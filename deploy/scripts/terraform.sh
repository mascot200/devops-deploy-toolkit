#!/usr/bin/env bash
# deploy/scripts/terraform.sh - plan / apply / drift for an AWS environment managed by Terraform.
#
# Usage: ENVIRONMENT=staging bash deploy/scripts/terraform.sh plan
#        ENVIRONMENT=staging APPLY=1 bash deploy/scripts/terraform.sh apply
#        ENVIRONMENT=staging bash deploy/scripts/terraform.sh drift
#
# plan   init, fmt -check, validate, then `plan -out=tfplan`; prints a create/update/delete summary.
#        (read-only: it changes no infrastructure)
# apply  applies ONLY the saved tfplan - never re-plans. Refuses if the plan is stale (older than
#        PLAN_MAX_AGE seconds, default 3600), was made from a different commit, or deletes/replaces
#        anything (unless ALLOW_DESTROY=1). Production needs CONFIRM_PROD=yes-deploy-prod.
# drift  `plan -refresh-only`: exit 0 = no drift, exit 3 = drift detected. Never changes anything.
#
# Credentials come from your environment (aws sso login / OIDC role). Nothing is stored here.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

cmd="${1:-}"
load_targets
require_vars TF_DIR
need terraform
need jq
mode_banner

tf() { terraform -chdir="$TF_DIR" "$@"; }
varfile=()
if [ -n "${TF_VAR_FILE:-}" ]; then varfile=(-var-file="$TF_VAR_FILE"); fi
planfile="tfplan"
planpath="$TF_DIR/$planfile"

summarise() {
  tf show -json "$planfile" >"$planpath.json"
  local c u d
  c="$(jq '[.resource_changes[]? | select(.change.actions == ["create"])] | length' "$planpath.json")"
  u="$(jq '[.resource_changes[]? | select(.change.actions == ["update"])] | length' "$planpath.json")"
  d="$(jq '[.resource_changes[]? | select(.change.actions | index("delete"))] | length' "$planpath.json")"
  log "plan summary: create=$c update=$u delete_or_replace=$d"
  if [ "$d" -gt 0 ]; then
    log "WARNING: these resources will be DELETED or REPLACED:"
    jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | "  - \(.address)  (\(.change.actions | join(",")))"' "$planpath.json" >&2
  fi
  echo "$d" >"$planpath.deletes"
}

do_plan() {
  ro tf init -input=false -no-color
  ro tf fmt -check -recursive -no-color
  ro tf validate -no-color
  local rc=0
  log "READ    terraform -chdir=$TF_DIR plan -out=$planfile (read-only)"
  tf plan -input=false -no-color -detailed-exitcode -out="$planfile" "${varfile[@]}" || rc=$?
  case "$rc" in
    0) log "no changes - infrastructure matches the code"; rm -f "$planpath.deletes" ;;
    2)
      git rev-parse HEAD >"$planpath.sha" 2>/dev/null || echo unknown >"$planpath.sha"
      date +%s >"$planpath.time"
      summarise
      log "saved $planpath - review it, then: ENVIRONMENT=$ENVIRONMENT APPLY=1 bash deploy/scripts/terraform.sh apply"
      ;;
    *) die "terraform plan failed (exit $rc)" ;;
  esac
}

do_apply() {
  guard_production
  [ -f "$planpath" ] || die "no saved plan at $planpath - run the plan step first"
  local age max=${PLAN_MAX_AGE:-3600} made head deletes
  made="$(cat "$planpath.time" 2>/dev/null || echo 0)"
  age=$(($(date +%s) - made))
  [ "$age" -le "$max" ] || die "saved plan is ${age}s old (limit ${max}s) - re-run plan so you apply what you reviewed"
  head="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  [ "$(cat "$planpath.sha" 2>/dev/null)" = "$head" ] || die "plan was made from a different commit - re-run plan"
  deletes="$(cat "$planpath.deletes" 2>/dev/null || echo 0)"
  if [ "$deletes" -gt 0 ] && [ "${ALLOW_DESTROY:-0}" != "1" ]; then
    die "plan deletes/replaces $deletes resource(s); set ALLOW_DESTROY=1 only if the user approved that explicitly"
  fi
  run terraform -chdir="$TF_DIR" apply -input=false -no-color "$planfile"
  if [ "$APPLY" = "1" ]; then
    rm -f "$planpath" "$planpath".*
    ro tf output
  fi
}

do_drift() {
  ro tf init -input=false -no-color
  local rc=0
  tf plan -refresh-only -input=false -no-color -detailed-exitcode "${varfile[@]}" || rc=$?
  case "$rc" in
    0) log "no drift - real infrastructure matches state" ;;
    2) log "DRIFT DETECTED - real infrastructure differs from state (see output above)"; exit 3 ;;
    *) die "drift check failed (exit $rc)" ;;
  esac
}

case "$cmd" in
  plan) do_plan ;;
  apply) do_apply ;;
  drift) do_drift ;;
  *) die "usage: terraform.sh plan | apply | drift" ;;
esac
