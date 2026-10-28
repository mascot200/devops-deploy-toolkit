#!/usr/bin/env bash
# deploy/lib/common.sh - shared helpers for the deploy scripts. Source it; do not execute it.
#
# Safety model
#   * Every script is a DRY RUN unless APPLY=1 is set in the environment.
#   * Commands that change anything go through run() / remote(); they only execute with APPLY=1.
#   * Commands that only read go through ro(); they always execute.
#   * Changing production additionally needs CONFIRM_PROD=yes-deploy-prod.

set -Eeuo pipefail

APPLY="${APPLY:-0}"
ENVIRONMENT="${ENVIRONMENT:-staging}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"; }

# run: a command that CHANGES something. Printed in dry-run mode, executed only with APPLY=1.
run() {
  if [ "$APPLY" = "1" ]; then
    log "RUN     $*"
    "$@"
  else
    log "DRYRUN  $*"
  fi
}

# ro: a read-only command. Always executed.
ro() {
  log "READ    $*"
  "$@"
}

# load_targets: source deploy/targets.<ENVIRONMENT>.env (or $TARGETS_FILE) and export its variables.
load_targets() {
  local file="${TARGETS_FILE:-deploy/targets.${ENVIRONMENT}.env}"
  [ -f "$file" ] || die "targets file not found: $file (copy deploy/targets.example.env to it and edit)"
  set -a
  # shellcheck disable=SC1090
  . "$file"
  set +a
}

# require_vars VAR...: fail with a clear message if a variable is missing from the targets file.
require_vars() {
  local v
  for v in "$@"; do
    [ -n "${!v:-}" ] || die "variable $v is not set in the targets file"
  done
}

# reject_floating_tag TAG: deploying "latest" makes rollback and audit impossible.
reject_floating_tag() {
  [ -n "${1:-}" ] || die "an image tag is required (commit SHA or semver)"
  case "$1" in
    latest | main | master | stable | dev) die "refusing floating tag '$1' - deploy an immutable tag (git SHA or vX.Y.Z)" ;;
  esac
}

# guard_production: with APPLY=1 in production, require an explicit confirmation variable.
guard_production() {
  if [ "$APPLY" = "1" ] && [ "$ENVIRONMENT" = "production" ] && [ "${CONFIRM_PROD:-}" != "yes-deploy-prod" ]; then
    die "refusing to change production without CONFIRM_PROD=yes-deploy-prod (set it only after the user approved this exact plan)"
  fi
}

mode_banner() {
  if [ "$APPLY" = "1" ]; then
    log "MODE: APPLY  environment=$ENVIRONMENT  (changes WILL be made)"
  else
    log "MODE: DRY-RUN  environment=$ENVIRONMENT  (nothing will be changed; set APPLY=1 to apply)"
  fi
}

# remote: run a script (read from stdin) on the VPS over SSH. Printed in dry-run mode.
# REMOTE_SHELL (default "bash -s") lets a caller use "sudo bash -s" for root-level setup.
remote() {
  local script shell="${REMOTE_SHELL:-bash -s}"
  script="$(cat)"
  if [ "$APPLY" = "1" ]; then
    log "SSH     ${VPS_USER}@${VPS_HOST}  ($shell)"
    ssh -o BatchMode=yes -o ConnectTimeout=10 "${VPS_USER}@${VPS_HOST}" "$shell" <<<"$script"
  else
    log "DRYRUN  ssh ${VPS_USER}@${VPS_HOST} '$shell'  <- script below"
    sed 's/^/          | /' <<<"$script" >&2
  fi
}

# upload_dir LOCAL_DIR REMOTE_DIR: copy a directory's files to the VPS (tar over ssh). Printed in dry-run mode.
# Files that exist on the server and are not in LOCAL_DIR are left alone (for example the server-side .env).
upload_dir() {
  local src="$1" dest="$2"
  [ -d "$src" ] || die "directory not found: $src"
  if [ "$APPLY" = "1" ]; then
    log "UPLOAD  $src -> ${VPS_USER}@${VPS_HOST}:$dest"
    tar -C "$src" -cf - . | ssh -o BatchMode=yes -o ConnectTimeout=10 "${VPS_USER}@${VPS_HOST}" "mkdir -p '$dest' && tar -C '$dest' -xf -"
  else
    log "DRYRUN  upload $src -> ${VPS_USER}@${VPS_HOST}:$dest  files:"
    (cd "$src" && find . -type f | LC_ALL=C sort | sed 's/^/          | /') >&2
  fi
}
