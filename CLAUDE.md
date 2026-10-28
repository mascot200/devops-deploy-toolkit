# CLAUDE.md

This repository is the **devops-deploy-toolkit**: Claude Code agents, skills and safe deployment scripts that are
*installed into an application repository* with `./install.sh`. It is the hands-on companion to the
[DevOps Roadmap curriculum](https://github.com/mascot200/devops-roadmap).

## Layout

- `.claude/agents/*.md` - subagent definitions (planner, security reviewer, deployer, release verifier, rollback responder, drift auditor)
- `.claude/skills/*/SKILL.md` - procedures per target (preflight, Compose/VPS, Terraform/AWS, Helm/K8s, GitOps/Argo CD, post-deploy verify)
- `.claude/skills/*/SKILL.md` also covers the beginner path: getting started, containerize, VPS setup, CD pipeline, AWS ECS, observability
- `deploy/` - the scripts the skills call; dry-run by default
- `deploy/templates/` - starting points copied into app repos: Dockerfiles, VPS compose + Caddy, monitoring stack, GitHub Actions, Terraform (AWS ECS)
- `templates/CLAUDE.deploy.md` - the rules block `install.sh` adds to an app repo's CLAUDE.md
- `tests/` - `bash tests/run-tests.sh` runs everything (stub-based, no cloud access needed)
- `docs/GUIDE.md` - the full user guide; `docs/RUNBOOKS.md` - one section per alert (alert rules link to its anchors)

## Working on this repo

- Safety is the product. Any change must keep: dry-run by default, `APPLY=1` for every mutation, the production guard
  (`CONFIRM_PROD`), rejection of floating tags, and read-only tool lists for the read-only agents. Templates follow the
  same rules: pinned image versions, production jobs behind a GitHub environment, no `ALLOW_DESTROY` in CI, no secrets.
- Run `bash tests/run-tests.sh` and `shellcheck -x -S warning deploy/lib/common.sh deploy/scripts/*.sh install.sh tests/*.sh` before committing.
- When a script's behaviour changes, update the matching `SKILL.md`, `docs/GUIDE.md` and add or adjust a test.
- Terraform templates must pass `terraform fmt -check` and `validate` (CI job `templates`); a new alert needs a `docs/RUNBOOKS.md` section.
- Keep skill and agent descriptions specific: they decide when Claude picks them.
