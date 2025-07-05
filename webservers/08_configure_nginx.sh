#!/usr/bin/env bash
# /srv/provision/08_configure_nginx.sh
# Phase 8: Deploy hardened NGINX config for Woodpecker CI webhook

set -euo pipefail

log() {
  echo -e "\033[1;34m[NGINX Config]\033[0m $1"
}

fail() {
  echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
  exit 1
}

NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_LINK_DIR="/etc/nginx/sites-enabled"
CONF_NAME="woodpecker.conf"
TARGET_PATH="$NGINX_CONF_DIR/$CONF_NAME"
PROVISION_SOURCE="/srv/provision/nginx/$CONF_NAME"

# Check required certs
if [ ! -f /etc/letsencrypt/live/ci.local/fullchain.pem ]; then
  fail "Missing TLS certificate for ci.local. Run Certbot first."
fi

log "Creating nginx directory if not exists"
mkdir -p "$(dirname "$PROVISION_SOURCE")"

log "Writing hardened NGINX config to $PROVISION_SOURCE"
cat > "$PROVISION_SOURCE" <<'EOF'
server {
    listen 443 ssl http2;
    server_name ci.local;

    ssl_certificate     /etc/letsencrypt/live/ci.local/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ci.local/privkey.pem;
    ssl_session_cache   shared:SSL:10m;
    ssl_protocols       TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    limit_req_zone $binary_remote_addr zone=github_webhook:10m rate=10r/m;

    location /github-webhook/ {
        proxy_pass         http://localhost:8000/github-webhook/;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        allow 140.82.112.0/20;
        allow 192.30.252.0/22;
        deny  all;

        limit_req zone=github_webhook burst=5 nodelay;
        limit_except POST { deny all; }

        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header Referrer-Policy no-referrer;
    }

    location / {
        return 302 https://github.com/lucidityflows;
    }
}

server {
    listen 80;
    server_name ci.local;
    return 301 https://$host$request_uri;
}
EOF

log "Deploying NGINX config to $TARGET_PATH"
cp -f "$PROVISION_SOURCE" "$TARGET_PATH"

log "Linking config in sites-enabled"
ln -sf "$TARGET_PATH" "$NGINX_LINK_DIR/$CONF_NAME"

log "Testing and reloading NGINX"
nginx -t && systemctl reload nginx

log "NGINX config for Woodpecker webhook successfully deployed"
exit 0
