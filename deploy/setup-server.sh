#!/usr/bin/env bash
# deploy/setup-server.sh — one-command server setup for Taniwha
# Run from the project root on your local machine:
#   ./deploy/setup-server.sh --admin-user ubuntu --server driky.lol --port 7777
set -euo pipefail

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Colour

ok()   { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
info() { printf "${YELLOW}[INFO]${NC}  %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
ADMIN_USER=""
SERVER=""
PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --admin-user) ADMIN_USER="$2"; shift 2 ;;
    --server)     SERVER="$2";     shift 2 ;;
    --port)       PORT="$2";       shift 2 ;;
    *) err "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$ADMIN_USER" || -z "$SERVER" || -z "$PORT" ]]; then
  err "Usage: $0 --admin-user <user> --server <host> --port <port>"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1 — Prerequisite check
# ---------------------------------------------------------------------------
info "Step 1/8 — Checking local prerequisites"
for cmd in ssh scp ssh-keyscan openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    err "Required command not found: $cmd"
    exit 1
  fi
done
ok "All prerequisites present"

# ---------------------------------------------------------------------------
# Step 2 — Generate deploy SSH key pair
# ---------------------------------------------------------------------------
info "Step 2/8 — Deploy SSH key pair"
DEPLOY_KEY=~/.ssh/taniwha_deploy
if [[ -f "$DEPLOY_KEY" ]]; then
  info "Key $DEPLOY_KEY already exists — reusing it"
else
  ssh-keygen -t ed25519 -C "taniwha-deploy@github-actions" -N "" -f "$DEPLOY_KEY"
  ok "Generated $DEPLOY_KEY"
fi

# ---------------------------------------------------------------------------
# Step 3 — Server-side user + sudoers setup (via admin SSH)
# ---------------------------------------------------------------------------
info "Step 3/8 — Creating taniwha-deploy user and sudoers on server"
ssh "${ADMIN_USER}@${SERVER}" -p "${PORT}" "
  set -euo pipefail
  # Create user — ignore error if already exists
  sudo adduser --disabled-password --gecos '' taniwha-deploy 2>/dev/null || true
  sudo usermod -aG docker taniwha-deploy
  sudo mkdir -p /home/taniwha-deploy/.ssh /home/taniwha-deploy/taniwha
  sudo chown taniwha-deploy:taniwha-deploy /home/taniwha-deploy/.ssh /home/taniwha-deploy/taniwha
  sudo chmod 700 /home/taniwha-deploy/.ssh
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl start taniwha' \
    'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl stop taniwha' \
    'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl restart taniwha' \
    'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl status taniwha' \
    'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/cp /tmp/taniwha.service /etc/systemd/system/taniwha.service' \
    'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl daemon-reload' \
    'taniwha-deploy ALL=(ALL) NOPASSWD: /bin/systemctl enable taniwha' \
    | sudo tee /etc/sudoers.d/taniwha-deploy > /dev/null
  sudo chmod 440 /etc/sudoers.d/taniwha-deploy
"
ok "User and sudoers configured"

# ---------------------------------------------------------------------------
# Step 4 — Install deploy public key
# ---------------------------------------------------------------------------
info "Step 4/8 — Installing deploy public key on server"
cat "${DEPLOY_KEY}.pub" | ssh "${ADMIN_USER}@${SERVER}" -p "${PORT}" \
  "sudo tee /home/taniwha-deploy/.ssh/authorized_keys > /dev/null && \
   sudo chmod 600 /home/taniwha-deploy/.ssh/authorized_keys && \
   sudo chown taniwha-deploy:taniwha-deploy /home/taniwha-deploy/.ssh/authorized_keys"
ok "Public key installed"

# ---------------------------------------------------------------------------
# Step 5 — Prompt for .env values
# ---------------------------------------------------------------------------
info "Step 5/8 — Gathering environment values"

PHX_HOST=""
while [[ -z "$PHX_HOST" ]]; do
  printf "  PHX_HOST (required, e.g. driky.lol): "
  read -r PHX_HOST
done

printf "  RTORRENT_SOCKET [/var/run/rtorrent/rpc.socket]: "
read -r RTORRENT_SOCKET
RTORRENT_SOCKET="${RTORRENT_SOCKET:-/var/run/rtorrent/rpc.socket}"

printf "  PORT [4000]: "
read -r APP_PORT
APP_PORT="${APP_PORT:-4000}"

SECRET_KEY_BASE="$(openssl rand -base64 48)"
ok "Environment values collected (SECRET_KEY_BASE auto-generated)"

# ---------------------------------------------------------------------------
# Step 6 — Create .env on server via deploy key
# ---------------------------------------------------------------------------
info "Step 6/8 — Writing .env on server"
printf 'SECRET_KEY_BASE=%s\nPHX_HOST=%s\nPORT=%s\nRTORRENT_SOCKET=%s\n\n# OpenTelemetry (optional — leave ENDPOINT empty to disable)\nOTEL_SERVICE_NAME=taniwha\nOTEL_EXPORTER_OTLP_ENDPOINT=\nOTEL_EXPORTER_OTLP_PROTOCOL=http_protobuf\nOTEL_EXPORTER_OTLP_HEADERS=\n' \
  "$SECRET_KEY_BASE" "$PHX_HOST" "$APP_PORT" "$RTORRENT_SOCKET" \
  | ssh -i "$DEPLOY_KEY" -p "${PORT}" "taniwha-deploy@${SERVER}" \
      "tee /home/taniwha-deploy/taniwha/.env > /dev/null && chmod 600 /home/taniwha-deploy/taniwha/.env"
ok ".env written with permissions 600"

# ---------------------------------------------------------------------------
# Step 7 — Copy and enable the systemd unit
# ---------------------------------------------------------------------------
info "Step 7/8 — Installing and enabling systemd unit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp -P "${PORT}" -i "$DEPLOY_KEY" "${SCRIPT_DIR}/taniwha.service" \
  "taniwha-deploy@${SERVER}:/tmp/taniwha.service"
ssh -i "$DEPLOY_KEY" -p "${PORT}" "taniwha-deploy@${SERVER}" \
  "sudo cp /tmp/taniwha.service /etc/systemd/system/taniwha.service && \
   sudo systemctl daemon-reload && \
   sudo systemctl enable taniwha"
ok "systemd unit installed and enabled"

# ---------------------------------------------------------------------------
# Step 8 — Print GitHub secrets summary
# ---------------------------------------------------------------------------
info "Step 8/8 — Fetching server host key"
HOST_KEY="$(ssh-keyscan -H -p "${PORT}" "${SERVER}" 2>/dev/null)"

printf '\n'
printf '========================================\n'
printf '  GitHub Secrets to configure\n'
printf '========================================\n'
printf 'DEPLOY_SSH_KEY     → (private key shown below)\n'
printf 'DEPLOY_HOST_KEY    → (host key shown below)\n'
printf 'DEPLOY_USER        → taniwha-deploy\n'
printf 'DEPLOY_HOST        → %s\n' "${SERVER}"
printf 'DEPLOY_PORT        → %s\n' "${PORT}"
printf '========================================\n'
printf '\n--- DEPLOY_SSH_KEY (contents of %s) ---\n' "$DEPLOY_KEY"
cat "$DEPLOY_KEY"
printf '\n--- DEPLOY_HOST_KEY (ssh-keyscan output) ---\n'
printf '%s\n' "$HOST_KEY"
printf '========================================\n'
ok "Setup complete. Configure the secrets above in GitHub and push a commit to trigger CD."
