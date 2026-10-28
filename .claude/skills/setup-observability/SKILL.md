---
name: setup-observability
description: Set up monitoring, dashboards and alerting for a deployed app - on a VPS a Prometheus, Grafana, Alertmanager, node-exporter, cAdvisor and blackbox stack with uptime, latency, TLS-expiry, disk, memory, CPU and crash-loop alerts sent to Slack or email; on AWS ECS the CloudWatch alarms, dashboard and SNS email from provision-aws-ecs. Includes sending a test alert and the runbook for every alert. Use when the user asks about monitoring, observability, metrics, dashboards, uptime checks, alerts, alarms, on-call or "how will I know if my app is down".
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*)
---

# Skill: setup-observability

Goal: **the user learns about problems from an alert, not from a customer**, and every alert says what to do next.
Keep alerts few and actionable; an alert nobody acts on trains people to ignore alerts.

## What to watch (explain this table once)

| Signal | Question it answers | VPS stack | AWS stack |
|--------|---------------------|-----------|-----------|
| Availability | Can users reach it? | `EndpointDown` (blackbox probe of `HEALTH_URL`) | `no-healthy-tasks`, `unhealthy-tasks` |
| Errors | Are requests failing? | app metrics, if exposed | `http-5xx` |
| Latency | Is it slow? | `EndpointSlow` | `latency-p95` |
| Saturation | Is it running out of something? | `HostHighCpu`, `HostLowMemory`, `HostDiskAlmostFull`, `HostDiskWillFillIn24h`, `ContainerNearMemoryLimit` | `cpu-high`, `memory-high` |
| Crashes / bad deploys | Is it restarting? | `ContainerRestarting` | `running-tasks-low`, `deployment-failed` event |
| Certificates | Will HTTPS break? | `TlsCertificateExpiringSoon` | ACM renews automatically |

Every alert links to `docs/RUNBOOKS.md` in the toolkit: meaning, first commands to run, likely fixes.

## VPS: Prometheus + Grafana + Alertmanager

Needs about 500 MB RAM on the server (use a 2 GB VPS), and `setup-vps` done.

1. **Copy the stack:** `mkdir -p deploy/monitoring && cp -R deploy/templates/observability/vps/. deploy/monitoring/` (commit it).
2. **Probe targets:** `HEALTH_URL` from the targets file is probed automatically; add more public URLs with
   `PROBE_URLS="https://app.example.com/ https://app.example.com/api/status"` in `deploy/targets.<env>.env`.
3. **Install (dry run, approve, apply):**
   ```bash
   ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh monitoring
   ENVIRONMENT=staging APPLY=1 bash deploy/scripts/vps-setup.sh monitoring
   ```
   It generates a Grafana admin password **on the server** and starts the stack. Nothing is exposed publicly: the UIs bind
   to `127.0.0.1`.
4. **Alert delivery:** the user creates a Slack incoming webhook (Slack -> Apps -> Incoming Webhooks) and writes it **on
   the server** (it is a secret; never in chat or git):
   ```bash
   ssh deploy@<host>
   nano /opt/monitoring/secrets/alertmanager/slack_webhook_url     # paste the URL, save
   cd /opt/monitoring && docker compose restart alertmanager
   ```
   Email instead: see the commented `email_configs` block in `deploy/monitoring/alertmanager/alertmanager.yml`.
5. **Prove it end to end - an untested alert path does not exist:**
   ```bash
   ENVIRONMENT=staging APPLY=1 bash deploy/scripts/vps-setup.sh test-alert
   ```
   The user must confirm the message arrived.
6. **Open the dashboards** through an SSH tunnel:
   ```bash
   ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 deploy@<host>
   ```
   Grafana at http://localhost:3000 (user `admin`, password: `cat /opt/monitoring/secrets/grafana/admin_password` on the
   server) -> folder **Deploy toolkit** -> *Server & app overview*. Prometheus alerts at http://localhost:9090/alerts.

A monitor on the same server cannot tell you the server itself died. Recommend one **external** uptime check too (any
free uptime service pinging `HEALTH_URL`, alerting by email/SMS).

## AWS ECS: CloudWatch

Already created by `provision-aws-ecs`: alarms -> SNS topic -> `alarm_email`, plus a dashboard.
1. The user must click the **confirmation link** AWS emails to `alarm_email`; until then nothing is delivered.
2. Show them `terraform -chdir=infra/envs/<env> output -raw dashboard_url`.
3. Test delivery once (harmless, the alarm returns to OK at the next evaluation):
   ```bash
   aws cloudwatch set-alarm-state --alarm-name <app>-<env>-http-5xx --state-value ALARM --state-reason "test from setup-observability"
   ```
   This changes alarm state, so ask before running it.
4. Slack or PagerDuty: subscribe them to the `alarm_topic_arn` output (AWS Chatbot for Slack). Tune thresholds with
   `alarm_5xx_threshold` and `alarm_p95_latency_seconds` in the env's `main.tf`.
5. Logs: `aws logs tail /ecs/<app>-<env> --follow`, or CloudWatch Logs Insights for searching.

## Tuning (after a week of real traffic)

- An alert that fired and needed no action: raise its threshold or `for:` duration, or delete it.
- An incident that no alert caught: add one, with a runbook entry.
- Use the numbers in `post-deploy-verify` so release checks and alerts agree.

## Roadmap references

[Observability level](https://github.com/mascot200/devops-roadmap/blob/main/level-10-observability/README.md) ·
[What to monitor](https://github.com/mascot200/devops-roadmap/blob/main/level-10-observability/11-what-to-monitor.md) ·
[SLOs](https://github.com/mascot200/devops-roadmap/blob/main/level-14-sre/02-slos.md) ·
[Project 7 - Observability](https://github.com/mascot200/devops-roadmap/blob/main/projects/project-07-observability.md)
