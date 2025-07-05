#!/bin/bash

# File: /srv/provision/11_verify_webhooks.sh
# Created: 2025-07-05
# Description: Verifies GitHub webhook endpoint security, IP whitelist, and request validation for Woodpecker CI.
# Usage: sudo bash /srv/provision/11_verify_webhooks.sh

set -euo pipefail
umask 027

# === Colors ===
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

[[ $EUID -ne 0 ]] && { error "Run as root."; exit 1; }

NGINX_CONF="/etc/nginx/sites-enabled/woodpecker"
WEBHOOK_PATH="/github-webhook/"

# === Verify NGINX Conf ===
if [[ ! -f "$NGINX_CONF" ]]; then
  error "NGINX config for Woodpecker not found at $NGINX_CONF"
  exit 1
fi

log "Checking NGINX config for webhook security..."

if ! grep -q "limit_except POST" "$NGINX_CONF"; then
  error "No POST-only enforcement on webhook path"
else
  ok "POST-only enforcement found"
fi

if ! grep -q "allow 140.82.112.0/20" "$NGINX_CONF"; then
  error "GitHub IP whitelist missing or incomplete"
else
  ok "GitHub IP whitelist present"
fi

# === Test Webhook Endpoint ===
log "Testing webhook endpoint with curl..."

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X GET "http://localhost$WEBHOOK_PATH")

if [[ "$HTTP_CODE" == "405" ]]; then
  ok "Webhook GET rejected (expected 405 Method Not Allowed)"
else
  error "Unexpected HTTP response code for webhook GET: $HTTP_CODE"
fi

log "Webhook endpoint verification completed."

exit 0
