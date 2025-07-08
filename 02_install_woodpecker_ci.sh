#!/bin/bash
#
# File: install_woodpecker_ci.sh
# Description: A consolidated, idempotent script to securely install and configure
# Woodpecker CI, NGINX with automated Let's Encrypt SSL, a hardened webhook verifier,
# and systemd services, using Docker Compose.
#

set -euo pipefail
umask 027

#------------------------------------------------------------------------------
# --- Configuration ---
#------------------------------------------------------------------------------

# The fully qualified domain name for your Woodpecker CI instance.
# IMPORTANT: A DNS A record must point this domain to this server's IP address.
CI_HOSTNAME="ci.stackrco.com"

# The email address for Let's Encrypt registration and renewal notices.
LETSENCRYPT_EMAIL="solsticeskies19@gmail.com"

# The GitHub username (login) of the primary Woodpecker administrator.
WOODPECKER_ADMIN_USER="rob"

#------------------------------------------------------------------------------
# --- Helper Functions ---
#------------------------------------------------------------------------------

log()   { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

#------------------------------------------------------------------------------
# --- Main Logic ---
#------------------------------------------------------------------------------

main() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root or with sudo."
    fi

    log "Starting Woodpecker CI installation for ${CI_HOSTNAME}..."

    check_secrets
    setup_dependencies
    setup_webhook_verifier
    setup_ssl
    configure_nginx
    deploy_woodpecker

    ok "Woodpecker CI deployment is complete!"
    log "Access your instance at: https://${CI_HOSTNAME}"
}

# 1. Verify that required secrets are present in the environment
check_secrets() {
    log "Checking for required secrets in environment variables..."
    : "${WOODPECKER_GITHUB_CLIENT_ID:?ERROR: WOODPECKER_GITHUB_CLIENT_ID is not set. Please export it.}"
    : "${WOODPECKER_GITHUB_CLIENT_SECRET:?ERROR: WOODPECKER_GITHUB_CLIENT_SECRET is not set. Please export it.}"
    : "${GITHUB_WEBHOOK_SECRET:?ERROR: GITHUB_WEBHOOK_SECRET is not set. Please export it.}"
    ok "All required secrets are present."
}

# 2. Install dependencies
setup_dependencies() {
    log "Installing dependencies (NGINX, Certbot, Docker, Go, jq)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq nginx certbot python3-certbot-nginx docker-ce docker-compose-plugin jq golang-go
    ok "Dependencies installed."
}

# 3. Compile and install the webhook signature verifier
setup_webhook_verifier() {
    log "Setting up secure webhook signature verifier..."
    local go_src="/tmp/webhook_verifier.go"
    local go_bin="/usr/local/bin/webhook-verifier"

    cat > "$go_src" <<'EOF'
package main
import (
    "bytes"
    "crypto/hmac"
    "crypto/sha256"
    "encoding/hex"
    "io"
    "log"
    "net/http"
    "os"
)

var (
    secret   = []byte(os.Getenv("GITHUB_WEBHOOK_SECRET"))
    upstream = "http://localhost:8000/hook"
)

func verifySignature(body []byte, sigHeader string) bool {
    if len(sigHeader) < 7 || sigHeader[:7] != "sha256=" { return false }
    sig, err := hex.DecodeString(sigHeader[7:])
    if err != nil { return false }
    h := hmac.New(sha256.New, secret)
    h.Write(body)
    return hmac.Equal(sig, h.Sum(nil))
}

func webhookHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
        return
    }
    sig := r.Header.Get("X-Hub-Signature-256")
    body, err := io.ReadAll(r.Body)
    if err != nil { http.Error(w, "Server Error", http.StatusInternalServerError); return }
    if !verifySignature(body, sig) {
        log.Printf("Invalid signature from %s", r.RemoteAddr)
        http.Error(w, "Invalid signature", http.StatusForbidden)
        return
    }
    req, _ := http.NewRequest("POST", upstream, bytes.NewReader(body))
    req.Header = r.Header
    resp, err := http.DefaultClient.Do(req)
    if err != nil { http.Error(w, "Bad Gateway", http.StatusBadGateway); return }
    defer resp.Body.Close()
    w.WriteHeader(resp.StatusCode)
    io.Copy(w, resp.Body)
}

func main() {
    if len(secret) == 0 { log.Fatal("GITHUB_WEBHOOK_SECRET env var is not set") }
    http.HandleFunc("/hook", webhookHandler)
    log.Println("Starting hardened webhook listener on :9900")
    log.Fatal(http.ListenAndServe(":9900", nil))
}
EOF

    go build -o "$go_bin" "$go_src"

    cat > /etc/systemd/system/webhook-verifier.service <<EOF
[Unit]
Description=Secure GitHub Webhook Verifier
After=network-online.target

[Service]
Type=simple
User=root
Environment="GITHUB_WEBHOOK_SECRET=${GITHUB_WEBHOOK_SECRET}"
ExecStart=${go_bin}
Restart=on-failure
ProtectSystem=full
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now webhook-verifier.service
    ok "Webhook verifier is compiled and running."
}

# 4. Obtain SSL Certificate
setup_ssl() {
    log "Obtaining SSL certificate for ${CI_HOSTNAME}..."
    systemctl stop nginx
    if certbot certonly --standalone -d "${CI_HOSTNAME}" --email "${LETSENCRYPT_EMAIL}" --agree-tos --no-eff-email --non-interactive; then
        ok "SSL certificate obtained successfully."
    else
        error "Certbot failed to obtain an SSL certificate."
    fi
}

# 5. Configure NGINX
configure_nginx() {
    log "Configuring hardened NGINX site..."
    local github_ips
    github_ips=$(curl -s https://api.github.com/meta | jq -r '.hooks[] | "allow \(.);"')
    if [ -z "$github_ips" ]; then error "Failed to fetch GitHub IP ranges."; fi

    local nginx_conf="/etc/nginx/sites-available/${CI_HOSTNAME}.conf"
    cat > "$nginx_conf" <<EOF
server {
    listen 80; server_name ${CI_HOSTNAME}; return 301 https://\$host\$request_uri; }
server {
    listen 443 ssl http2; server_name ${CI_HOSTNAME};
    ssl_certificate /etc/letsencrypt/live/${CI_HOSTNAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CI_HOSTNAME}/privkey.pem;
    ssl_protocols TLSv1.3;

    location /hook {
        ${github_ips}
        deny all;
        proxy_pass http://localhost:9900/hook; # Pass to the secure verifier
    }
    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

    ln -sf "$nginx_conf" "/etc/nginx/sites-enabled/"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl start nginx
    ok "NGINX configured and started."
}

# 6. Deploy Woodpecker using Docker Compose
deploy_woodpecker() {
    log "Deploying Woodpecker via Docker Compose..."
    local compose_dir="/etc/woodpecker"
    local compose_file="${compose_dir}/docker-compose.yml"
    mkdir -p "$compose_dir"

    local agent_secret=$(openssl rand -hex 16)

    cat > "$compose_file" <<EOF
version: '3.8'
services:
  server:
    image: woodpeckerci/woodpecker-server:latest
    container_name: woodpecker-server
    restart: always
    environment:
      - WOODPECKER_SERVER_ADDR=https://${CI_HOSTNAME}
      - WOODPECKER_GITHUB_CLIENT=${WOODPECKER_GITHUB_CLIENT_ID}
      - WOODPECKER_GITHUB_SECRET=${WOODPECKER_GITHUB_CLIENT_SECRET}
      - WOODPECKER_AGENT_SECRET=${agent_secret}
      - WOODPECKER_ADMIN=${WOODPECKER_ADMIN_USER}
    volumes:
      - /var/lib/woodpecker:/var/lib/woodpecker/
    networks:
      - woodpecker-net

  agent:
    image: woodpeckerci/woodpecker-agent:latest
    container_name: woodpecker-agent
    restart: always
    environment:
      - WOODPECKER_SERVER=woodpecker-server:9000
      - WOODPECKER_AGENT_SECRET=${agent_secret}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - woodpecker-net

networks:
  woodpecker-net:
    driver: bridge
EOF

    docker compose -f "$compose_file" up -d
    ok "Woodpecker containers deployed via Docker Compose."
}

# --- Run Script ---
main