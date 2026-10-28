# Runbooks

One section per alert the toolkit sets up. Each says **what it means**, **what to check first** and **how to fix it**.
Alerts link here directly. The same rule applies to every incident: **if a deploy happened in the last hour, rolling
back is the fastest fix**. Debug afterwards.

You can also ask Claude Code in your app repo: *"EndpointDown fired for production - use the release-verifier agent,
then the rollback-responder if needed."*

| VPS (Prometheus) | AWS (CloudWatch) |
|------------------|------------------|
| [EndpointDown](#endpointdown) · [EndpointSlow](#endpointslow) · [TlsCertificateExpiringSoon](#tlscertificateexpiringsoon) · [MonitoringTargetDown](#monitoringtargetdown) · [HostHighCpu](#hosthighcpu) · [HostLowMemory](#hostlowmemory) · [HostDiskAlmostFull](#hostdiskalmostfull) · [ContainerRestarting](#containerrestarting) · [ContainerNearMemoryLimit](#containernearmemorylimit) | [http-5xx](#http-5xx) · [latency-p95](#latency-p95) · [no-healthy-tasks](#no-healthy-tasks) · [unhealthy-tasks](#unhealthy-tasks) · [running-tasks-low](#running-tasks-low) · [cpu-memory-high](#cpu-memory-high) · [deployment-failed](#deployment-failed) |

Shortcuts used below: `ssh deploy@<host>` for the VPS; `cd /opt/<app>` is the app directory.

---

## VPS alerts

### EndpointDown
**Meaning:** the public health check (`HEALTH_URL`) has failed for 2 minutes. Users are probably affected.

1. Recent deploy? `ENVIRONMENT=<env> bash deploy/scripts/compose-deploy.sh status` shows the current and previous tag.
   If the current tag is new, roll back: `ENVIRONMENT=<env> APPLY=1 bash deploy/scripts/compose-deploy.sh rollback`
   (production also `CONFIRM_PROD=yes-deploy-prod`), or **Actions -> rollback**.
2. Is the app running? `ssh deploy@<host> 'cd /opt/<app> && docker compose ps && docker compose logs --tail=100 app'`
3. Is Caddy OK? `docker compose logs --tail=50 caddy` (certificate or upstream errors).
4. Is it the server? `ENVIRONMENT=<env> bash deploy/scripts/vps-setup.sh status` (disk, memory, load).
5. Is it the database or another dependency? The app logs usually say so.

### EndpointSlow
**Meaning:** the health check has averaged over 1 second for 10 minutes.

Check CPU/memory in Grafana (*Server & app overview*); a slow database query or an exhausted connection pool are the
usual causes. Recent deploy -> compare with the previous version, roll back if it is the cause.

### TlsCertificateExpiringSoon
**Meaning:** the certificate expires in under 14 days, so automatic renewal is failing.

`docker compose logs caddy | grep -i -E 'error|challenge'`. Usual causes: the DNS record no longer points at the
server, or port 80 is blocked (cloud firewall). Fix that, then `docker compose restart caddy`.

### MonitoringTargetDown
**Meaning:** Prometheus cannot scrape part of the monitoring stack, so other alerts may be blind.

`ssh deploy@<host> 'cd /opt/monitoring && docker compose ps'`, then `docker compose up -d`. Check memory (cAdvisor and
Prometheus are the first to be OOM-killed on a small server).

### HostHighCpu
**Meaning:** server CPU above 85% for 15 minutes.

Grafana -> *Container CPU* shows which container. App: a hot loop, a traffic spike or a bot; consider rate limiting in
Caddy, a bigger server, or moving to the AWS rung with autoscaling. Not the app: `top` on the server.

### HostLowMemory
**Meaning:** under 10% memory available; the kernel will soon kill processes.

Grafana -> *Container memory*. Lower `APP_MEM_LIMIT` or fix the leak; restart the offending container as a stop-gap
(`docker compose restart app`); add swap or a bigger server for a lasting fix.

### HostDiskAlmostFull
Also fires as **HostDiskWillFillIn24h** (warning, same steps, more time).

**Meaning:** a filesystem is over 90% full. At 100% Docker, databases and logins break.

```bash
df -h
docker system df                 # images, containers, volumes, build cache
sudo du -xh / --max-depth=2 2>/dev/null | sort -h | tail -15
```
Safe to remove: old images (`docker image prune -a` removes images not used by a container; keep the previous tag if you
may roll back - re-pull is also fine), build cache (`docker builder prune`). Container logs are capped by the toolkit; a
large `/var/log` or an app writing files is the usual culprit. Never delete database volumes to free space.

### ContainerRestarting
**Meaning:** a container restarted more than twice in 15 minutes: a crash loop.

`docker compose logs --tail=200 <container>` shows the crash. `docker inspect <container> --format '{{.State.OOMKilled}}'`
prints `true` if it ran out of memory (see the next alert). After a deploy: roll back first.

### ContainerNearMemoryLimit
**Meaning:** a container uses over 90% of its memory limit; it will be OOM-killed if it grows.

Raise the limit (`APP_MEM_LIMIT` in the server's `.env`, then redeploy) if the usage is legitimate, otherwise look for a
leak (memory graph that only goes up between deploys).

---

## AWS alarms

Useful commands (from `infra/envs/<env>`):
```bash
aws logs tail "$(terraform output -raw log_group)" --since 30m --follow
aws ecs describe-services --cluster "$(terraform output -raw cluster_name)" --services "$(terraform output -raw service_name)" \
  --query 'services[0].{running:runningCount,desired:desiredCount,events:events[:5].message}'
```

### http-5xx
**Meaning:** more server errors than the threshold in 5 minutes. `HTTPCode_Target_5XX` = your app returned 5xx;
`HTTPCode_ELB_5XX` = the load balancer could not reach a healthy task (502/503/504).

Recent deploy -> roll back (re-run the last good deploy, or plan/apply with the previous tag). Otherwise read the logs for
the stack trace; check the database and third-party APIs.

### latency-p95
**Meaning:** the slowest 5% of requests took longer than the threshold for 10 minutes.

Dashboard: CPU/memory saturated? Autoscaling may be at `max_count` (raise it). Otherwise slow queries or a slow dependency.

### no-healthy-tasks
**Meaning:** the load balancer has **no** healthy task. The site is down. Critical.

`describe-services` events (command above) and the logs show why tasks fail health checks: crash on start (missing env
var or secret, bad image), wrong `health_check_path`, or the app is not listening on `PORT`. Recent deploy -> roll back.

### unhealthy-tasks
**Meaning:** at least one task failed health checks for 5 minutes; others still serve traffic.

Same checks as above. ECS replaces unhealthy tasks automatically; if it keeps happening, a task is crashing or the
health check is too strict (it must be fast and not depend on slow dependencies).

### running-tasks-low
**Meaning:** fewer tasks than `min_count` for 5 minutes: crash loop, or Fargate could not place tasks.

`describe-services` events say which. "unable to place" / capacity -> wait or change size; "essential container exited"
-> the logs.

### cpu-memory-high
**Meaning:** average CPU or memory above 85% for 15 minutes even with autoscaling - usually autoscaling is at `max_count`.

Raise `max_count`, or give tasks more `cpu`/`memory` in `infra/envs/<env>/main.tf` (plan, review, apply). For memory
that only grows, look for a leak.

### deployment-failed
**Meaning:** an ECS deployment failed and the circuit breaker **already rolled it back**. Users are on the previous version.

The CD job also fails at "Verify". Read the logs of the failed tasks (they are kept in CloudWatch), fix, and push a new
commit. Do not re-run the same commit expecting a different result.

---

## After any incident

Write five lines while it is fresh: what users saw, when it started and ended, the cause, the fix, and one change that
prevents it (often: a better alert, a test, or a backward-compatible migration). The `rollback-responder` agent drafts
the timeline for you.
