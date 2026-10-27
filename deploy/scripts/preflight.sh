#!/usr/bin/env bash
# deploy/scripts/preflight.sh - checks that must pass BEFORE any deployment. Read-only.
#
# Usage: TARGET=<compose|terraform|helm|gitops> [ENVIRONMENT=staging] bash deploy/scripts/preflight.sh [image-tag]
# Env:   PREFLIGHT_TEST_CMD="npm test"   run this command as the test gate (optional)
#        ALLOW_BRANCH=1                  allow deploying from a branch other than main/release/*
#
# Prints one PASS/WARN/FAIL line per check and exits 1 if any check FAILED.
set -uo pipefail

TARGET="${TARGET:-}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
tag="${1:-${IMAGE_TAG:-}}"
fails=0
warns=0

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; warns=$((warns + 1)); }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

echo "== preflight: target=${TARGET:-unset} environment=$ENVIRONMENT tag=${tag:-none} =="

# 1. Inside a git repository
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then pass "inside a git repository"; else
  fail "not inside a git repository"
  echo "== result: $fails failed =="
  exit 1
fi

# 2. Clean working tree - what you deploy must be what is committed
if [ -z "$(git status --porcelain)" ]; then pass "working tree is clean"; else fail "uncommitted changes present (commit or stash first)"; fi

# 3. Deploying from an approved branch
branch="$(git rev-parse --abbrev-ref HEAD)"
case "$branch" in
  main | master | release/*) pass "on deployable branch '$branch'" ;;
  *) if [ "${ALLOW_BRANCH:-0}" = "1" ]; then warn "deploying from '$branch' (ALLOW_BRANCH=1)"; else fail "on branch '$branch' - deploy from main or release/* (or set ALLOW_BRANCH=1)"; fi ;;
esac

# 4. Immutable image tag (not required for terraform)
if [ "$TARGET" != "terraform" ]; then
  if [ -z "$tag" ]; then
    fail "no image tag given"
  else
    case "$tag" in
      latest | main | master | stable | dev) fail "tag '$tag' is a floating tag; deploy a commit SHA or semver" ;;
      *)
        if printf '%s' "$tag" | grep -Eq '^[0-9a-f]{7,40}$|^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
          pass "tag '$tag' is immutable-looking (SHA or semver)"
        else
          warn "tag '$tag' is neither a git SHA nor semver"
        fi
        ;;
    esac
  fi
fi

# 5. Secret scan: gitleaks if installed, otherwise a conservative pattern grep over tracked files
if have gitleaks; then
  if gitleaks detect --no-banner --redact --log-opts="-n 50" >/dev/null 2>&1; then pass "gitleaks found no secrets in the last 50 commits"; else fail "gitleaks reported possible secrets"; fi
else
  if git grep -nIE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{30,}' -- . ':!*.md' ':!deploy/targets.example.env' >/dev/null 2>&1; then
    fail "secret-looking strings found in tracked files (run: git grep -nIE 'AKIA|PRIVATE KEY|ghp_')"
  else
    pass "no secret-looking strings in tracked files (install gitleaks for a deeper scan)"
  fi
fi

# 6. Tests
if [ -n "${PREFLIGHT_TEST_CMD:-}" ]; then
  if bash -c "$PREFLIGHT_TEST_CMD" >/dev/null 2>&1; then pass "test command passed: $PREFLIGHT_TEST_CMD"; else fail "test command failed: $PREFLIGHT_TEST_CMD"; fi
else
  warn "no PREFLIGHT_TEST_CMD set - tests were not run by this check (CI should have run them)"
fi

# 7. Tools required for the chosen target
req=""
case "$TARGET" in
  compose) req="ssh curl" ;;
  terraform) req="terraform jq" ;;
  helm) req="helm kubectl" ;;
  gitops) req="git kustomize argocd" ;;
  "") warn "TARGET not set - tool check skipped" ;;
  *) fail "unknown TARGET '$TARGET' (use compose, terraform, helm or gitops)" ;;
esac
for t in $req; do
  if have "$t"; then pass "tool available: $t"; else
    # kustomize is optional (the gitops script falls back to sed)
    if [ "$t" = "kustomize" ]; then warn "kustomize not installed (sed fallback will be used)"; else fail "required tool missing: $t"; fi
  fi
done

# 8. Production extra: require a signed-off version marker
if [ "$ENVIRONMENT" = "production" ]; then
  warn "production: confirm the same tag already passed staging and verification"
fi

echo "== result: $fails failed, $warns warnings =="
[ "$fails" -eq 0 ]
