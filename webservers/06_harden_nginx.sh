#!/bin/bash

# File: /srv/provision/06_harden_nginx.sh
# Created: 2025-07-05
# Description: Harden NGINX for Woodpecker CI webhook endpoint. Enforces POST-only access,
#              GitHub IP whitelisting, and performs endpoint validation.
# Usage: sudo bash /srv/provision/06_harden_nginx.sh

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
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

[[ $EUID -ne 0 ]] && { error "Run as root."; exit 1; }

# === Constants ===
NGINX_CONF="/etc/nginx/sites-enabled/woodpecker"
BACKUP="/etc/nginx/sites-enabled/woodpecker.bak.$(date +%s)"
WEBHOOK_PATH="/github-webhook/"
GITHUB_META_URL="https://api.github.com/meta"
TMP_WHITELIST="/tmp/github_hook_ips.txt"
GITHUB_IP_BLOCKS_REGEX='140\.82\.112\.0/20|192\.30\.252\.0/22|185\.199\.108\.0/22|143\.55\.64\.0/20'

# === Pre-check ===
[[ ! -f "$NGINX_CONF" ]] && {
    error "NGINX config not found at $NGINX_CONF"
    exit 1
}

cp -a "$NGINX_CONF" "$BACKUP"
log "Backup of NGINX config saved to $BACKUP"

# === Fetch GitHub IPs ===
log "Fetching GitHub IPs for hooks..."
curl -fsSL "$GITHUB_META_URL" | jq -r '.hooks[]' > "$TMP_WHITELIST" || {
    error "Failed to fetch GitHub hook IPs"
    exit 1
}

log "Fetched $(wc -l < "$TMP_WHITELIST") IP ranges"

# === Prepare whitelist and insert hardening block ===
HARDEN_BLOCK=$(cat <<EOF

    location = $WEBHOOK_PATH {
        limit_except POST { deny all; }

        # GitHub Hook IP Whitelist
$(awk '{printf "        allow %s;\n", $1}' "$TMP_WHITELIST")

        deny all;
    }
EOF
)

# === Apply hardening ===
if grep -q "location = $WEBHOOK_PATH" "$NGINX_CONF"; then
    warn "Webhook hardening block already exists, replacing..."
    sed -i "/location = $WEBHOOK_PATH {/,/deny all;/d" "$NGINX_CONF"
fi

echo "$HARDEN_BLOCK" >> "$NGINX_CONF"
ok "Webhook hardening block applied to $NGINX_CONF"

# === Reload NGINX ===
nginx -t && systemctl reload nginx && ok "NGINX reloaded successfully" || {
    cp -a "$BACKUP" "$NGINX_CONF"
    error "NGINX failed to reload. Rolled back to backup."
    exit 1
}

# === Test webhook endpoint ===
log "Testing GET request to webhook path (should be 405)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X GET "http://localhost$WEBHOOK_PATH")

if [[ "$HTTP_CODE" == "405" ]]; then
    ok "Webhook GET rejected with 405 Method Not Allowed"
else
    error "Webhook returned unexpected HTTP code: $HTTP_CODE"
    exit 1
fi

log "Webhook endpoint verification complete."
exit 0
