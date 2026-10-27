---
name: deploy-preflight
description: Run the mandatory pre-deployment checks (clean git tree, deployable branch, immutable image tag, secret scan, tests, required tools) before deploying any application to a VPS, AWS/Terraform, Kubernetes/Helm or GitOps/Argo CD target. Use at the start of every deployment, before planning or applying anything.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*)
---

# Skill: deploy-preflight

Every deployment starts here. The goal is to **fail early and cheaply**: a dirty working tree, a floating
`latest` tag or a leaked key is much cheaper to catch now than after traffic is hitting the new version.

## When to use

- The user asks to deploy, release, ship, promote or roll out anything.
- Before running `deploy-compose-vps`, `deploy-terraform-aws`, `deploy-helm-k8s` or `deploy-gitops-argocd`.

## Inputs you need (ask the user if missing)

| Input | Example | Notes |
|-------|---------|-------|
| Target | `compose`, `terraform`, `helm`, `gitops` | picks which tools are checked |
| Environment | `staging` or `production` | defaults to `staging`; production is stricter |
| Version | `3f9c1ab` or `v1.4.2` | immutable tag; not required for `terraform` |

## Procedure

1. **Confirm the targets file exists** for the environment: `deploy/targets.<environment>.env`
   (copy `deploy/targets.example.env` if not). Never print its secrets; it should contain none.
2. **Run the checks** (read-only):
   ```bash
   TARGET=helm ENVIRONMENT=staging PREFLIGHT_TEST_CMD="npm test" \
     bash deploy/scripts/preflight.sh 3f9c1ab
   ```
3. **Read every line of output.** `FAIL` blocks the deployment; `WARN` must be mentioned to the user.
4. **Summarise what will be deployed** so the user can sanity-check it:
   ```bash
   git log --oneline -n 10
   git diff --stat origin/main...HEAD
   ```
5. **Report** using this exact shape:
   ```
   PREFLIGHT: PASS | BLOCKED
   Target / environment / version: ...
   Failed checks: ... (or none)
   Warnings: ...
   Changes included: <n commits, notable files>
   ```

## Rules

- Do **not** work around a failing check (for example by setting `ALLOW_BRANCH=1`) unless the user explicitly tells you to.
- Do not continue to a deploy skill while preflight is `BLOCKED`.
- A production preflight additionally needs evidence that the **same tag** already passed staging verification.

## Why these checks

| Check | Failure it prevents | Roadmap reference |
|-------|---------------------|-------------------|
| Clean tree + approved branch | deploying code nobody reviewed | [Git: protected branches](https://github.com/mascot200/devops-roadmap/blob/main/level-03-git-and-github/08-protected-branches-and-pull-requests.md) |
| Immutable tag | rollbacks that "roll back" to a different build | [CI/CD: artifacts](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/06-artifacts.md) |
| Secret scan | credentials in the repo or image | [Security: secrets scanning](https://github.com/mascot200/devops-roadmap/blob/main/level-11-security-devsecops/11-secrets-scanning.md) |
| Tool check | failing halfway through a rollout | [CI/CD: pipeline design](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/01-pipeline-design.md) |
