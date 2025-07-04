#!/bin/bash
# File: /srv/provision/05_harden_ssh.sh
# Description: Harden SSH server configuration for security best practices
# Created: 2025-07-04

set -euo pipefail

LOG_PREFIX="[SSH_HARDEN]"

log() { echo -e "\033[1;34m$LOG_PREFIX $1\033[0m"; }
warn() { echo -e "\033[1;33m$LOG_PREFIX WARNING: $1\033[0m"; }
err() { echo -e "\033[1;31m$LOG_PREFIX ERROR: $1\033[0m" >&2; }

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.bak.$(date +%s)"

backup_config() {
  if [ ! -f "$BACKUP" ]; then
    cp "$SSHD_CONFIG" "$BACKUP"
    log "Backed up original sshd_config to $BACKUP"
  else
    log "Backup already exists: $BACKUP"
  fi
}

set_or_replace() {
  local key="$1"
  local value="$2"
  if grep -qE "^\s*${key}\s+" "$SSHD_CONFIG"; then
    sed -i "s|^\s*${key}\s\+.*|${key} ${value}|" "$SSHD_CONFIG"
  else
    echo "${key} ${value}" >> "$SSHD_CONFIG"
  fi
}

main() {
  backup_config

  log "Disabling root login over SSH..."
  set_or_replace "PermitRootLogin" "no"

  log "Disabling SSH protocol 1..."
  set_or_replace "Protocol" "2"

  log "Disabling password authentication; only allow public key..."
  set_or_replace "PasswordAuthentication" "no"

  log "Disabling challenge-response authentication..."
  set_or_replace "ChallengeResponseAuthentication" "no"

  log "Enabling public key authentication..."
  set_or_replace "PubkeyAuthentication" "yes"

  log "Disabling empty passwords..."
  set_or_replace "PermitEmptyPasswords" "no"

  log "Disabling X11 forwarding unless explicitly needed..."
  set_or_replace "X11Forwarding" "no"

  log "Restarting sshd service to apply changes..."
  systemctl restart sshd

  log "SSH hardening completed successfully."
}

main "$@"
