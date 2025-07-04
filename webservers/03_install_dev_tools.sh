#!/bin/bash
# File: /srv/provision/03_setup_firewall.sh
# Description: Configures UFW with strict rules for SSH and Jenkins.
# Created: 2025-07-04

set -euo pipefail

LOG_PREFIX="[UFW_SETUP]"
JENKINS_PORT=8080

log() {
  echo -e "\033[1;34m$LOG_PREFIX $1\033[0m"
}

warn() {
  echo -e "\033[1;33m$LOG_PREFIX WARNING: $1\033[0m"
}

err() {
  echo -e "\033[1;31m$LOG_PREFIX ERROR: $1\033[0m" >&2
}

main() {
  log "Checking for UFW installation..."
  if ! command -v ufw >/dev/null; then
    err "UFW not installed. Aborting."
    exit 1
  fi

  log "Resetting existing rules (non-destructive if re-run)..."
  ufw --force reset

  log "Setting default policies..."
  ufw default deny incoming
  ufw default allow outgoing

  log "Allowing SSH and Jenkins ports..."
  ufw allow OpenSSH
  ufw allow ${JENKINS_PORT}/tcp

  log "Enabling UFW with logging..."
  ufw logging on
  ufw --force enable

  log "Firewall successfully configured."
}

main "$@"
