---
name: deploy-gitops-argocd
description: Promote an application version through a GitOps repository watched by Argo CD (bump the image tag on a branch, open a pull request, sync, check health, and roll back with git revert). Use when the cluster is managed by Argo CD or Flux, or the user wants to promote dev to staging to production by Git commit.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*)
---

# Skill: deploy-gitops-argocd

In GitOps the **Git repository is the deployment interface**. You do not run `kubectl apply` or `helm upgrade`; you change
desired state in Git, a human merges it, and Argo CD reconciles the cluster. The commit history becomes the audit trail
and `git revert` becomes the rollback.

```
Developer -> CI builds image:TAG -> this skill bumps TAG in the GitOps repo (branch) -> PR merged -> Argo CD syncs -> cluster
```

## When to use

The target namespace is managed by Argo CD (Project 6, Level 17). If there is no Argo CD/Flux, use `deploy-helm-k8s`.

## Prerequisites

- `deploy-preflight` passed with `TARGET=gitops` (requires `git`; `argocd` CLI for diff/sync/status; `kustomize` optional).
- `deploy/targets.<env>.env` defines `IMAGE GITOPS_REPO_DIR GITOPS_OVERLAY_PATH ARGOCD_APP APP_NAME`
  (optional `GITOPS_BASE_BRANCH`, default `main`).
- `GITOPS_REPO_DIR` is a clean clone of the GitOps repo. The overlay is a kustomize directory whose
  `kustomization.yaml` lists the image under `images:` with a `newTag`.
- `argocd login <server>` has been done by the user (SSO). Credentials are never pasted into chat or files.
- The image tag exists and was promoted through the lower environment first (dev -> staging -> production).

## Procedure

### 1. Current state (read-only)
```bash
ENVIRONMENT=staging bash deploy/scripts/gitops-promote.sh status
ENVIRONMENT=staging bash deploy/scripts/gitops-promote.sh diff
```
Expect `Synced` and `Healthy` before you start. If the app is already `OutOfSync` or `Degraded`, stop and report it:
promoting on top of an unhealthy base hides the real cause.

### 2. Dry-run the promotion
```bash
ENVIRONMENT=staging bash deploy/scripts/gitops-promote.sh bump 3f9c1ab
```
Shows the branch name, the kustomize edit and the commit that would be created.

### 3. Approval gate
Ask the user to approve environment + tag. For production the approval must name both.

### 4. Create the promotion branch
```bash
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/gitops-promote.sh bump 3f9c1ab
ENVIRONMENT=production APPLY=1 CONFIRM_PROD=yes-deploy-prod bash deploy/scripts/gitops-promote.sh bump 3f9c1ab
```
This pushes `promote/<app>-<env>-<tag>`. **It does not deploy.** Tell the user to open the pull request and merge it
(the merge is the deployment). Do not merge production promotions yourself.

### 5. Sync and wait (only if auto-sync is disabled)
```bash
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/gitops-promote.sh sync
```
With auto-sync on, Argo CD picks up the merge within its polling interval or webhook; just watch `status`.

### 6. Verify
Run `post-deploy-verify`. Confirm `argocd app get` shows the new revision, `Synced` and `Healthy`.

### 7. Roll back = revert in Git
Find the promotion commit that was merged into the GitOps repo (the merge commit or the commit itself), then:
```bash
ENVIRONMENT=staging bash deploy/scripts/gitops-promote.sh rollback <sha>          # dry-run
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/gitops-promote.sh rollback <sha>  # after approval
```
This creates `rollback/<app>-<env>-<sha8>` with `git revert`; the user merges it and Argo CD restores the previous version.
The script refuses commits that were never merged and handles merge commits (`git revert -m 1`).

## Rules

- **Never** `kubectl edit/apply/patch` resources that Argo CD manages; it will revert you and the history will lie.
- Never push directly to the base branch of the GitOps repo.
- Never disable self-heal or pruning to "make it work"; find out why the diff exists.
- If a manual emergency change was made, record it and put it back into Git afterwards.

## Failure guide

| Symptom | Likely cause |
|---------|--------------|
| `OutOfSync` right after merge | auto-sync off or webhook missing: run `sync` or wait for the poll |
| `Degraded` | new Pods failing probes: `argocd app get`, `kubectl describe pod` |
| `ComparisonError` | invalid manifest or Kustomize/Helm render error in the repo |
| Sync loops forever | a controller mutates a field Argo manages: add an `ignoreDifferences` rule |
| `kustomize edit` changed nothing | image name in `images:` does not match `IMAGE` exactly |

## Roadmap references

[GitOps level](https://github.com/mascot200/devops-roadmap/blob/main/level-17-gitops/README.md) ·
[Rollback through Git](https://github.com/mascot200/devops-roadmap/blob/main/level-17-gitops/06-rollback-through-git.md) ·
[Environment promotion](https://github.com/mascot200/devops-roadmap/blob/main/level-17-gitops/04-environment-promotion.md) ·
[CI to GitOps flow](https://github.com/mascot200/devops-roadmap/blob/main/level-17-gitops/07-ci-to-gitops-flow.md) ·
[Project 6 - Production Kubernetes](https://github.com/mascot200/devops-roadmap/blob/main/projects/project-06-production-kubernetes.md)
