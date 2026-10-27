# deploy/ - safe deployment scripts

Small, readable Bash scripts that the deployment [skills and agents](../docs/GUIDE.md) call. You can also run
them by hand or from CI. They are the part that actually touches servers, clusters and cloud accounts, so they are built
around one idea: **look first, change only when told to.**

```
deploy/
├── targets.example.env      # copy to targets.<env>.env (git-ignored) and edit
├── lib/common.sh            # dry-run/apply helpers, production guard, tag checks
└── scripts/
    ├── preflight.sh         # pre-deployment checks (read-only)
    ├── smoke.sh             # HTTP smoke test with retries (read-only)
    ├── compose-deploy.sh    # Docker Compose on a VPS over SSH
    ├── terraform.sh         # AWS via Terraform: plan | apply | drift
    ├── helm-deploy.sh       # Kubernetes via Helm: diff | deploy | rollback | status
    └── gitops-promote.sh    # Argo CD / GitOps: bump | diff | status | sync | rollback
```

## The safety model

| Layer | What it does |
|-------|--------------|
| **Dry-run by default** | Nothing changes unless `APPLY=1` is set. A dry run prints exactly what would run (for SSH it prints the whole remote script). |
| **Production guard** | With `APPLY=1`, `ENVIRONMENT=production` also needs `CONFIRM_PROD=yes-deploy-prod`. |
| **No floating tags** | `latest`, `main`, `master`, `stable` and `dev` are rejected. Deploy a commit SHA or semver. |
| **Saved-plan Terraform** | `apply` uses only the plan file you reviewed; refuses a plan older than an hour, from another commit, or with deletions (unless `ALLOW_DESTROY=1`). |
| **Atomic Helm** | `--atomic --wait`: a release whose Pods never become Ready is rolled back automatically. |
| **GitOps = pull request** | `bump` pushes a branch; a human merging the pull request is the deployment. |
| **Explicit contexts** | Helm and kubectl always get `--kube-context`, so the wrong cluster is not an accident waiting to happen. |
| **No secrets in files** | Credentials come from your SSH agent, `aws sso login`/OIDC and kubectl contexts. The targets files contain hostnames and names only. |

## Quick start

```bash
cp deploy/targets.example.env deploy/targets.staging.env   # edit the values

# 1. checks
TARGET=helm ENVIRONMENT=staging PREFLIGHT_TEST_CMD="npm test" bash deploy/scripts/preflight.sh 3f9c1ab

# 2. look (dry run / diff / plan)
ENVIRONMENT=staging bash deploy/scripts/helm-deploy.sh diff 3f9c1ab

# 3. change, after a human has approved the plan
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/helm-deploy.sh deploy 3f9c1ab

# 4. prove it works
bash deploy/scripts/smoke.sh https://staging.example.com/healthz 200 30 2
```

## Requirements

| Script | Needs |
|--------|-------|
| all | `bash` 4+, `git`, `curl` |
| `compose-deploy.sh` | `ssh` key access to the server; Docker + Compose plugin on the server |
| `terraform.sh` | `terraform` (or OpenTofu aliased as `terraform`), `jq`, AWS credentials |
| `helm-deploy.sh` | `helm`, `kubectl`; optional `helm-diff` plugin |
| `gitops-promote.sh` | `git`; `argocd` CLI for diff/sync/status; `kustomize` optional (falls back to `sed`) |

## Testing the scripts without real infrastructure

The scripts can be exercised with stub binaries on `PATH` (a fake `ssh`, `terraform`, `helm`, `kubectl`, `argocd` that record
their arguments). That is how their control flow was tested: dry-run vs apply, production refusal, floating-tag rejection,
stale or mismatched Terraform plans, `--atomic` Helm upgrades, and real `git` branch/commit/push/revert against a local bare
repository. `smoke.sh` and `preflight.sh` run against a local `python3 -m http.server` and a throwaway git repo.
