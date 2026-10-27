---
name: deploy-compose-vps
description: Deploy, verify and roll back a Docker Compose application on a single Linux VPS over SSH (Nginx or Caddy in front, health check, recorded previous version). Use when the user wants to deploy to a VPS, server or droplet that runs docker compose, or asks to roll back such a deployment.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*)
---

# Skill: deploy-compose-vps

Deploys `IMAGE:TAG` to a VPS that runs your app with Docker Compose. The server keeps
`.deploy/current_tag` and `.deploy/previous_tag`, so **rollback is one command**.

## When to use

The target is "a server I can SSH into that runs `docker compose`" (Projects 2 and 3).
For Kubernetes use `deploy-helm-k8s`; for infrastructure use `deploy-terraform-aws`.

## Prerequisites (check, do not assume)

- `deploy-preflight` passed for `TARGET=compose`.
- `deploy/targets.<env>.env` defines `VPS_HOST VPS_USER VPS_APP_DIR IMAGE HEALTH_URL`.
- SSH key auth works for the deploy user (agent-loaded key; **no passwords or keys in files**).
- The server's `compose.yaml` references the image as `${IMAGE}:${IMAGE_TAG}` and secrets live in
  the server-side `.env`, never in the image or repo.
- The image tag exists in the registry (built and scanned by CI).
- If the release includes a **database migration**, it must be backward compatible (expand/contract)
  so the previous version still works against the new schema. See
  [CI/CD: database migrations](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/09-database-migrations.md). If it is not, stop and tell the user rollback will not be safe.

## Procedure

### 1. Show current state (read-only)
```bash
ENVIRONMENT=staging bash deploy/scripts/compose-deploy.sh status
```
Note the current tag; this is the rollback target.

### 2. Dry-run the deployment (read-only, prints the exact remote script)
```bash
ENVIRONMENT=staging bash deploy/scripts/compose-deploy.sh deploy 3f9c1ab
```
Show the user the `DRYRUN` lines. Explain in one sentence what will change:
`current -> new tag, compose pull, up -d, then health check on <HEALTH_URL>`.

### 3. Approval gate
Ask the user to approve **this exact plan** (environment + tag). For **production** the user must name the
environment and tag in their approval. Do not proceed on a vague "ok" given earlier for a different plan.

### 4. Apply
```bash
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/compose-deploy.sh deploy 3f9c1ab
# production only, and only after explicit approval:
ENVIRONMENT=production APPLY=1 CONFIRM_PROD=yes-deploy-prod bash deploy/scripts/compose-deploy.sh deploy 3f9c1ab
```
The script waits for `HEALTH_URL` to return 200. If the health check fails it stops with a rollback
hint (or rolls back by itself when `AUTO_ROLLBACK=1` is set in the targets file).

### 5. Verify
Run the `post-deploy-verify` skill. Do not call the deployment done until it reports `PASS`.

### 6. Roll back (when verification fails)
```bash
ENVIRONMENT=staging bash deploy/scripts/compose-deploy.sh rollback          # dry-run first
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/compose-deploy.sh rollback  # after approval
```

## Failure guide

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| `Permission denied (publickey)` | key not loaded / wrong user | `ssh-add -l`, `ssh -v` |
| `pull access denied` | server not logged in to the registry | `docker login` on the server |
| Health check never returns 200 | app crashing or wrong port | `docker compose logs --tail=100 app` on the server |
| 502 from Nginx after deploy | container up but not ready | probe path, start time, `depends_on` health |
| Rollback says "no previous tag" | first deployment ever | redeploy a known-good tag explicitly |

## Roadmap references

[Linux: SSH](https://github.com/mascot200/devops-roadmap/blob/main/level-01-linux-fundamentals/12-ssh-keys-and-authorized-keys.md) ·
[Docker Compose](https://github.com/mascot200/devops-roadmap/blob/main/level-04-docker/08-docker-compose.md) ·
[Rollback](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/07-rollback.md) ·
[Zero-downtime deployments](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/08-zero-downtime-deployments.md) ·
[Project 3 - CI/CD](https://github.com/mascot200/devops-roadmap/blob/main/projects/project-03-cicd.md)
