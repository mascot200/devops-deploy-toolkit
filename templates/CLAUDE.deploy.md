## Deployment safety rules (devops-deploy-toolkit)

1. **Plan first, apply only with approval.** Every script in `deploy/scripts/` is a dry run unless `APPLY=1` is set.
   Never set `APPLY=1` until the user has approved the specific plan (environment + version) in this conversation.
2. **Production needs two things:** the user's explicit approval naming the environment and version, and
   `CONFIRM_PROD=yes-deploy-prod` on the command. Never set that variable on your own.
3. **Never deploy floating tags** (`latest`, `main`). Deploy a commit SHA or semver tag.
4. **Never put credentials in files, commands or chat.** Credentials come from the user's SSH agent, `aws sso login`/OIDC and kubectl contexts.
   `deploy/targets.*.env` is git-ignored and must contain no secrets.
5. **Terraform:** apply only a saved, reviewed plan. Do not run `destroy` or `state` commands as part of a deployment.
6. **GitOps-managed clusters:** change Git, not the cluster. No `kubectl apply/edit/patch` on resources owned by Argo CD or Flux.
7. After every deployment run verification (`post-deploy-verify` skill / `release-verifier` agent). A zero exit code is not proof of health.
8. If something fails, stop and report. Do not retry blindly or improvise a different fix.
9. **Templates are starting points:** copy from `deploy/templates/` into the repo, edit, and commit before using them.
   Alerts link to runbooks in the toolkit's `docs/RUNBOOKS.md`.

| Goal | Skill | Agent |
|------|-------|-------|
| Not sure where/how to deploy; first deployment | `deploy-getting-started` | - |
| Write a Dockerfile | `containerize-app` | - |
| Prepare a new VPS (hardening, Docker, HTTPS) | `setup-vps` | - |
| Deploy on every push (GitHub Actions) | `setup-cd-pipeline` | - |
| AWS with load balancer, autoscaling, alarms | `provision-aws-ecs` | `deployer` |
| Monitoring, dashboards, alerts | `setup-observability` | - |
| Decide what and how to deploy | `deploy-preflight` | `deploy-planner` |
| Review manifests/infra before shipping | - | `deploy-security-reviewer` |
| Deploy to a VPS with Docker Compose | `deploy-compose-vps` | `deployer` |
| Provision/change AWS with Terraform | `deploy-terraform-aws` | `deployer` |
| Deploy to Kubernetes with Helm | `deploy-helm-k8s` | `deployer` |
| Promote through Argo CD / GitOps | `deploy-gitops-argocd` | `deployer` |
| Confirm a release is healthy | `post-deploy-verify` | `release-verifier` |
| Recover from a bad release | (rollback section of each skill) | `rollback-responder` |
| Find manual changes | - | `drift-auditor` |
