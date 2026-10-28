#!/usr/bin/env bash
# install.sh - install the deployment agents, skills and scripts into an application repository.
#
# Usage: ./install.sh [--dry-run] [--force] [TARGET_REPO_DIR]
#   TARGET_REPO_DIR  the git repository of the application you deploy (default: current directory)
#   --dry-run        show what would be copied, change nothing
#   --force          overwrite files that already exist and differ (default: skip them and say so)
#
# Installs:  .claude/agents/*  .claude/skills/*  deploy/  (+ a marked rules block in CLAUDE.md
#            and git-ignore entries for local target files and Terraform plans)
# Idempotent: running it twice changes nothing the second time.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dry=0
force=0
target=""

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { echo "install.sh: $*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    --force) force=1 ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown option: $arg" ;;
    *) [ -z "$target" ] || die "only one target directory allowed"; target="$arg" ;;
  esac
done
target="$(cd "${target:-$PWD}" 2>/dev/null && pwd)" || die "target directory does not exist"
[ "$target" != "$SRC" ] || die "run this against your APPLICATION repository, not the toolkit itself"
[ -d "$target/.git" ] || die "$target is not the root of a git repository"

copied=0 same=0 skipped=0
say() { printf '  %-10s %s\n' "$1" "$2"; }

install_file() { # install_file <relative path>
  local rel="$1" from="$SRC/$1" to="$target/$1"
  if [ ! -e "$to" ]; then
    say "add" "$rel"
    if [ "$dry" = 0 ]; then mkdir -p "$(dirname "$to")"; cp -p "$from" "$to"; fi
    copied=$((copied + 1))
  elif cmp -s "$from" "$to"; then
    same=$((same + 1))
  elif [ "$force" = 1 ]; then
    say "overwrite" "$rel"
    if [ "$dry" = 0 ]; then cp -p "$from" "$to"; fi
    copied=$((copied + 1))
  else
    say "SKIP" "$rel (exists and differs; use --force to overwrite)"
    skipped=$((skipped + 1))
  fi
}

echo "Installing deployment toolkit into: $target"
[ "$dry" = 0 ] || echo "(dry run - nothing will be changed)"

while IFS= read -r f; do install_file "$f"; done < <(
  cd "$SRC" && find .claude/agents .claude/skills deploy -type f ! -name '*.pyc' | LC_ALL=C sort
)

# --- git-ignore entries -------------------------------------------------------------------
gi_marker="# deploy-toolkit: local files"
if ! grep -qF "$gi_marker" "$target/.gitignore" 2>/dev/null; then
  say "append" ".gitignore (target files, Terraform plans and local state)"
  if [ "$dry" = 0 ]; then
    {
      [ ! -s "$target/.gitignore" ] || echo
      echo "$gi_marker"
      echo "deploy/targets.*.env"
      echo "!deploy/targets.example.env"
      echo "**/tfplan"
      echo "**/tfplan.*"
      echo "**/.terraform/"
      echo "*.tfstate"
      echo "*.tfstate.*"
    } >>"$target/.gitignore"
  fi
fi

# --- CLAUDE.md rules block (delimited so it can be updated) -----------------------------------
start="<!-- deploy-toolkit:start -->"
end="<!-- deploy-toolkit:end -->"
block="$SRC/templates/CLAUDE.deploy.md"
if grep -qF "$start" "$target/CLAUDE.md" 2>/dev/null; then
  if [ "$force" = 1 ]; then
    say "update" "CLAUDE.md deployment rules block"
    if [ "$dry" = 0 ]; then
      awk -v s="$start" -v e="$end" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$target/CLAUDE.md" >"$target/CLAUDE.md.tmp"
      { cat "$target/CLAUDE.md.tmp"; echo; echo "$start"; cat "$block"; echo "$end"; } >"$target/CLAUDE.md"
      rm -f "$target/CLAUDE.md.tmp"
    fi
  fi
else
  say "append" "CLAUDE.md deployment rules block"
  if [ "$dry" = 0 ]; then
    { [ ! -s "$target/CLAUDE.md" ] || echo; echo "$start"; cat "$block"; echo "$end"; } >>"$target/CLAUDE.md"
  fi
fi

echo
echo "Done: $copied added/updated, $same unchanged, $skipped skipped."
cat <<EOF

Next steps
  1. cp deploy/targets.example.env deploy/targets.staging.env   # then edit; it is git-ignored
  2. Open Claude Code in $target and ask:  "Plan a staging deployment of <tag> with the deploy-planner agent."
  3. Read docs: https://github.com/mascot200/devops-deploy-toolkit/blob/main/docs/GUIDE.md
EOF
