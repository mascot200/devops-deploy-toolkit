#!/usr/bin/env bash
# deploy/scripts/compose-deploy.sh - deploy a Docker Compose app to a VPS over SSH.
#
# Env:   SMOKE_RETRIES (default 30) and SMOKE_SLEEP (default 2s) tune the post-deploy health wait.
# Usage: ENVIRONMENT=staging bash deploy/scripts/compose-deploy.sh deploy <image-tag>
#        ENVIRONMENT=staging bash deploy/scripts/compose-deploy.sh rollback
#        ENVIRONMENT=staging bash deploy/scripts/compose-deploy.sh status
# DRY-RUN unless APPLY=1.  Production additionally needs CONFIRM_PROD=yes-deploy-prod.
#
# Server contract: $VPS_APP_DIR holds the compose file; the compose file uses
#   image: ${IMAGE}:${IMAGE_TAG}
# The script records .deploy/current_tag and .deploy/previous_tag on the server, which is what
# makes `rollback` a one-liner.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

cmd="${1:-}"
tag="${2:-}"
load_targets
require_vars VPS_HOST VPS_USER VPS_APP_DIR HEALTH_URL IMAGE
COMPOSE_FILE="${COMPOSE_FILE:-compose.yaml}"
mode_banner

ssh_ro() { ssh -o BatchMode=yes -o ConnectTimeout=10 "${VPS_USER}@${VPS_HOST}" "$@"; }

show_state() {
  local cur prev
  cur="$(ssh_ro "cat '$VPS_APP_DIR/.deploy/current_tag' 2>/dev/null" 2>/dev/null || true)"
  prev="$(ssh_ro "cat '$VPS_APP_DIR/.deploy/previous_tag' 2>/dev/null" 2>/dev/null || true)"
  log "server state: current=${cur:-unknown} previous=${prev:-none}"
}

do_status() {
  show_state
  ro ssh_ro "cd '$VPS_APP_DIR' && docker compose -f '$COMPOSE_FILE' ps"
  ro bash "$HERE/smoke.sh" "$HEALTH_URL" 200 1 1 || true
}

do_deploy() {
  reject_floating_tag "$tag"
  guard_production
  show_state
  log "plan: ${IMAGE}:${tag} -> ${VPS_USER}@${VPS_HOST}:${VPS_APP_DIR}"
  remote <<EOF
set -Eeuo pipefail
cd "$VPS_APP_DIR"
mkdir -p .deploy
if [ -s .deploy/current_tag ]; then cp .deploy/current_tag .deploy/previous_tag; fi
echo "$tag" > .deploy/current_tag
export IMAGE="$IMAGE" IMAGE_TAG="$tag"
docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
docker compose -f "$COMPOSE_FILE" ps
EOF
  if [ "$APPLY" = "1" ]; then
    if ! bash "$HERE/smoke.sh" "$HEALTH_URL" 200 "${SMOKE_RETRIES:-30}" "${SMOKE_SLEEP:-2}"; then
      if [ "${AUTO_ROLLBACK:-0}" = "1" ]; then
        log "health check FAILED - AUTO_ROLLBACK=1, rolling back"
        do_rollback
        die "deployment of $tag failed verification and was rolled back"
      fi
      die "health check FAILED for $tag - run: ENVIRONMENT=$ENVIRONMENT APPLY=1 bash deploy/scripts/compose-deploy.sh rollback"
    fi
    log "deployment of $tag is healthy"
  else
    log "DRYRUN  bash $HERE/smoke.sh $HEALTH_URL   (runs after a real deploy)"
  fi
}

do_rollback() {
  guard_production
  show_state
  remote <<EOF
set -Eeuo pipefail
cd "$VPS_APP_DIR"
[ -s .deploy/previous_tag ] || { echo "no previous tag recorded - cannot roll back" >&2; exit 1; }
prev="\$(cat .deploy/previous_tag)"
cur="\$(cat .deploy/current_tag 2>/dev/null || true)"
echo "\$prev" > .deploy/current_tag
if [ -n "\$cur" ]; then echo "\$cur" > .deploy/previous_tag; fi
export IMAGE="$IMAGE" IMAGE_TAG="\$prev"
docker compose -f "$COMPOSE_FILE" pull --quiet || true
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans
docker compose -f "$COMPOSE_FILE" ps
EOF
  if [ "$APPLY" = "1" ]; then bash "$HERE/smoke.sh" "$HEALTH_URL" 200 "${SMOKE_RETRIES:-30}" "${SMOKE_SLEEP:-2}" || die "still unhealthy after rollback - escalate"; fi
}

case "$cmd" in
  deploy) do_deploy ;;
  rollback) do_rollback ;;
  status) do_status ;;
  *) die "usage: compose-deploy.sh deploy <tag> | rollback | status" ;;
esac
