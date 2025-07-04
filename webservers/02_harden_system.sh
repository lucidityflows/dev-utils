#!/bin/bash
# File: /srv/provision/02_harden_ssh.sh
# Description: Harden OpenSSH server configuration for production.
# Created: 2025-07-04

set -euo pipefail

LOG_PREFIX="[SSH_HARDEN]"
SSH_CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.bak.$(date +%s)"

log() {
  echo -e "\033[1;34m$LOG_PREFIX $1\033[0m"
}

err() {
  echo -e "\033[1;31m$LOG_PREFIX ERROR: $1\033[0m" >&2
}

backup_config() {
  if [ ! -f "$BACKUP" ]; then
    cp "$SSH_CONFIG" "$BACKUP"
    log "Backup created at $BACKUP"
  fi
}

harden_ssh() {
  log "Applying hardened SSH configuration..."

  # Clean slate: comment out legacy settings
  sed -i.bak '/^#*PermitRootLogin/s/^/#/' "$SSH_CONFIG"
  sed -i '/^#*PasswordAuthentication/s/^/#/' "$SSH_CONFIG"
  sed -i '/^#*ChallengeResponseAuthentication/s/^/#/' "$SSH_CONFIG"
  sed -i '/^#*UsePAM/s/^/#/' "$SSH_CONFIG"
  sed -i '/^#*PermitEmptyPasswords/s/^/#/' "$SSH_CONFIG"

  # Add hardened config
  {
    echo "PermitRootLogin no"
    echo "PasswordAuthentication no"
    echo "ChallengeResponseAuthentication no"
    echo "UsePAM yes"
    echo "PermitEmptyPasswords no"
    echo "AllowUsers rob zac"
    echo "LogLevel VERBOSE"
  } >> "$SSH_CONFIG"

  log "Restarting SSH service..."
  systemctl restart sshd
  log "SSH hardening complete."
}

main() {
  log "Starting SSH hardening..."
  backup_config
  harden_ssh
}

main "$@"
