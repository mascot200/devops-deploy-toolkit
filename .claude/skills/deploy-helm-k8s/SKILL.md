---
name: deploy-helm-k8s
description: Deploy, verify and roll back an application on Kubernetes with Helm (lint, template, helm diff, upgrade --atomic, rollout status, helm rollback). Use when the user wants to install or upgrade a Helm release, deploy to a Kubernetes cluster or kind/EKS namespace, or roll back a Helm release.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*)
---

# Skill: deploy-helm-k8s

Deploys an image tag through a Helm chart whose `image.tag` value selects the version. Uses `--atomic --wait`, so if the
new Pods never become Ready Helm **rolls back automatically**.

## When to use

The user wants a Helm install/upgrade or a Helm rollback (Projects 5 and 6, Levels 8 and 9).
If the cluster is managed by Argo CD or Flux, **do not use Helm directly** - use `deploy-gitops-argocd`
(a manual `helm upgrade` would be reverted by the controller and would break the audit trail).

## Prerequisites

- `deploy-preflight` passed with `TARGET=helm`.
- `deploy/targets.<env>.env` defines `KUBE_CONTEXT K8S_NAMESPACE HELM_RELEASE HELM_CHART HELM_VALUES`.
- **Verify the cluster before anything else** and read it back to the user:
  ```bash
  kubectl config current-context
  kubectl --context <KUBE_CONTEXT> get ns <K8S_NAMESPACE>
  ```
  The script always passes `--kube-context` explicitly so you cannot hit the wrong cluster by accident.
- The chart has readiness/liveness probes, resource requests and limits
  ([probes](https://github.com/mascot200/devops-roadmap/blob/main/level-08-kubernetes/15-liveness-and-readiness-probes.md),
  [requests and limits](https://github.com/mascot200/devops-roadmap/blob/main/level-08-kubernetes/14-resource-requests-and-limits.md)).
  Without a readiness probe, `--wait` cannot tell a broken release from a healthy one.

## Procedure

### 1. Diff (read-only)
```bash
ENVIRONMENT=staging bash deploy/scripts/helm-deploy.sh diff 3f9c1ab
```
Runs `helm lint`, `helm template`, and `helm diff upgrade` (or a dry-run if the diff plugin is missing), then prints release history.
Summarise the diff for the user: image tag change, config changes, new/removed resources, changed resource limits or replicas.

### 2. Approval gate
Ask the user to approve environment + tag + the summarised diff. Production approval must name both.

### 3. Deploy
```bash
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/helm-deploy.sh deploy 3f9c1ab
# production:
ENVIRONMENT=production APPLY=1 CONFIRM_PROD=yes-deploy-prod bash deploy/scripts/helm-deploy.sh deploy 3f9c1ab
```
It runs `helm upgrade --install --atomic --wait --timeout 5m`, then `kubectl rollout status` and lists the Pods.

### 4. Verify
Run `post-deploy-verify`. Also check Pod health directly:
```bash
ENVIRONMENT=staging bash deploy/scripts/helm-deploy.sh status
```
Look for restarts > 0, `CrashLoopBackOff`, `ImagePullBackOff`, `Pending` Pods (resources or scheduling).

### 5. Roll back
```bash
ENVIRONMENT=staging bash deploy/scripts/helm-deploy.sh status                # note the revision numbers
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/helm-deploy.sh rollback      # to previous revision
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/helm-deploy.sh rollback 7    # to revision 7
```

## Failure guide

| Symptom | Likely cause | Check |
|---------|--------------|-------|
| `ImagePullBackOff` | wrong tag, or no pull secret | `kubectl describe pod`, registry credentials |
| `CrashLoopBackOff` | app error, missing env/secret | `kubectl logs --previous` |
| `Pending` forever | requests exceed node capacity, taints | `kubectl describe pod` events |
| `--atomic` rolled back | readiness probe never passed | `kubectl get events`, probe path/port |
| `UPGRADE FAILED: another operation in progress` | interrupted earlier release | `helm history`; do not delete secrets by hand - ask the user |
| `no matches for kind` | CRD missing / API version removed | `kubectl api-resources` |

## Roadmap references

[Helm level](https://github.com/mascot200/devops-roadmap/blob/main/level-09-helm/README.md) ·
[Releases](https://github.com/mascot200/devops-roadmap/blob/main/level-09-helm/04-releases.md) ·
[Deployments and ReplicaSets](https://github.com/mascot200/devops-roadmap/blob/main/level-08-kubernetes/03-deployments-and-replicasets.md) ·
[Rolling deployments](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/10-rolling-deployments.md) ·
[Project 5 - Kubernetes](https://github.com/mascot200/devops-roadmap/blob/main/projects/project-05-kubernetes.md) ·
[Project 6 - Production Kubernetes](https://github.com/mascot200/devops-roadmap/blob/main/projects/project-06-production-kubernetes.md)
