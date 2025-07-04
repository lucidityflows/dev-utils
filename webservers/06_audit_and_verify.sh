#!/bin/bash
# File: /srv/provision/07_logging_setup.sh
# Description: Configure rsyslog and logrotate for system and Jenkins logs
# Created: 2025-07-04

set -euo pipefail

LOG_PREFIX="[LOGGING_SETUP]"

log() { echo -e "\033[1;34m$LOG_PREFIX $1\033[0m"; }
warn() { echo -e "\033[1;33m$LOG_PREFIX WARNING: $1\033[0m"; }
err() { echo -e "\033[1;31m$LOG_PREFIX ERROR: $1\033[0m" >&2; }

main() {
  # Check rsyslog installed
  log "Checking rsyslog installation..."
  if ! command -v rsyslogd >/dev/null 2>&1; then
    err "rsyslog is not installed. Install with: apt-get install rsyslog"
    exit 1
  fi

  # Enable and start rsyslog service
  log "Enabling and starting rsyslog service..."
  systemctl enable rsyslog
  systemctl start rsyslog

  # Logrotate Jenkins logs config
  LOGROTATE_CONF="/etc/logrotate.d/jenkins"
  if [[ ! -f "$LOGROTATE_CONF" ]]; then
    log "Creating logrotate configuration for Jenkins logs..."
    cat <<EOF > "$LOGROTATE_CONF"
/var/log/jenkins/jenkins.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
  else
    log "Logrotate configuration for Jenkins already exists."
  fi

  log "Logging setup complete."
}

main "$@"
