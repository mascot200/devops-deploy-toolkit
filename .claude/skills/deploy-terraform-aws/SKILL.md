---
name: deploy-terraform-aws
description: Plan, review, apply and drift-check AWS infrastructure managed with Terraform (VPC, subnets, security groups, EC2/ALB, RDS, Redis) using a saved plan file and explicit approval. Use when the user wants to provision or change AWS infrastructure, run terraform plan or apply, or check for infrastructure drift.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*)
---

# Skill: deploy-terraform-aws

Infrastructure changes are the riskiest deployments: a wrong apply can delete a database. This skill makes the
workflow **plan -> human review -> apply the same saved plan**, and refuses to skip steps.

## When to use

- "Create/change/destroy infrastructure", "run terraform", "is prod drifting?" (Projects 4 and 9, Level 7).

## Prerequisites

- `deploy-preflight` passed with `TARGET=terraform`.
- `deploy/targets.<env>.env` defines `TF_DIR` (and optionally `TF_VAR_FILE`, relative to `TF_DIR`).
- AWS credentials come from the environment (`aws sso login`, or an OIDC role in CI). **Never** paste keys.
  Check the identity before anything else: `aws sts get-caller-identity` and confirm it is the intended account.
- The module uses a **remote backend with locking** (S3 with `use_lockfile`, or DynamoDB). If state is local, stop and tell the user.
  See [State and remote backends](https://github.com/mascot200/devops-roadmap/blob/main/level-07-terraform-iac/04-state-and-remote-backends.md) and
  [State locking](https://github.com/mascot200/devops-roadmap/blob/main/level-07-terraform-iac/08-state-locking.md).

## Procedure

### 1. Confirm the account
```bash
aws sts get-caller-identity
```
Read the account id back to the user. Wrong account is the classic way to damage production.

### 2. Plan (read-only: changes no infrastructure)
```bash
ENVIRONMENT=staging bash deploy/scripts/terraform.sh plan
```
This runs `init`, `fmt -check`, `validate`, then `plan -out=tfplan`, and prints a summary:
`create=N update=N delete_or_replace=N`.

Optional, if installed (run read-only): `tflint`, `checkov -d <TF_DIR>`, `infracost breakdown --path <TF_DIR>`.

### 3. Review the plan with the user
Walk through **every** resource marked delete or replace. Typical dangers:

| Plan shows | Meaning | Ask |
|------------|---------|-----|
| `aws_db_instance ... replace` | database will be destroyed and recreated | "Is there a fresh snapshot, and is data loss acceptable?" |
| `aws_security_group ... update` opening `0.0.0.0/0` | public exposure | "Why does this need to be public?" |
| `aws_instance ... replace` | server rebuilt; downtime | "Is it behind an ASG/ALB?" |
| IAM `*` actions or resources | privilege escalation risk | "What is the minimum needed?" |

### 4. Approval gate
Ask the user to approve **the plan summary you showed**. If the plan deletes or replaces anything, the approval must
mention that explicitly; only then may `ALLOW_DESTROY=1` be used.

### 5. Apply the saved plan (never re-plan)
```bash
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/terraform.sh apply
# only if the user explicitly approved deletions/replacements:
ENVIRONMENT=staging APPLY=1 ALLOW_DESTROY=1 bash deploy/scripts/terraform.sh apply
# production:
ENVIRONMENT=production APPLY=1 CONFIRM_PROD=yes-deploy-prod bash deploy/scripts/terraform.sh apply
```
The script refuses a plan that is older than an hour, was made from a different commit, or contains deletions
without `ALLOW_DESTROY=1`. It applies exactly the file you reviewed.

### 6. Verify
Re-run `ENVIRONMENT=staging bash deploy/scripts/terraform.sh drift` (expect "no drift"), then run `post-deploy-verify`
against any endpoint the change affects.

### Drift check (any time, read-only)
```bash
ENVIRONMENT=production bash deploy/scripts/terraform.sh drift   # exit 0 = clean, exit 3 = drift
```

## Hard rules

- Never run `terraform destroy`, `terraform state rm/mv`, `terraform taint` or `terraform import` as part of a deployment.
  Those are separate, explicitly requested operations.
- Never edit the state file by hand.
- If `apply` fails halfway, **stop**, show the error, run `plan` again and review. Do not retry blindly.
- A stuck lock: report who holds it. `terraform force-unlock` is only for the user to decide.

## Roadmap references

[Terraform level](https://github.com/mascot200/devops-roadmap/blob/main/level-07-terraform-iac/README.md) ·
[Drift detection](https://github.com/mascot200/devops-roadmap/blob/main/level-07-terraform-iac/09-drift-detection.md) ·
[Terraform CI/CD](https://github.com/mascot200/devops-roadmap/blob/main/level-07-terraform-iac/07-terraform-ci-cd.md) ·
[Least-privilege IAM](https://github.com/mascot200/devops-roadmap/blob/main/level-11-security-devsecops/02-least-privilege-iam.md) ·
[Cost: egress](https://github.com/mascot200/devops-roadmap/blob/main/level-20-cost-optimization/07-network-egress-costs.md) ·
[Project 4 - Terraform](https://github.com/mascot200/devops-roadmap/blob/main/projects/project-04-terraform.md)
