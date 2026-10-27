#!/usr/bin/env bash
# deploy/scripts/helm-deploy.sh - deploy a Helm release to Kubernetes.
#
# Usage: ENVIRONMENT=staging bash deploy/scripts/helm-deploy.sh diff <image-tag>
#        ENVIRONMENT=staging APPLY=1 bash deploy/scripts/helm-deploy.sh deploy <image-tag>
#        ENVIRONMENT=staging APPLY=1 bash deploy/scripts/helm-deploy.sh rollback [revision]
#        ENVIRONMENT=staging bash deploy/scripts/helm-deploy.sh status
#
# diff      lint + template + `helm diff` (or a client-side dry-run if the diff plugin is missing). Read-only.
# deploy    helm upgrade --install --atomic --wait: if the new pods never become Ready, Helm rolls back by itself.
# rollback  helm rollback to the previous revision (or the given one) and wait for readiness.
# Chart contract: image.tag is the value that selects the version.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

cmd="${1:-}"
tag="${2:-}"
load_targets
require_vars KUBE_CONTEXT K8S_NAMESPACE HELM_RELEASE HELM_CHART HELM_VALUES
need helm
need kubectl
mode_banner

ctx=(--kube-context "$KUBE_CONTEXT")
common_args=("$HELM_RELEASE" "$HELM_CHART" --namespace "$K8S_NAMESPACE" "${ctx[@]}" -f "$HELM_VALUES")

do_diff() {
  reject_floating_tag "$tag"
  ro helm lint "$HELM_CHART" -f "$HELM_VALUES" --set image.tag="$tag"
  ro helm template "$HELM_RELEASE" "$HELM_CHART" --namespace "$K8S_NAMESPACE" -f "$HELM_VALUES" --set image.tag="$tag" >/dev/null
  if helm plugin list 2>/dev/null | grep -q '^diff'; then
    ro helm diff upgrade "${common_args[@]}" --set image.tag="$tag" --context 3 || true
  else
    log "helm-diff plugin not installed (helm plugin install https://github.com/databus23/helm-diff) - showing a dry-run instead"
    ro helm upgrade --install "${common_args[@]}" --set image.tag="$tag" --dry-run >/dev/null
    log "dry-run rendered successfully"
  fi
  ro helm history "$HELM_RELEASE" --namespace "$K8S_NAMESPACE" "${ctx[@]}" --max 5 || log "no existing release history (first install)"
}

do_deploy() {
  reject_floating_tag "$tag"
  guard_production
  do_diff
  run helm upgrade --install "${common_args[@]}" --set image.tag="$tag" \
    --atomic --wait --timeout 5m --history-max 10 --create-namespace
  if [ "$APPLY" = "1" ]; then
    ro kubectl --context "$KUBE_CONTEXT" -n "$K8S_NAMESPACE" rollout status "deployment/$HELM_RELEASE" --timeout=300s
    ro kubectl --context "$KUBE_CONTEXT" -n "$K8S_NAMESPACE" get pods -l "app.kubernetes.io/instance=$HELM_RELEASE"
  fi
}

do_rollback() {
  guard_production
  ro helm history "$HELM_RELEASE" --namespace "$K8S_NAMESPACE" "${ctx[@]}" --max 8
  # `helm rollback <release>` with no revision goes to the previous one.
  run helm rollback "$HELM_RELEASE" ${tag:+"$tag"} --namespace "$K8S_NAMESPACE" "${ctx[@]}" --wait --timeout 5m
}

do_status() {
  ro helm status "$HELM_RELEASE" --namespace "$K8S_NAMESPACE" "${ctx[@]}"
  ro helm history "$HELM_RELEASE" --namespace "$K8S_NAMESPACE" "${ctx[@]}" --max 8
  ro kubectl --context "$KUBE_CONTEXT" -n "$K8S_NAMESPACE" get deploy,pods,svc,ingress -l "app.kubernetes.io/instance=$HELM_RELEASE"
}

case "$cmd" in
  diff) do_diff ;;
  deploy) do_deploy ;;
  rollback) do_rollback ;; # for rollback, the 2nd argument is an optional revision number
  status) do_status ;;
  *) die "usage: helm-deploy.sh diff <tag> | deploy <tag> | rollback [revision] | status" ;;
esac
