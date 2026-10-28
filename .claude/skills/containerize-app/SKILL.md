---
name: containerize-app
description: Write a production-ready Dockerfile and .dockerignore for a Node.js, Python or Go web app from the toolkit templates (multi-stage, non-root, small base image, listens on $PORT), add a /healthz endpoint if missing, then build and run it locally to prove it works. Use when the app has no Dockerfile, the user asks to dockerize or containerize an app, or an image is too big, runs as root or fails to start.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(docker build:*), Bash(docker images:*)
---

# Skill: containerize-app

Every deployment target in this toolkit runs a container image. This skill produces one that is small, runs as a
non-root user, and behaves the same on a laptop, a VPS and AWS.

## 1. Pick the template

| App | Template | Notes |
|-----|----------|-------|
| Node.js (Express, Fastify, Next.js standalone, NestJS) | `deploy/templates/docker/node/Dockerfile` | needs `package-lock.json` (`npm ci`) |
| Python (Flask, Django, FastAPI) | `deploy/templates/docker/python/Dockerfile` | needs `requirements.txt` with `gunicorn` or `uvicorn` |
| Go | `deploy/templates/docker/go/Dockerfile` | static binary on distroless |
| Anything else | adapt the closest one | keep: multi-stage, non-root `USER`, `$PORT`, no secrets |

Copy it to the repo root as `Dockerfile`, and `deploy/templates/docker/dockerignore` to `.dockerignore`.
Edit only the lines marked `ADJUST` (start command, build step, main package). Show the user the diff.

## 2. Make the app container-friendly (check each, fix with the user's approval)

- **Port:** listens on `0.0.0.0:$PORT` (not `localhost`, not a hard-coded port).
- **Health:** `GET /healthz` returns `200` quickly when the app can serve traffic. If missing, add a minimal handler
  (and, ideally, a cheap database ping). Every target uses it: Caddy, the load balancer, `smoke.sh`, monitoring.
- **Config:** every setting and secret comes from environment variables. Nothing secret in the image.
- **Logs:** to stdout/stderr, not files.
- **Shutdown:** handles `SIGTERM` (finish in-flight requests within ~10 s) so rolling deploys drop no requests.

## 3. Prove it locally

```bash
docker build -t app:dev .
docker run --rm -p 8080:8080 --env-file .env.local app:dev     # .env.local is git-ignored
curl -fsS http://localhost:8080/healthz
docker images app:dev --format '{{.Size}}'                      # Node/Python: aim < 300 MB, Go: < 30 MB
```

If it fails, read the container output first (`docker logs`), then fix the Dockerfile or the app. Common causes:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `connection refused` on curl | app binds to `127.0.0.1` | bind `0.0.0.0` |
| `EACCES` / permission denied | non-root user cannot write | write to `/tmp`, or `chown` the directory in the build |
| image is 1 GB+ | dev dependencies or build cache included | multi-stage, `npm prune --omit=dev`, `.dockerignore` |
| `exec format error` on the server | built on Apple Silicon (arm64) for an amd64 server | `docker build --platform linux/amd64` (CI builds amd64 anyway) |

## 4. Next

Commit the Dockerfile. Images for real deployments are built by CI and tagged with the **commit SHA**, never `latest`
(skill `setup-cd-pipeline`). Next rung: `setup-vps` or `provision-aws-ecs` (see `deploy-getting-started`).

## Roadmap references

[Dockerfile best practices](https://github.com/mascot200/devops-roadmap/blob/main/level-04-docker/README.md) ·
[Image security](https://github.com/mascot200/devops-roadmap/blob/main/level-11-security-devsecops/README.md)
