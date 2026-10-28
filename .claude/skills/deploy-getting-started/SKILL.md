---
name: deploy-getting-started
description: Front door for developers who want to deploy an app but are new to DevOps - asks a few questions about the app, team and budget, recommends a rung of the deployment ladder (single VPS with Docker Compose -> CD pipeline -> AWS ECS with load balancing, autoscaling and alarms -> Kubernetes), and walks through it step by step using the other skills. Use when the user asks how or where to deploy, wants to go to production for the first time, asks "what do I need" for hosting, CI/CD, monitoring or scaling, or does not say which target they want.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git log:*), Bash(ls:*)
---

# Skill: deploy-getting-started

Your job is to get a developer from "it works on my laptop" to a **safe, observable, repeatable** deployment as fast as
their situation allows, without making them learn everything at once. Speak plainly, explain each new concept in one
sentence the first time it appears, and always say what something costs (money and effort).

## 1. Look before asking

Inspect the repository (read-only) so you only ask what you cannot see:

| Check | How | Tells you |
|-------|-----|-----------|
| Language / framework | `package.json`, `requirements.txt`/`pyproject.toml`, `go.mod`, `pom.xml`, `Gemfile` | which Dockerfile template |
| Already containerized? | `Dockerfile`, `compose.yaml`/`docker-compose.yml` | skip rung 0 |
| Health endpoint? | grep for `healthz`, `/health`, `/ready` | needed by every target |
| Existing CI | `.github/workflows/` | extend, do not duplicate |
| Existing infra | `infra/`, `*.tf`, `charts/`, `k8s/` | they may already have chosen |
| Toolkit installed? | `deploy/scripts/`, `deploy/targets.*.env` | what is configured |
| Database / state | ORM config, migrations folder, `DATABASE_URL` | the hardest part of any deploy |

## 2. Ask at most these questions (skip what you already know)

1. **Who uses it and how much?** (side project / internal tool / paying customers; rough requests per minute)
2. **What does downtime cost?** (a few minutes during a deploy is fine / must stay up)
3. **Budget per month?** (about 5-20 USD / 50-150 USD / more)
4. **Where is your data?** (none, managed database, a database you want to run yourself)
5. **Which cloud accounts do you already have?** (none, a VPS provider, AWS, ...)

## 3. Recommend one rung of the ladder

Recommend the **lowest rung that meets their needs**; they can climb later without rewriting the app.

| Rung | What you get | Typical cost | Good for | Skills, in order |
|------|--------------|--------------|----------|------------------|
| **0. Containerize** | the app runs the same everywhere | free | everyone, first | `containerize-app` |
| **1. Single VPS** | one server, Docker Compose, automatic HTTPS (Caddy), hardened SSH/firewall, one-command rollback | 5-20 USD | side projects, MVPs, internal tools, early startups | `setup-vps` -> `deploy-compose-vps` -> `post-deploy-verify` |
| **2. CD pipeline** | every push to `main` is tested, built, scanned and deployed to staging; production after a click-approval in GitHub | free (GitHub Actions minutes) | anyone deploying more than once a week | `setup-cd-pipeline` |
| **3. Monitoring and alerts** | dashboards, uptime probes, alerts to Slack/email with runbooks | free on the VPS / a few USD on AWS | before real users arrive | `setup-observability` |
| **4. AWS, Infrastructure as Code** | load balancer across 2+ zones, autoscaling containers (ECS Fargate), zero-downtime rolling deploys with automatic rollback, CloudWatch alarms and dashboard, all in Terraform | 50-150 USD+ | paying customers, uptime promises, traffic spikes | `provision-aws-ecs` -> `setup-cd-pipeline` (aws-ecs) -> `setup-observability` (AWS part) |
| **5. Kubernetes** | many services, platform team, GitOps | 150 USD+ and real expertise | several teams / many services | `deploy-helm-k8s`, `deploy-gitops-argocd` |

Rules of thumb you should say out loud when relevant:
- A single VPS has **brief downtime on each deploy** (seconds) and is a **single point of failure**. That is fine for most early products. Move to rung 4 when that stops being acceptable.
- **Do not run your own database** on the app server for anything with paying users; use a managed database (RDS, Neon, Supabase, DigitalOcean Managed DB) and backups you have tested.
- Kubernetes is not a goal. Most apps never need it.

## 4. Prerequisites every rung needs (check them, help fix them)

- [ ] `GET /healthz` (or similar) returns 200 only when the app can serve traffic (checks its database connection).
- [ ] The app reads **all** config and secrets from environment variables; nothing secret in git.
- [ ] The app listens on `$PORT` and logs to stdout/stderr.
- [ ] Database migrations are **backward compatible** (add columns first, remove later) so a rollback is safe.
- [ ] The toolkit is installed (`install.sh`) and `deploy/targets.<env>.env` exists for each environment.

## 5. Produce a written path

End with a short checklist the user can follow, for example:

```text
Your path: rung 1 -> 2 -> 3 (about 2 hours the first time)
[ ] 0. Dockerfile from deploy/templates/docker/node   (skill containerize-app)
[ ] 1. Rent an Ubuntu 24.04 VPS (2 GB RAM), point app.example.com at it, bootstrap it  (skill setup-vps)
[ ] 2. First deploy to staging by hand, verify                                (deploy-compose-vps, post-deploy-verify)
[ ] 3. GitHub Actions: staging on every push, production with approval       (setup-cd-pipeline, vps)
[ ] 4. Monitoring + Slack alerts, send a test alert                           (setup-observability)
Later, when you need zero-downtime and autoscaling: provision-aws-ecs
```

Then start with step 1 using its skill. Do every change through the toolkit's dry-run-first flow: show the dry run,
get approval for the exact plan, then apply. Never ask the user to paste secrets into the chat.

## Roadmap references

[DevOps Roadmap](https://github.com/mascot200/devops-roadmap) ·
[Docker](https://github.com/mascot200/devops-roadmap/blob/main/level-04-docker/README.md) ·
[CI/CD](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/README.md) ·
[Observability](https://github.com/mascot200/devops-roadmap/blob/main/level-10-observability/README.md)
