#!/usr/bin/env bash
# deploy/scripts/gitops-promote.sh - promote a version through a GitOps repository watched by Argo CD.
#
# Usage: ENVIRONMENT=staging bash deploy/scripts/gitops-promote.sh bump <image-tag>
#        ENVIRONMENT=staging bash deploy/scripts/gitops-promote.sh diff
#        ENVIRONMENT=staging bash deploy/scripts/gitops-promote.sh status
#        ENVIRONMENT=staging APPLY=1 bash deploy/scripts/gitops-promote.sh sync
#        ENVIRONMENT=staging APPLY=1 bash deploy/scripts/gitops-promote.sh rollback <gitops-commit-sha>
#
# GitOps rule: the cluster is changed by a commit to the GitOps repo, never by kubectl. So:
#   bump      creates a branch in the GitOps repo with the new image tag and pushes it. A HUMAN (or the
#             team's auto-merge rules for staging) merges the pull request - that merge is the deployment.
#   diff      shows what Argo CD would change (live vs Git). Read-only.
#   status    shows Argo CD sync + health. Read-only.
#   sync      forces a sync when auto-sync is off, then waits for Healthy.
#   rollback  `git revert` of a bad promotion commit on a branch, pushed for a pull request.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

cmd="${1:-}"
arg="${2:-}"
load_targets
require_vars IMAGE GITOPS_REPO_DIR GITOPS_OVERLAY_PATH ARGOCD_APP APP_NAME
base="${GITOPS_BASE_BRANCH:-main}"
mode_banner

in_repo() { (cd "$GITOPS_REPO_DIR" && "$@"); }

do_bump() {
  local tag="$arg"
  reject_floating_tag "$tag"
  guard_production
  need git
  [ -d "$GITOPS_REPO_DIR/.git" ] || die "GITOPS_REPO_DIR is not a git clone: $GITOPS_REPO_DIR"
  [ -z "$(in_repo git status --porcelain)" ] || die "GitOps repo has uncommitted changes - clean it first"
  local branch="promote/${APP_NAME}-${ENVIRONMENT}-${tag}"
  ro in_repo git fetch origin "$base"
  run in_repo git checkout -B "$branch" "origin/$base"
  if command -v kustomize >/dev/null 2>&1; then
    run in_repo bash -c "cd '$GITOPS_OVERLAY_PATH' && kustomize edit set image '${IMAGE}=${IMAGE}:${tag}'"
  else
    log "kustomize not installed - falling back to sed on kustomization.yaml (newTag)"
    run in_repo sed -i -E "s|^([[:space:]]*newTag:).*|\\1 ${tag}|" "$GITOPS_OVERLAY_PATH/kustomization.yaml"
  fi
  run in_repo git add -A
  run in_repo git commit -m "promote(${ENVIRONMENT}): ${APP_NAME} -> ${tag}"
  run in_repo git push -u origin "$branch"
  log "next: open a pull request '$branch' -> '$base'. Merging it IS the deployment; Argo CD syncs after the merge."
}

do_diff() {
  need argocd
  # argocd app diff exits 1 when there IS a difference, which is information, not an error.
  ro argocd app diff "$ARGOCD_APP" || log "(exit 1 from argocd app diff means a difference was found)"
}

do_status() {
  need argocd
  ro argocd app get "$ARGOCD_APP"
}

do_sync() {
  need argocd
  guard_production
  run argocd app sync "$ARGOCD_APP"
  run argocd app wait "$ARGOCD_APP" --health --timeout 300
}

do_rollback() {
  local sha="$arg"
  [ -n "$sha" ] || die "usage: rollback <gitops-commit-sha of the bad promotion>"
  guard_production
  need git
  local branch="rollback/${APP_NAME}-${ENVIRONMENT}-${sha:0:8}"
  ro in_repo git fetch origin "$base"
  in_repo git cat-file -e "${sha}^{commit}" 2>/dev/null || die "commit $sha not found in the GitOps repo"
  # A rollback only makes sense for a promotion that was MERGED (that is what Argo CD deployed).
  in_repo git merge-base --is-ancestor "$sha" "origin/$base" ||
    die "commit $sha is not in origin/$base - that promotion was never merged, so there is nothing to roll back (close the pull request instead)"
  # A pull request merged with a merge commit has two parents and must be reverted relative to parent 1.
  local mainline=()
  if [ "$(in_repo git rev-list --parents -n 1 "$sha" | wc -w)" -gt 2 ]; then mainline=(-m 1); fi
  run in_repo git checkout -B "$branch" "origin/$base"
  run in_repo git revert --no-edit "${mainline[@]}" "$sha"
  run in_repo git push -u origin "$branch"
  log "next: open a pull request '$branch' -> '$base' and merge it; Argo CD will restore the previous version."
}

case "$cmd" in
  bump) do_bump ;;
  diff) do_diff ;;
  status) do_status ;;
  sync) do_sync ;;
  rollback) do_rollback ;;
  *) die "usage: gitops-promote.sh bump <tag> | diff | status | sync | rollback <sha>" ;;
esac
