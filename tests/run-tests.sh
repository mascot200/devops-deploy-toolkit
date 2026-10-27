#!/usr/bin/env bash
# tests/run-tests.sh - exercises the toolkit without any real infrastructure.
#   * fake ssh/terraform/helm/kubectl/argocd binaries record their arguments (control-flow tests)
#   * real git against a local bare repository (GitOps branch/commit/push/revert)
#   * a real local HTTP server (smoke test)
#   * structural checks of every agent and skill definition
# Usage: bash tests/run-tests.sh      Exit status 0 = all passed.
# shellcheck disable=SC2034  # "out" is read inside eval-ed check strings
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
SRV_PID=""
cleanup() {
  if [ -n "$SRV_PID" ]; then kill "$SRV_PID" 2>/dev/null; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
passed=0
failed=0

chk() { # chk <description> <command string evaluated in the current shell>
  if eval "$2"; then
    passed=$((passed + 1))
    printf '  ok    %s\n' "$1"
  else
    failed=$((failed + 1))
    printf '  FAIL  %s\n' "$1"
  fi
}
section() { printf '\n== %s\n' "$1"; }

for tool in git jq curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool for tests: $tool"; exit 2; }
done
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ------------------------------------------------------------------------------------------
section "agent and skill definitions"
for f in "$ROOT"/.claude/agents/*.md; do
  n="$(basename "$f" .md)"
  chk "agent $n: frontmatter name matches file" "[ \"\$(awk -F': *' '/^name:/{print \$2; exit}' '$f')\" = '$n' ]"
  chk "agent $n: has description and tools" "grep -q '^description: .\\+' '$f' && grep -q '^tools: .\\+' '$f'"
done
for ro in deploy-planner deploy-security-reviewer release-verifier drift-auditor; do
  chk "read-only agent $ro has no Edit/Write tools" "! grep '^tools:' '$ROOT/.claude/agents/$ro.md' | grep -Eq 'Edit|Write|NotebookEdit'"
  chk "read-only agent $ro contains no 'APPLY=1 <command>' invocation" "! grep -Eq 'APPLY=1 +(CONFIRM_PROD|ALLOW_DESTROY|ENVIRONMENT|bash|terraform|helm)' '$ROOT/.claude/agents/$ro.md'"
done
for d in "$ROOT"/.claude/skills/*/; do
  n="$(basename "$d")"
  chk "skill $n: SKILL.md name matches directory" "[ \"\$(awk -F': *' '/^name:/{print \$2; exit}' '$d/SKILL.md')\" = '$n' ]"
  chk "skill $n: has description" "grep -q '^description: .\\+' '$d/SKILL.md'"
done
chk "deployer requires the approval handshake" "grep -q 'APPROVED_PLAN' '$ROOT/.claude/agents/deployer.md' && grep -q 'USER_APPROVAL' '$ROOT/.claude/agents/deployer.md'"

# ------------------------------------------------------------------------------------------
section "smoke.sh (real local HTTP server)"
mkdir -p "$WORK/www" && echo ok >"$WORK/www/healthz"
python3 -m http.server 18765 --directory "$WORK/www" >/dev/null 2>&1 &
SRV_PID=$!
sleep 1
S="$ROOT/deploy/scripts/smoke.sh"
chk "passes on 200 with expected body" "EXPECT_BODY=ok bash '$S' http://127.0.0.1:18765/healthz 200 3 1 >/dev/null"
chk "fails when the body does not match" "! EXPECT_BODY=nope bash '$S' http://127.0.0.1:18765/healthz 200 2 1 >/dev/null"
chk "fails when status is never reached" "! bash '$S' http://127.0.0.1:18765/missing 200 2 1 >/dev/null"
chk "fails when latency limit is exceeded" "! MAX_LATENCY_MS=0 bash '$S' http://127.0.0.1:18765/healthz 200 2 1 >/dev/null"
kill "$SRV_PID" 2>/dev/null
SRV_PID=""

# ------------------------------------------------------------------------------------------
section "preflight.sh (throwaway git repository)"
PF="$WORK/pf"
mkdir -p "$PF" && (cd "$PF" && git init -q -b main && echo hi >a.txt && git add . && git commit -qm init)
chk "clean main + SHA tag passes (compose)" "(cd '$PF' && TARGET=compose bash '$ROOT/deploy/scripts/preflight.sh' abc1234 >/dev/null)"
chk "floating tag 'latest' fails" "! (cd '$PF' && TARGET=compose bash '$ROOT/deploy/scripts/preflight.sh' latest >/dev/null)"
echo x >>"$PF/a.txt"
chk "dirty working tree fails" "! (cd '$PF' && TARGET=compose bash '$ROOT/deploy/scripts/preflight.sh' abc1234 >/dev/null)"
(cd "$PF" && git checkout -q -- a.txt && git checkout -q -b feature/x)
chk "non-deployable branch fails" "! (cd '$PF' && TARGET=compose bash '$ROOT/deploy/scripts/preflight.sh' abc1234 >/dev/null)"
chk "ALLOW_BRANCH=1 downgrades to a warning" "(cd '$PF' && ALLOW_BRANCH=1 TARGET=compose bash '$ROOT/deploy/scripts/preflight.sh' abc1234 >/dev/null)"
(cd "$PF" && git checkout -q main && echo 'k=AKIAABCDEFGHIJKLMNOP' >conf.txt && git add . && git commit -qm leak)
chk "secret-looking string fails" "! (cd '$PF' && TARGET=compose bash '$ROOT/deploy/scripts/preflight.sh' abc1234 >/dev/null)"

# ------------------------------------------------------------------------------------------
# Fake binaries record their arguments in $STUBLOG
BIN="$WORK/bin"
mkdir -p "$BIN"
export STUBLOG="$WORK/stub.log"
cat >"$BIN/ssh" <<'EOF'
#!/usr/bin/env bash
echo "ssh $*" >>"$STUBLOG"
case "$*" in *current_tag*) echo "v1.0.0" ;; *previous_tag*) echo "v0.9.0" ;; esac
if [[ "$*" == *"bash -s"* ]]; then cat >>"$STUBLOG"; fi
exit 0
EOF
cat >"$BIN/terraform" <<'EOF'
#!/usr/bin/env bash
echo "terraform $*" >>"$STUBLOG"
args=" $* "
dir=.; [[ "$1" == -chdir=* ]] && dir="${1#-chdir=}"
case "$args" in
  *" plan "*) out=$(echo "$args" | sed -n 's/.*-out=\([^ ]*\).*/\1/p'); [ -n "$out" ] && : >"$dir/$out"; exit "${TF_PLAN_RC:-2}" ;;
  *" show "*) cat "$TF_JSON" ;;
esac
exit 0
EOF
for t in helm kubectl argocd; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"$STUBLOG"\nexit 0\n' "$t" >"$BIN/$t"
done
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

PROJ="$WORK/proj"
mkdir -p "$PROJ/deploy" "$PROJ/infra/envs/staging"
cat >"$PROJ/deploy/targets.staging.env" <<EOF
APP_NAME=shop-api
IMAGE=ghcr.io/acme/shop-api
HEALTH_URL=http://127.0.0.1:1/healthz
VPS_HOST=203.0.113.10
VPS_USER=deploy
VPS_APP_DIR=/opt/shop-api
TF_DIR=infra/envs/staging
TF_VAR_FILE=staging.tfvars
KUBE_CONTEXT=kind-staging
K8S_NAMESPACE=shop
HELM_RELEASE=shop-api
HELM_CHART=charts/shop-api
HELM_VALUES=charts/shop-api/values-staging.yaml
GITOPS_REPO_DIR=$WORK/gitops
GITOPS_OVERLAY_PATH=apps/shop-api/overlays/staging
ARGOCD_APP=shop-api-staging
EOF
sed 's/staging/production/g' "$PROJ/deploy/targets.staging.env" >"$PROJ/deploy/targets.production.env"
echo 'resource "x" "y" {}' >"$PROJ/infra/envs/staging/main.tf"
(cd "$PROJ" && git init -q -b main && git add . && git commit -qm init)
cd "$PROJ" || exit 2
D="$ROOT/deploy/scripts"

# ------------------------------------------------------------------------------------------
section "compose-deploy.sh"
: >"$STUBLOG"
out="$(bash "$D/compose-deploy.sh" deploy abc1234 2>&1)"
chk "dry-run exits 0" "[ \$? = 0 ] || true; echo \"\$out\" | grep -q 'MODE: DRY-RUN'"
chk "dry-run prints the remote script but does not run it" "echo \"\$out\" | grep -q 'docker compose' && ! grep -q 'bash -s' '$STUBLOG'"
chk "dry-run names the image and tag" "echo \"\$out\" | grep -q 'ghcr.io/acme/shop-api:abc1234'"
out="$(bash "$D/compose-deploy.sh" deploy latest 2>&1)"; rc=$?
chk "floating tag rejected" "[ $rc != 0 ] && echo \"\$out\" | grep -q floating"
out="$(ENVIRONMENT=production APPLY=1 bash "$D/compose-deploy.sh" deploy abc1234 2>&1)"; rc=$?
chk "production APPLY=1 without CONFIRM_PROD refused" "[ $rc != 0 ] && echo \"\$out\" | grep -q CONFIRM_PROD"
: >"$STUBLOG"
out="$(APPLY=1 SMOKE_RETRIES=1 SMOKE_SLEEP=0 bash "$D/compose-deploy.sh" deploy abc1234 2>&1)"; rc=$?
chk "APPLY=1 runs the deploy script over ssh" "grep -q 'bash -s' '$STUBLOG' && grep -q 'IMAGE_TAG=\"abc1234\"' '$STUBLOG'"
chk "failed health check -> nonzero exit with rollback hint" "[ $rc != 0 ] && echo \"\$out\" | grep -q rollback"
: >"$STUBLOG"
out="$(APPLY=1 AUTO_ROLLBACK=1 SMOKE_RETRIES=1 SMOKE_SLEEP=0 bash "$D/compose-deploy.sh" deploy abc1234 2>&1)"
chk "AUTO_ROLLBACK=1 rolls back after a failed health check" "echo \"\$out\" | grep -q 'AUTO_ROLLBACK=1' && grep -q 'previous_tag' '$STUBLOG'"

# ------------------------------------------------------------------------------------------
section "terraform.sh"
cat >"$WORK/plan_del.json" <<'EOF'
{"resource_changes":[{"address":"aws_instance.a","change":{"actions":["create"]}},{"address":"aws_db_instance.db","change":{"actions":["delete","create"]}}]}
EOF
cat >"$WORK/plan_ok.json" <<'EOF'
{"resource_changes":[{"address":"aws_instance.a","change":{"actions":["create"]}},{"address":"aws_s3_bucket.b","change":{"actions":["update"]}}]}
EOF
export TF_JSON="$WORK/plan_del.json"
out="$(bash "$D/terraform.sh" plan 2>&1)"; rc=$?
chk "plan succeeds and flags the replacement" "[ $rc = 0 ] && echo \"\$out\" | grep -q 'delete_or_replace=1' && echo \"\$out\" | grep -q aws_db_instance.db"
out="$(APPLY=1 bash "$D/terraform.sh" apply 2>&1)"; rc=$?
chk "apply refuses a plan with a replacement" "[ $rc != 0 ] && echo \"\$out\" | grep -q ALLOW_DESTROY"
: >"$STUBLOG"
out="$(APPLY=1 ALLOW_DESTROY=1 bash "$D/terraform.sh" apply 2>&1)"; rc=$?
chk "ALLOW_DESTROY=1 applies the saved plan and never re-plans" "[ $rc = 0 ] && grep -q 'apply -input=false -no-color tfplan' '$STUBLOG' && ! grep -q ' plan ' '$STUBLOG'"
out="$(APPLY=1 bash "$D/terraform.sh" apply 2>&1)"; rc=$?
chk "plan file is consumed (second apply refused)" "[ $rc != 0 ] && echo \"\$out\" | grep -q 'no saved plan'"
export TF_JSON="$WORK/plan_ok.json"
bash "$D/terraform.sh" plan >/dev/null 2>&1
echo 1 >"$PROJ/infra/envs/staging/tfplan.time"
out="$(APPLY=1 bash "$D/terraform.sh" apply 2>&1)"; rc=$?
chk "stale plan refused" "[ $rc != 0 ] && echo \"\$out\" | grep -q old"
bash "$D/terraform.sh" plan >/dev/null 2>&1
git commit -q --allow-empty -m "after plan"
out="$(APPLY=1 bash "$D/terraform.sh" apply 2>&1)"; rc=$?
chk "plan made from a different commit refused" "[ $rc != 0 ] && echo \"\$out\" | grep -q 'different commit'"
TF_PLAN_RC=2 bash "$D/terraform.sh" drift >/dev/null 2>&1; rc=$?
chk "drift detected -> exit 3" "[ $rc = 3 ]"
TF_PLAN_RC=0 bash "$D/terraform.sh" drift >/dev/null 2>&1; rc=$?
chk "no drift -> exit 0" "[ $rc = 0 ]"

# ------------------------------------------------------------------------------------------
section "helm-deploy.sh"
: >"$STUBLOG"
bash "$D/helm-deploy.sh" deploy abc1234 >/dev/null 2>&1; rc=$?
chk "dry-run only invokes 'helm upgrade' with --dry-run" "[ $rc = 0 ] && [ \"\$(grep -c 'helm upgrade' '$STUBLOG')\" = 1 ] && grep 'helm upgrade' '$STUBLOG' | grep -q -- --dry-run"
: >"$STUBLOG"
APPLY=1 bash "$D/helm-deploy.sh" deploy abc1234 >/dev/null 2>&1
chk "APPLY=1 upgrades with --atomic --wait and checks rollout" "grep -q -- '--atomic --wait' '$STUBLOG' && grep -q 'rollout status' '$STUBLOG'"
chk "explicit --kube-context is always passed" "grep 'helm upgrade' '$STUBLOG' | grep -q -- '--kube-context kind-staging'"
: >"$STUBLOG"
APPLY=1 bash "$D/helm-deploy.sh" rollback >/dev/null 2>&1
chk "rollback without a revision goes to the previous one" "grep -q 'helm rollback shop-api --namespace' '$STUBLOG'"
: >"$STUBLOG"
APPLY=1 bash "$D/helm-deploy.sh" rollback 7 >/dev/null 2>&1
chk "rollback to revision 7" "grep -q 'helm rollback shop-api 7 ' '$STUBLOG'"

# ------------------------------------------------------------------------------------------
section "gitops-promote.sh (real git, local bare origin)"
O="$WORK/origin.git"
G="$WORK/gitops"
git init -q --bare "$O"
git clone -q "$O" "$G" 2>/dev/null
(cd "$G" && git checkout -q -b main && mkdir -p apps/shop-api/overlays/staging &&
  printf 'images:\n  - name: ghcr.io/acme/shop-api\n    newTag: v1.0.0\n' >apps/shop-api/overlays/staging/kustomization.yaml &&
  git add . && git commit -qm base && git push -q -u origin main 2>/dev/null)
KF=apps/shop-api/overlays/staging/kustomization.yaml
bash "$D/gitops-promote.sh" bump abc1234 >/dev/null 2>&1; rc=$?
chk "dry-run bump changes nothing" "[ $rc = 0 ] && grep -q 'newTag: v1.0.0' '$G/$KF' && [ \"\$(git -C '$G' branch --show-current)\" = main ]"
APPLY=1 bash "$D/gitops-promote.sh" bump abc1234 >/dev/null 2>&1; rc=$?
chk "APPLY=1 bump pushes a promote branch with the new tag" "[ $rc = 0 ] && git -C '$O' show promote/shop-api-staging-abc1234:$KF | grep -q 'newTag: abc1234'"
promo="$(git -C "$G" rev-parse HEAD)"
out="$(APPLY=1 bash "$D/gitops-promote.sh" rollback "$promo" 2>&1)"; rc=$?
chk "rollback of an UNMERGED promotion is refused clearly" "[ $rc != 0 ] && echo \"\$out\" | grep -q 'never merged'"
(cd "$G" && git checkout -q main && git merge -q --no-ff -m "Merge PR abc1234" promote/shop-api-staging-abc1234 && git push -q origin main 2>/dev/null)
mc="$(git -C "$G" rev-parse HEAD)"
APPLY=1 bash "$D/gitops-promote.sh" rollback "$mc" >/dev/null 2>&1; rc=$?
chk "rollback of a merge commit uses -m 1 and restores v1.0.0" "[ $rc = 0 ] && git -C '$O' show rollback/shop-api-staging-${mc:0:8}:$KF | grep -q 'newTag: v1.0.0'"
out="$(APPLY=1 bash "$D/gitops-promote.sh" rollback deadbeefdeadbeef 2>&1)"; rc=$?
chk "unknown commit rejected" "[ $rc != 0 ] && echo \"\$out\" | grep -q 'not found'"
: >"$STUBLOG"
APPLY=1 bash "$D/gitops-promote.sh" sync >/dev/null 2>&1
chk "sync runs argocd sync then waits for health" "grep -q 'argocd app sync shop-api-staging' '$STUBLOG' && grep -q 'argocd app wait shop-api-staging --health' '$STUBLOG'"
bash "$D/gitops-promote.sh" bump latest >/dev/null 2>&1; rc=$?
chk "floating tag rejected" "[ $rc != 0 ]"

# ------------------------------------------------------------------------------------------
section "install.sh"
APP="$WORK/app"
mkdir -p "$APP" && (cd "$APP" && git init -q -b main && echo '# My app' >CLAUDE.md && git add . && git commit -qm init)
bash "$ROOT/install.sh" --dry-run "$APP" >/dev/null 2>&1
chk "--dry-run changes nothing" "[ ! -d '$APP/.claude' ] && [ ! -d '$APP/deploy' ]"
bash "$ROOT/install.sh" "$APP" >/dev/null 2>&1; rc=$?
chk "installs agents, skills and scripts" "[ $rc = 0 ] && [ -f '$APP/.claude/agents/deployer.md' ] && [ -f '$APP/.claude/skills/deploy-preflight/SKILL.md' ] && [ -x '$APP/deploy/scripts/helm-deploy.sh' ]"
chk "keeps the app's existing CLAUDE.md and appends a marked block" "head -1 '$APP/CLAUDE.md' | grep -q 'My app' && grep -q 'deploy-toolkit:start' '$APP/CLAUDE.md'"
chk "adds git-ignore entries" "grep -q 'deploy/targets' '$APP/.gitignore'"
out="$(bash "$ROOT/install.sh" "$APP" 2>&1)"
chk "second run is idempotent" "echo \"\$out\" | grep -q '0 added/updated' && [ \"\$(grep -c 'deploy-toolkit:start' '$APP/CLAUDE.md')\" = 1 ] && [ \"\$(grep -c 'deploy-toolkit: local files' '$APP/.gitignore')\" = 1 ]"
echo '# local edit' >>"$APP/.claude/agents/deployer.md"
out="$(bash "$ROOT/install.sh" "$APP" 2>&1)"
chk "a locally edited file is skipped, not overwritten" "echo \"\$out\" | grep -q 'SKIP' && grep -q 'local edit' '$APP/.claude/agents/deployer.md'"
bash "$ROOT/install.sh" --force "$APP" >/dev/null 2>&1
chk "--force overwrites it" "! grep -q 'local edit' '$APP/.claude/agents/deployer.md'"
bash "$ROOT/install.sh" "$ROOT" >/dev/null 2>&1; rc=$?
chk "refuses to install into the toolkit itself" "[ $rc != 0 ]"
mkdir -p "$WORK/notgit"
bash "$ROOT/install.sh" "$WORK/notgit" >/dev/null 2>&1; rc=$?
chk "refuses a directory that is not a git repository" "[ $rc != 0 ]"

# ------------------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
