# devops-deploy-toolkit

**Claude Code agents, skills and safe deployment scripts** for shipping an application to a VPS, AWS, Kubernetes or a GitOps
cluster - with a hard rule built into the code: **look first, change only when a human has approved the plan.**

It is the hands-on companion to the [DevOps Roadmap: Beginner to Senior](https://github.com/mascot200/devops-roadmap) curriculum,
and every skill links back to the lesson that explains the "why".

**New to DevOps?** Install it, open Claude Code in your app repo and say *"help me deploy this app"*. The
`deploy-getting-started` skill looks at your code, asks a few questions and walks you up the ladder below, one rung at a time.

## The deployment ladder

Start at the lowest rung that fits; climb when you need to. Each rung reuses the one before it.

| Rung | You get | Cost / month | Skills |
|------|---------|--------------|--------|
| 0. Containerize | a small, non-root image that runs the same everywhere | free | `containerize-app` |
| 1. Single VPS | hardened server, Docker Compose, **automatic HTTPS** (Caddy), one-command rollback | 5-20 USD | `setup-vps`, `deploy-compose-vps` |
| 2. CD pipeline | push to `main` -> tests -> image tagged with the commit SHA -> scan -> staging -> **click-approved** production; one-click rollback | free | `setup-cd-pipeline` |
| 3. Monitoring | Prometheus, Grafana, Alertmanager: uptime, latency, TLS, disk, memory, crash-loop alerts to Slack/email, each with a [runbook](docs/RUNBOOKS.md) | free on the VPS | `setup-observability` |
| 4. AWS, Infrastructure as Code | Terraform: **load balancer** across zones, **autoscaling** ECS Fargate, zero-downtime deploys with automatic rollback, **CloudWatch alarms** + dashboard, OIDC (no AWS keys), daily drift check | 30-150 USD | `provision-aws-ecs`, `deploy-terraform-aws`, `setup-cd-pipeline` |
| 5. Kubernetes | Helm and GitOps with Argo CD | 150 USD+ | `deploy-helm-k8s`, `deploy-gitops-argocd` |

```mermaid
flowchart LR
    U["You: deploy shop-api v1.4.2 to staging"] --> P["deploy-planner<br/>read-only"]
    P --> S["deploy-security-reviewer<br/>read-only"]
    S --> A{"You approve<br/>the exact plan?"}
    A -->|no| X["Stop. Nothing changed."]
    A -->|yes| D["deployer<br/>APPLY=1, once"]
    D --> V["release-verifier<br/>read-only evidence"]
    V -->|PASS| OK["Done"]
    V -->|ROLLBACK RECOMMENDED| R["rollback-responder<br/>asks approval again"]
```

## What is inside

| Kind | Name | Purpose |
|------|------|---------|
| Skill | `deploy-getting-started` | the front door: inspects the repo, asks a few questions, picks a rung of the ladder |
| Skill | `containerize-app` | Dockerfile + `.dockerignore` from templates (Node, Python, Go), `/healthz`, local test |
| Skill | `setup-vps` | fresh Ubuntu/Debian server -> deploy user, SSH keys only, firewall, fail2ban, updates, Docker, Caddy HTTPS |
| Skill | `setup-cd-pipeline` | GitHub Actions: staging on every push, production after reviewer approval, rollback button, drift check |
| Skill | `provision-aws-ecs` | Terraform: VPC, ALB, ECS Fargate autoscaling, alarms, dashboard, state bucket, ECR, GitHub OIDC roles |
| Skill | `setup-observability` | VPS monitoring stack or AWS CloudWatch alarms, alert delivery, test alert, runbooks |
| Skill | `deploy-preflight` | clean tree, deployable branch, immutable tag, secret scan, tests, tools |
| Skill | `deploy-compose-vps` | Docker Compose on a VPS over SSH, health check, one-command rollback |
| Skill | `deploy-terraform-aws` | `plan` -> review -> apply the **saved** plan; drift check |
| Skill | `deploy-helm-k8s` | lint, diff, `upgrade --atomic --wait`, rollout status, `helm rollback` |
| Skill | `deploy-gitops-argocd` | promote by pull request, sync, rollback by `git revert` |
| Skill | `post-deploy-verify` | smoke test + error rate/latency/restarts with explicit PASS thresholds |
| Agent | `deploy-planner` | turns "deploy X" into a written plan with risks, verification and rollback (read-only) |
| Agent | `deploy-security-reviewer` | reviews Dockerfiles, manifests, Terraform, CI before shipping (read-only) |
| Agent | `deployer` | executes an **approved** plan; refuses without the approval handshake |
| Agent | `release-verifier` | evidence-based verdict after a release (read-only) |
| Agent | `rollback-responder` | restores the last good version with approval, drafts the incident timeline |
| Agent | `drift-auditor` | finds manual changes vs Git (Terraform, Helm, Argo CD); never fixes (read-only) |
| Scripts | `deploy/scripts/*.sh` | the commands the skills call; dry-run by default (`vps-setup.sh` prepares servers and monitoring) |
| Templates | `deploy/templates/` | Dockerfiles, VPS compose + Caddy, monitoring stack, GitHub Actions pipelines, Terraform for AWS |
| Docs | [`docs/RUNBOOKS.md`](docs/RUNBOOKS.md) | what to do when each alert fires |

## Install into your application repo

```bash
git clone https://github.com/mascot200/devops-deploy-toolkit.git
cd your-app-repo
../devops-deploy-toolkit/install.sh          # or: ../devops-deploy-toolkit/install.sh --dry-run
cp deploy/targets.example.env deploy/targets.staging.env   # edit; git-ignored
```

The installer copies `.claude/agents`, `.claude/skills` and `deploy/`, appends a marked rules block to your `CLAUDE.md` and
git-ignore entries, never overwrites a file you changed (use `--force` to), and is safe to run repeatedly.
Then open Claude Code in your app repo and try:

```text
Use the deploy-planner agent to plan a staging deployment of shop-api tag 3f9c1ab with Helm.
```

## The safety model

| Layer | Behaviour |
|-------|-----------|
| Dry-run by default | scripts change nothing unless `APPLY=1`; dry runs print exactly what would run |
| Human approval | the `deployer` needs an `APPROVED_PLAN` block plus the user's quoted approval; production approval must name the environment and version |
| Production guard | `APPLY=1` in production also needs `CONFIRM_PROD=yes-deploy-prod` |
| No floating tags | `latest`/`main`/`master`/`stable`/`dev` are rejected |
| Terraform | applies only the reviewed plan file; refuses stale plans, plans from another commit and plans that delete/replace (unless `ALLOW_DESTROY=1`; a new ECS task definition revision is the one routine exception, listed separately) |
| CD pipelines | production waits for a reviewer in a GitHub environment; CI never sets `ALLOW_DESTROY`; AWS access via OIDC with 1-hour credentials |
| Servers | SSH keys only (never locks you out), firewall, fail2ban, unattended upgrades, capped container logs, monitoring UIs on `127.0.0.1` |
| Helm | `--atomic --wait`; explicit `--kube-context` on every call |
| GitOps | a pull request merge is the deployment; rollback refuses promotions that were never merged |
| Read-only agents | the planner, security reviewer, verifier and drift auditor have no `Edit`/`Write` tools |
| No secrets in files | credentials come from your SSH agent, `aws sso login`/OIDC and kubectl contexts |

## Honest limits

- The scripts and definitions are tested with **stub binaries and real local git** (`bash tests/run-tests.sh`, 150+ checks, also run in CI).
  CI also runs `terraform validate`, `actionlint`, `promtool` and `amtool` on the templates.
  They have **not** been run against a real AWS account, cluster or VPS by the authors. Treat your first run as a staging rehearsal and read every dry run.
- Pinned versions in the templates (Prometheus, Grafana, Caddy, Terraform provider, ...) are known-good, not the newest. Bump them deliberately.
- Claude Code permission prompts remain your outer safety net. See [docs/GUIDE.md](docs/GUIDE.md#6-permissions-and-the-outer-safety-net).
- Licensed under the [MIT License](LICENSE). The software is provided "as is": you are responsible for what you deploy with it.

## Documentation

[docs/GUIDE.md](docs/GUIDE.md) - the ladder, setup, a workflow for each target with example prompts (from a bare VPS to an
autoscaling AWS service), CD pipelines, monitoring, the approval handshake, drift audits, extending the toolkit and troubleshooting.
[docs/RUNBOOKS.md](docs/RUNBOOKS.md) - one section per alert: meaning, first checks, fixes.

Created by Ubong Eduok ([@mascot200](https://github.com/mascot200)) as part of the
[DevOps Roadmap](https://github.com/mascot200/devops-roadmap) course.
