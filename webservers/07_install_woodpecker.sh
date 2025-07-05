#!/usr/bin/env bash
# /srv/provision/07_install_woodpecker.sh
# Phase 7: Secure installation of Woodpecker CI with Docker, GitHub OAuth, and GPG support

set -euo pipefail

log() {
  echo -e "\033[1;34m[Woodpecker CI]\033[0m $1"
}

fail() {
  echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
  exit 1
}

# Ensure docker is installed
command -v docker >/dev/null || fail "Docker is required. Please install Docker first."

# Create Woodpecker directories
mkdir -p /srv/woodpecker/{data,config,gpg}
chmod 700 /srv/woodpecker/gpg

# Load secrets from .env if available
if [ -f /srv/woodpecker/.env ]; then
  log "Loading secrets from .env file"
  source /srv/woodpecker/.env
else
  fail "/srv/woodpecker/.env file not found. Aborting."
fi

# Verify required environment variables
: "${WOODPECKER_GITHUB_CLIENT_ID:?}"
: "${WOODPECKER_GITHUB_CLIENT_SECRET:?}"
: "${WOODPECKER_ADMIN:?}"
: "${WOODPECKER_AGENT_SECRET:?}"

# GPG support - generate a new key if not present
if [ ! -f /srv/woodpecker/gpg/secring.gpg ]; then
  log "Generating GPG key for pipeline signing..."
  gpg --batch --gen-key <<EOF
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: woodpecker-ci
Name-Email: ci@localhost
Expire-Date: 0
%no-protection
%commit
EOF
  gpg --export-secret-keys --armor > /srv/woodpecker/gpg/secring.gpg
  chmod 600 /srv/woodpecker/gpg/secring.gpg
fi

log "Deploying Woodpecker server container"
docker run -d \
  --name woodpecker-server \
  --restart=always \
  -v /srv/woodpecker/data:/var/lib/woodpecker \
  -v /srv/woodpecker/gpg/secring.gpg:/etc/woodpecker/secring.gpg:ro \
  -e WOODPECKER_OPEN=true \
  -e WOODPECKER_GITHUB=true \
  -e WOODPECKER_GITHUB_CLIENT=$WOODPECKER_GITHUB_CLIENT_ID \
  -e WOODPECKER_GITHUB_SECRET=$WOODPECKER_GITHUB_CLIENT_SECRET \
  -e WOODPECKER_GITHUB_SCOPE=repo,admin:repo_hook,user:email \
  -e WOODPECKER_SERVER_ADDR=http://localhost:8000 \
  -e WOODPECKER_AGENT_SECRET=$WOODPECKER_AGENT_SECRET \
  -e WOODPECKER_ADMIN=$WOODPECKER_ADMIN \
  -e WOODPECKER_SECRET_KEY=/etc/woodpecker/secring.gpg \
  -p 8000:8000 \
  woodpeckerci/woodpecker-server:latest

log "Deploying Woodpecker agent container"
docker run -d \
  --name woodpecker-agent \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e WOODPECKER_SERVER=ws://localhost:8000/ws/broker \
  -e WOODPECKER_AGENT_SECRET=$WOODPECKER_AGENT_SECRET \
  -e WOODPECKER_BACKEND=docker \
  woodpeckerci/woodpecker-agent:latest

# Hardened NGINX config with webhook protection and Let's Encrypt support
cat >/etc/nginx/sites-available/woodpecker <<EOF
server {
    listen 443 ssl http2;
    server_name ci.local;

    ssl_certificate     /etc/letsencrypt/live/ci.local/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ci.local/privkey.pem;
    ssl_session_cache   shared:SSL:10m;
    ssl_protocols       TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    limit_req_zone \$binary_remote_addr zone=github_webhook:10m rate=10r/m;

    location /github-webhook/ {
        proxy_pass         http://localhost:8000/github-webhook/;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;

        allow 140.82.112.0/20;
        allow 192.30.252.0/22;
        deny  all;

        limit_req zone=github_webhook burst=5 nodelay;
        limit_except POST { deny all; }

        if (\$http_x_hub_signature_256 = '') {
            return 403;
        }

        access_log /var/log/nginx/woodpecker_webhook.log;

        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header Referrer-Policy no-referrer;
    }

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        allow all;
    }

    location / {
        return 302 https://github.com/lucidityflows;
    }
}

server {
    listen 80;
    server_name ci.local;
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
        allow all;
    }
    return 301 https://\$host\$request_uri;
}
EOF

ln -sf /etc/nginx/sites-available/woodpecker /etc/nginx/sites-enabled/woodpecker

# Hardened systemd override for NGINX
mkdir -p /etc/systemd/system/nginx.service.d
cat >/etc/systemd/system/nginx.service.d/override.conf <<EOF
[Service]
ReadWritePaths=/var/log/nginx /var/cache/nginx /var/www/letsencrypt
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl restart nginx

# Cron job for cert renewal
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -

# Systemd watchdogs and liveness probes
cat >/etc/systemd/system/woodpecker-watchdog.service <<EOF
[Unit]
Description=Woodpecker CI Health Watchdog
After=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/woodpecker-health-check.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

cat >/usr/local/bin/woodpecker-health-check.sh <<'EOF'
#!/usr/bin/env bash
while true; do
  if ! curl -fs http://localhost:8000/healthz >/dev/null; then
    echo "[Watchdog] Server unhealthy. Restarting container." | systemd-cat -t woodpecker-watchdog -p warning
    docker restart woodpecker-server
  fi
  sleep 60
done
EOF

chmod +x /usr/local/bin/woodpecker-health-check.sh
systemctl daemon-reload
systemctl enable --now woodpecker-watchdog.service

# Provisioning tests
log "Running post-provision tests"

if docker ps | grep -q woodpecker-server && docker ps | grep -q woodpecker-agent; then
  log "Containers running"
else
  fail "One or more containers failed to start"
fi

curl -fs http://localhost:8000/healthz >/dev/null && log "Health endpoint OK" || fail "Health check failed"

log "Woodpecker CI deployed successfully"
exit 0
