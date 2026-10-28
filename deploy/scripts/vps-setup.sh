#!/usr/bin/env bash
# deploy/scripts/vps-setup.sh - prepare a fresh Ubuntu/Debian VPS and install the app and monitoring config.
#
# Usage: ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh bootstrap    # once per new server
#        ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh app-config   # upload compose.yaml + Caddyfile
#        ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh monitoring   # Prometheus/Grafana/Alertmanager
#        ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh test-alert   # send a test alert end to end
#        ENVIRONMENT=staging bash deploy/scripts/vps-setup.sh status       # read-only overview
# DRY-RUN unless APPLY=1 (the dry run prints the full remote script). Production also needs CONFIRM_PROD=yes-deploy-prod.
#
# bootstrap   connects as BOOTSTRAP_USER (default root; a sudo user also works) and, idempotently:
#             installs Docker + Compose plugin from Docker's apt repository, caps container log size,
#             creates VPS_USER (docker group) with the bootstrap user's authorized_keys, opens only
#             SSH/80/443 in ufw, enables fail2ban and unattended security upgrades, adds swap
#             (SWAP_SIZE, default 1G, 0 = none), and turns off SSH password login - only when VPS_USER
#             has a key, so you cannot lock yourself out.
# app-config  uploads APP_CONFIG_DIR (default deploy/vps) to VPS_APP_DIR; creates the server-side .env from
#             .env.example only if .env does not exist yet (secrets live there, never in git).
# monitoring  uploads MONITORING_CONFIG_DIR (default deploy/monitoring) to VPS_MONITORING_DIR (default
#             /opt/monitoring), writes the HTTP probe targets (HEALTH_URL + PROBE_URLS), generates a Grafana
#             admin password on the server if none exists, and starts the stack. UIs bind to 127.0.0.1 only.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$HERE/../lib/common.sh"

cmd="${1:-}"
load_targets
require_vars VPS_HOST VPS_USER VPS_APP_DIR
BOOTSTRAP_USER="${BOOTSTRAP_USER:-root}"
APP_CONFIG_DIR="${APP_CONFIG_DIR:-deploy/vps}"
MONITORING_CONFIG_DIR="${MONITORING_CONFIG_DIR:-deploy/monitoring}"
VPS_MONITORING_DIR="${VPS_MONITORING_DIR:-/opt/monitoring}"
SWAP_SIZE="${SWAP_SIZE:-1G}"
SSH_PORT="${SSH_PORT:-22}"
mode_banner

[[ "$VPS_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "VPS_USER '$VPS_USER' is not a valid Linux user name"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "SSH_PORT must be a number"
[[ "$SWAP_SIZE" =~ ^(0|[0-9]+[MG])$ ]] || die "SWAP_SIZE must look like 1G, 512M or 0"

ssh_ro() { ssh -o BatchMode=yes -o ConnectTimeout=10 "${VPS_USER}@${VPS_HOST}" "$@"; }

# vars NAME...: print safe shell assignments, so the quoted remote scripts below need no escaping.
vars() {
  local v
  for v in "$@"; do printf '%s=%q\n' "$v" "${!v}"; done
}

do_bootstrap() {
  guard_production
  local shell="bash -s"
  [ "$BOOTSTRAP_USER" = "root" ] || shell="sudo bash -s"
  log "plan: harden ${BOOTSTRAP_USER}@${VPS_HOST}, install Docker, create deploy user '$VPS_USER', app dir $VPS_APP_DIR"
  {
    DEPLOY_USER="$VPS_USER" APP_DIR="$VPS_APP_DIR" vars DEPLOY_USER APP_DIR SWAP_SIZE SSH_PORT
    cat <<'EOF'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release
case "$ID" in ubuntu | debian) ;; *) echo "unsupported OS '$ID' - use Ubuntu or Debian" >&2; exit 1 ;; esac

echo "== packages"
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg ufw fail2ban python3-systemd unattended-upgrades

echo "== docker (official apt repository)"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" >/etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
if [ ! -f /etc/docker/daemon.json ]; then
  # without a cap, container logs grow until the disk is full
  printf '{\n  "log-driver": "json-file",\n  "log-opts": { "max-size": "10m", "max-file": "3" }\n}\n' >/etc/docker/daemon.json
  systemctl restart docker
fi
systemctl enable --now docker

echo "== deploy user '$DEPLOY_USER'"
id -u "$DEPLOY_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$DEPLOY_USER"
usermod -aG docker "$DEPLOY_USER"
home="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"
src_home="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$home/.ssh"
if [ ! -s "$home/.ssh/authorized_keys" ] && [ -s "$src_home/.ssh/authorized_keys" ]; then
  install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$src_home/.ssh/authorized_keys" "$home/.ssh/authorized_keys"
  echo "copied authorized_keys from ${SUDO_USER:-root}"
fi
install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR"

echo "== firewall: allow ssh ($SSH_PORT), 80, 443 only"
ufw allow "$SSH_PORT/tcp"
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

echo "== fail2ban (sshd jail) and unattended security upgrades"
printf '[sshd]\nenabled = true\nport = %s\nbackend = systemd\n' "$SSH_PORT" >/etc/fail2ban/jail.d/deploy-toolkit.local
systemctl enable --now fail2ban
systemctl restart fail2ban
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' >/etc/apt/apt.conf.d/20auto-upgrades

echo "== swap"
if [ "$SWAP_SIZE" != "0" ] && [ -z "$(swapon --show --noheadings)" ]; then
  if fallocate -l "$SWAP_SIZE" /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile; then
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    echo "added $SWAP_SIZE swap"
  else
    rm -f /swapfile
    echo "WARNING: could not create swap (filesystem may not support fallocate) - continuing without"
  fi
fi

echo "== ssh: keys only"
if [ ! -d /etc/ssh/sshd_config.d ]; then
  echo "WARNING: /etc/ssh/sshd_config.d missing - password login NOT disabled; do it by hand"
elif [ -s "$home/.ssh/authorized_keys" ]; then
  # 01- sorts before 50-cloud-init.conf; the first value sshd reads wins
  conf=/etc/ssh/sshd_config.d/01-deploy-toolkit.conf
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' >"$conf"
  if sshd -t; then
    # with socket activation (Ubuntu 24.04) new connections read the config anyway
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    echo "SSH password login disabled"
  else
    rm -f "$conf"
    echo "WARNING: sshd rejected the hardening config - removed it, password login unchanged"
  fi
else
  echo "WARNING: $DEPLOY_USER has no authorized_keys - password login left ON so you are not locked out"
fi

echo "== done: $(docker --version); $(docker compose version)"
EOF
  } | REMOTE_SHELL="$shell" VPS_USER="$BOOTSTRAP_USER" remote
  log "next: confirm 'ssh ${VPS_USER}@${VPS_HOST}' works, then run: vps-setup.sh app-config"
}

do_app_config() {
  guard_production
  [ -f "$APP_CONFIG_DIR/compose.yaml" ] || die "no $APP_CONFIG_DIR/compose.yaml - copy deploy/templates/vps to $APP_CONFIG_DIR first"
  upload_dir "$APP_CONFIG_DIR" "$VPS_APP_DIR"
  {
    APP_DIR="$VPS_APP_DIR" vars APP_DIR
    cat <<'EOF'
set -Eeuo pipefail
cd "$APP_DIR"
if [ ! -f .env ]; then
  if [ -f .env.example ]; then cp .env.example .env; else : >.env; fi
  chmod 600 .env
  echo "created $APP_DIR/.env from .env.example - edit it ON THE SERVER (domain, app secrets) before the first deploy"
fi
IMAGE=config-check IMAGE_TAG=config-check docker compose config --quiet && echo "compose file is valid"
EOF
  } | remote
}

do_monitoring() {
  guard_production
  require_vars HEALTH_URL
  [ -f "$MONITORING_CONFIG_DIR/compose.yaml" ] || die "no $MONITORING_CONFIG_DIR/compose.yaml - copy deploy/templates/observability/vps to $MONITORING_CONFIG_DIR first"
  # shellcheck disable=SC2034  # read indirectly by vars()
  local PROBE_TARGETS="$HEALTH_URL ${PROBE_URLS:-}" MON_DIR="$VPS_MONITORING_DIR" ENV_NAME="$ENVIRONMENT"
  upload_dir "$MONITORING_CONFIG_DIR" "$VPS_MONITORING_DIR"
  {
    vars MON_DIR PROBE_TARGETS ENV_NAME
    cat <<'EOF'
set -Eeuo pipefail
cd "$MON_DIR"
mkdir -p prometheus/targets
{
  echo "# written by vps-setup.sh monitoring - edit PROBE_URLS in the targets file, not this file"
  echo "- labels: { environment: \"$ENV_NAME\" }"
  echo "  targets:"
  for u in $PROBE_TARGETS; do echo "    - \"$u\""; done
} >prometheus/targets/http.yml
# secrets/ is private on the host (700). The subdirectories are bind-mounted into non-root containers
# (grafana uid 472, alertmanager uid 65534), so they and their files must be readable inside the container.
install -d -m 700 secrets
install -d -m 755 secrets/grafana secrets/alertmanager
if [ ! -s secrets/grafana/admin_password ]; then
  head -c 24 /dev/urandom | base64 | tr -d '/+=' >secrets/grafana/admin_password
  echo "generated a Grafana admin password: cat $MON_DIR/secrets/grafana/admin_password (on the server)"
fi
chmod 644 secrets/grafana/admin_password
if [ ! -s secrets/alertmanager/slack_webhook_url ]; then
  echo "NOTE: no Slack webhook yet - alerts are not delivered until you write it to $MON_DIR/secrets/alertmanager/slack_webhook_url"
  : >secrets/alertmanager/slack_webhook_url
fi
chmod 644 secrets/alertmanager/slack_webhook_url
docker compose up -d --remove-orphans
docker compose ps
EOF
  } | remote
  log "Grafana/Prometheus/Alertmanager listen on 127.0.0.1 only. Open them with an SSH tunnel:"
  log "  ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 ${VPS_USER}@${VPS_HOST}"
}

do_test_alert() {
  guard_production
  {
    MON_DIR="$VPS_MONITORING_DIR" vars MON_DIR ENVIRONMENT
    cat <<'EOF'
set -Eeuo pipefail
cd "$MON_DIR"
docker compose exec -T alertmanager amtool alert add DeployToolkitTestAlert severity=warning "environment=$ENVIRONMENT" \
  --annotation=summary="Test alert from vps-setup.sh - if you can read this, alert delivery works" \
  --alertmanager.url=http://127.0.0.1:9093
echo "test alert sent; it should reach your channel within about a minute"
EOF
  } | remote
}

do_status() {
  ro ssh_ro "cd '$VPS_APP_DIR' 2>/dev/null && docker compose ps || echo 'app: not set up ($VPS_APP_DIR)'"
  ro ssh_ro "cd '$VPS_MONITORING_DIR' 2>/dev/null && docker compose ps || echo 'monitoring: not set up ($VPS_MONITORING_DIR)'"
  ro ssh_ro "df -h / | tail -1; free -m | sed -n 2p; uptime" || true
}

case "$cmd" in
  bootstrap) do_bootstrap ;;
  app-config) do_app_config ;;
  monitoring) do_monitoring ;;
  test-alert) do_test_alert ;;
  status) do_status ;;
  *) die "usage: vps-setup.sh bootstrap | app-config | monitoring | test-alert | status" ;;
esac
