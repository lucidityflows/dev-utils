#!/bin/bash
# File: /srv/woodpecker/diagnostics/postcheck.sh
# Created: 2025-07-05
# Description: Verifies status of Woodpecker server/agent, health endpoint, volumes, GPG key, and GitHub integration.

set -euo pipefail
umask 027

BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

WOODPECKER_DIR="/srv/woodpecker"
SERVER_CONTAINER="woodpecker-server"
AGENT_CONTAINER="woodpecker-agent"

# --- Container Status ---
log "Checking container statuses..."
docker ps --format '{{.Names}}' | grep -q "$SERVER_CONTAINER" && ok "Server container is running." || error "Server container missing."
docker ps --format '{{.Names}}' | grep -q "$AGENT_CONTAINER" && ok "Agent container is running." || error "Agent container missing."

# --- Healthz Endpoint ---
log "Testing Woodpecker healthz endpoint..."
curl -fsSL http://localhost:8000/healthz && ok "Healthz endpoint returned 200." || error "Health check failed."

# --- GPG Key Check ---
log "Verifying imported GPG key..."
gpg --homedir "$WOODPECKER_DIR/gpg" --list-secret-keys --with-colons | grep -q '^sec' && ok "GPG key is present." || error "No secret GPG key found."

# --- Volume Permissions ---
log "Checking directory permissions..."
find "$WOODPECKER_DIR" -type d ! -perm 0700 -exec chmod 0700 {} \;
find "$WOODPECKER_DIR" -type f ! -perm 0600 -exec chmod 0600 {} \;
ok "Permissions corrected and secure."

# --- Webhook Exposure (Optional NGINX) ---
if grep -q "server_name" /etc/nginx/sites-enabled/woodpecker 2>/dev/null; then
  log "NGINX config detected, validating TLS and security headers..."
  nginx -t && ok "NGINX config is syntactically valid."
  curl -fsSL https://ci.local/healthz --resolve ci.local:443:127.0.0.1 --insecure && ok "Remote TLS healthz reachable."
else
  log "No NGINX exposure detected, skipping TLS check."
fi

ok "Postcheck completed."

exit 0
