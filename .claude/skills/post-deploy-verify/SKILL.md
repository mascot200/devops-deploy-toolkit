---
name: post-deploy-verify
description: Verify a deployment after it ships - smoke test the health endpoint, watch error rate and latency over an observation window, check Pods or containers, and return PASS or ROLLBACK RECOMMENDED with evidence. Use immediately after any deploy to a VPS, Kubernetes or GitOps target, or when the user asks whether a release is healthy.
allowed-tools: Read, Grep, Glob, Bash(git log:*)
---

# Skill: post-deploy-verify

"The command succeeded" is not "the release is healthy". This skill collects **evidence** and returns a verdict.
Run it after every deployment; it is read-only.

## Inputs

| Input | Source |
|-------|--------|
| `HEALTH_URL` | `deploy/targets.<env>.env` |
| Version just deployed | the user / the deploy output |
| Previous known-good version | `status` output of the deploy script |
| Metrics URL (optional) | e.g. Prometheus at `PROM_URL=http://prometheus.example.com:9090` |

## Procedure

### 1. Smoke test (hard gate)
```bash
EXPECT_BODY=ok MAX_LATENCY_MS=800 bash deploy/scripts/smoke.sh "$HEALTH_URL" 200 30 2
```
`FAIL` here means **ROLLBACK RECOMMENDED** immediately. Also hit one real user path (for example `GET /api/products`)
with the same script and the expected status.

### 2. Runtime state
- VPS: `ENVIRONMENT=<env> bash deploy/scripts/compose-deploy.sh status`
- Kubernetes: `ENVIRONMENT=<env> bash deploy/scripts/helm-deploy.sh status` (restarts, `CrashLoopBackOff`, readiness)
- GitOps: `ENVIRONMENT=<env> bash deploy/scripts/gitops-promote.sh status` (`Synced` and `Healthy`)

### 3. Observation window (golden signals)
Observe for at least **5 minutes** (staging) or **15 minutes** (production), checking about every 30 to 60 seconds.
If Prometheus is available, compare the new version against the 1 hour before the deploy
(replace the job label with your own):
```bash
# error ratio (5xx / all) over 5 minutes
curl -sG "$PROM_URL/api/v1/query" --data-urlencode \
  'query=sum(rate(http_requests_total{job="shop-api",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="shop-api"}[5m]))'

# p95 latency over 5 minutes
curl -sG "$PROM_URL/api/v1/query" --data-urlencode \
  'query=histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="shop-api"}[5m])))'

# restarts in the last 15 minutes (Kubernetes)
curl -sG "$PROM_URL/api/v1/query" --data-urlencode \
  'query=sum(increase(kube_pod_container_status_restarts_total{namespace="shop"}[15m]))'
```
No metrics system? Use `smoke.sh` repeatedly and read application logs for new error signatures.

### 4. Decide with explicit thresholds

| Signal | PASS | ROLLBACK RECOMMENDED |
|--------|------|----------------------|
| Smoke test | passes within the retries | fails |
| 5xx ratio | at most the pre-deploy baseline + 0.5 percentage points | above baseline + 1 pp, or above the SLO burn threshold |
| p95 latency | within 20% of baseline | more than 50% above baseline, sustained 5 min |
| Restarts / crash loops | 0 new | any new crash loop |
| New error type in logs | none | a new error that affects users |

In-between results are **INCONCLUSIVE**: extend the window once, then decide. Tie the thresholds to the service's SLO if one exists
([SLOs](https://github.com/mascot200/devops-roadmap/blob/main/level-14-sre/02-slos.md), [error budgets](https://github.com/mascot200/devops-roadmap/blob/main/level-14-sre/04-error-budgets.md)).

### 5. Report in this exact shape
```
VERDICT: PASS | ROLLBACK RECOMMENDED | INCONCLUSIVE
Deployed: <version> to <environment>   Previous good: <version>
Evidence:
  smoke:      <result and latency>
  runtime:    <pods/containers/sync state>
  error rate: <value vs baseline>
  p95:        <value vs baseline>
  logs:       <notable findings or none>
Next step: <nothing | run rollback via <skill> | extend observation to <time>>
```

## Rules

- Verification is read-only. Never trigger a rollback from this skill; recommend it and let the user approve.
- Report numbers, not adjectives. If you could not measure something, say so.
- Never mark PASS only because the deploy command exited 0.

## Roadmap references

[Observability: what to monitor](https://github.com/mascot200/devops-roadmap/blob/main/level-10-observability/11-what-to-monitor.md) ·
[Prometheus and PromQL](https://github.com/mascot200/devops-roadmap/blob/main/level-10-observability/02-prometheus-and-promql.md) ·
[Canary deployments](https://github.com/mascot200/devops-roadmap/blob/main/level-05-cicd/12-canary-deployments.md) ·
[Alert fatigue reduction](https://github.com/mascot200/devops-roadmap/blob/main/level-14-sre/08-alert-fatigue-reduction.md)
