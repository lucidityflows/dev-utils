#!/bin/bash
# File: /srv/provision/02_harden_ssh.sh
# Created: 2025-07-05
# Description: Harden OpenSSH server configuration with restricted user access, strong crypto, and added security flags.
# Usage: sudo bash /srv/provision/02_harden_ssh.sh

set -euo pipefail
umask 027

# === Colors ===
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

[[ $EUID -ne 0 ]] && { error "Run as root or with sudo"; exit 1; }

SSH_CONFIG_FILE="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
ALLOWED_USERS=("rob" "zac")

# Backup original config
log "Backing up original sshd_config to $BACKUP_FILE"
cp -p "$SSH_CONFIG_FILE" "$BACKUP_FILE"

# Helper to add or replace config directives (idempotent)
upsert_sshd_config() {
  local key=$1
  local value=$2
  if grep -qE "^\s*${key}\b" "$SSH_CONFIG_FILE"; then
    # Replace existing directive, preserving order
    sed -i "s|^\s*${key}\b.*|${key} ${value}|" "$SSH_CONFIG_FILE"
  else
    # Append directive
    echo "${key} ${value}" >> "$SSH_CONFIG_FILE"
  fi
}

log "Applying hardened SSH configuration directives..."

# Port and Protocol
upsert_sshd_config "Port" "22"
upsert_sshd_config "Protocol" "2"

# Root login disabled
upsert_sshd_config "PermitRootLogin" "no"

# Allowed users (join with space)
AllowUsers=$(IFS=' '; echo "${ALLOWED_USERS[*]}")
upsert_sshd_config "AllowUsers" "$AllowUsers"

# Disable password authentication
upsert_sshd_config "PasswordAuthentication" "no"
upsert_sshd_config "ChallengeResponseAuthentication" "no"
upsert_sshd_config "UsePAM" "yes"
upsert_sshd_config "PubkeyAuthentication" "yes"

# Strong ciphers and MACs (OpenSSH 8.0+)
upsert_sshd_config "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
upsert_sshd_config "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com"

# Disable X11 forwarding unless explicitly needed
upsert_sshd_config "X11Forwarding" "no"

# Additional recommended security hardening flags
upsert_sshd_config "PermitTunnel" "no"
upsert_sshd_config "AllowTcpForwarding" "no"
upsert_sshd_config "UseDNS" "no"
upsert_sshd_config "LoginGraceTime" "30"
upsert_sshd_config "MaxAuthTries" "3"
upsert_sshd_config "MaxSessions" "10"
upsert_sshd_config "ClientAliveInterval" "300"
upsert_sshd_config "ClientAliveCountMax" "2"
upsert_sshd_config "LogLevel" "VERBOSE"

log "Reloading sshd service..."

if systemctl reload sshd; then
  ok "sshd reloaded successfully."
else
  error "sshd failed to reload. Restoring backup..."
  cp -p "$BACKUP_FILE" "$SSH_CONFIG_FILE"
  systemctl reload sshd || { error "Failed to restore sshd after rollback"; exit 1; }
  exit 1
fi

# Enable systemd rate limiting for sshd service
log "Configuring systemd rate limiting for sshd..."

SSH_SERVICE_OVERRIDE_DIR="/etc/systemd/system/sshd.service.d"
SSH_SERVICE_OVERRIDE_FILE="${SSH_SERVICE_OVERRIDE_DIR}/override.conf"

mkdir -p "$SSH_SERVICE_OVERRIDE_DIR"

cat > "$SSH_SERVICE_OVERRIDE_FILE" <<EOF
[Service]
StartLimitIntervalSec=60
StartLimitBurst=5
EOF

systemctl daemon-reload

ok "SSH hardening complete. Only users (${AllowUsers}) can login with key-based authentication."

exit 0
