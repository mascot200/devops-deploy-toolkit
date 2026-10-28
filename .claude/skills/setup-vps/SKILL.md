---
name: setup-vps
description: Turn a fresh Ubuntu/Debian VPS (DigitalOcean, Hetzner, Linode, Vultr, Lightsail, EC2) into a hardened Docker host and install the app stack - deploy user, SSH keys only, firewall, fail2ban, automatic security updates, swap, Docker Compose, and Caddy with automatic HTTPS - using vps-setup.sh (dry-run first). Use when the user has a new server, wants to self-host on a VPS or droplet, needs HTTPS/a domain for a VPS app, or before the first deploy-compose-vps deployment.
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(ssh-add -l:*)
---

# Skill: setup-vps

Gets a brand-new server ready for `deploy-compose-vps` in about 15 minutes. Everything goes through
`deploy/scripts/vps-setup.sh`, which is a **dry run unless `APPLY=1`** and prints the full script it would run on the server.

## What the user needs first

- A VPS running **Ubuntu 22.04/24.04 or Debian 12**, at least 1 GB RAM (2 GB if you add monitoring). Created with their
  **SSH public key** (every provider has a field for it). Never ask for or accept a root password.
- A **domain** (or subdomain) with a DNS **A record** pointing at the server's IP. Caddy needs it to get the HTTPS certificate.
  Check: `dig +short app.example.com` returns the server IP.
- Their key loaded locally: `ssh-add -l` lists it, and `ssh root@<ip>` (or `ubuntu@<ip>`) works.

## Procedure

### 1. Describe the server (no secrets)
In `deploy/targets.<env>.env` (copy from `deploy/targets.example.env` if missing):
```bash
VPS_HOST=203.0.113.10
VPS_USER=deploy              # created by bootstrap; deployments use it
VPS_APP_DIR=/opt/shop-api
BOOTSTRAP_USER=root          # the user the provider gave you (root, ubuntu, admin, ...)
HEALTH_URL=https://app.example.com/healthz
IMAGE=ghcr.io/acme/shop-api
```

### 2. Bootstrap (dry run, review, approve, apply)
```bash
ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh bootstrap            # prints the remote script
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/vps-setup.sh bootstrap    # after the user approves
```
Summarize the dry run for the user: installs Docker from Docker's apt repo, caps container logs at 30 MB, creates `deploy`
in the `docker` group with the same SSH keys, firewall allows only SSH/80/443, fail2ban, unattended security upgrades,
1 GB swap (`SWAP_SIZE=0` to skip), and **disables SSH password login only if the deploy user has a key** (no lock-out).
It is idempotent: safe to run again.

Then confirm: `ssh deploy@<host> docker ps` works. Mention that the `docker` group is root-equivalent, so the deploy
key must be protected like a root key.

### 3. App configuration (compose + Caddy)
```bash
mkdir -p deploy/vps && cp -R deploy/templates/vps/. deploy/vps/      # once; commit deploy/vps
```
Edit `deploy/vps/compose.yaml` only if needed (port, memory limit, extra services such as a worker or Redis).
Upload it (dry run first):
```bash
ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh app-config
ENVIRONMENT=staging APPLY=1 bash deploy/scripts/vps-setup.sh app-config
```
The first run creates `/opt/<app>/.env` on the server from `.env.example`. **The user edits it on the server**
(`ssh deploy@<host>` then `nano /opt/<app>/.env`): `DOMAIN`, `APP_PORT`, and the app's secrets. Secrets never go through
the chat, git or the toolkit's files. Later runs never overwrite `.env`.

### 4. Make the image pullable
Public GHCR package: nothing to do. Private: on the server, once, `docker login ghcr.io -u <github-user>` with a
**read:packages** token (the user types it on the server).

### 5. First deployment
Hand over to `deploy-compose-vps` (dry run -> approval -> apply), then `post-deploy-verify`. Caddy obtains the certificate
on the first request; if HTTPS fails, check DNS and that ports 80/443 are reachable.

### 6. Next steps to offer
- Automate deploys: `setup-cd-pipeline` (vps).
- Monitoring and alerts: `setup-observability` (vps).
- Backups: if a database runs on this server, set up and **test a restore** of off-server backups before real users arrive.

## Failure guide

| Symptom | Likely cause | Check / fix |
|---------|--------------|-------------|
| `Permission denied (publickey)` for root | provider uses another user | set `BOOTSTRAP_USER=ubuntu` (or `admin`) |
| `sudo: a password is required` | bootstrap user lacks passwordless sudo | run as root, or add NOPASSWD sudo for that user |
| `unsupported OS` | not Ubuntu/Debian | rebuild the VPS with Ubuntu 24.04 |
| Caddy logs `challenge failed` | DNS not pointing here yet, or port 80 blocked by a cloud firewall | `dig +short <domain>`; open 80/443 in the provider's firewall too |
| `DOMAIN` error from compose | `.env` on the server missing `DOMAIN` | edit `/opt/<app>/.env` |
| A published port is reachable despite ufw | Docker bypasses ufw for `ports:` | publish only Caddy; bind other ports to `127.0.0.1:` |

## Roadmap references

[SSH keys](https://github.com/mascot200/devops-roadmap/blob/main/level-01-linux-fundamentals/12-ssh-keys-and-authorized-keys.md) ·
[Docker Compose](https://github.com/mascot200/devops-roadmap/blob/main/level-04-docker/08-docker-compose.md) ·
[Project 2/3](https://github.com/mascot200/devops-roadmap/blob/main/projects/project-03-cicd.md)
