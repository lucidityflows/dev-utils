#!/bin/bash
# File: /srv/provision/00_init_environment.sh
# Created: 2025-07-04
# Description: Initialize base environment, secure shell, configure locale/logging, and enforce baseline idempotent state.

set -euo pipefail

# Constants
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="/var/log/provision"
LOG_FILE="${LOG_DIR}/00_init_environment.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create log directory if missing
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Logging function
log() {
  echo -e "[\033[1;34mINFO\033[0m] $1"
  echo -e "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

error() {
  echo -e "[\033[1;31mERROR\033[0m] $1" >&2
  echo -e "[$TIMESTAMP] ERROR: $1" >> "$LOG_FILE"
}

# Confirm execution
read -rp $'\033[1;33mThis script will initialize the base provisioning environment. Continue? [y/N]: \033[0m' confirm
[[ "$confirm" =~ ^[Yy]$ ]] || {
  log "Aborted by user."
  exit 1
}

log "Starting initial environment setup."

# Enforce secure umask
umask 027
log "Set umask to 027."

# Set default shell to bash if not already
if [[ "$SHELL" != "/bin/bash" ]]; then
  chsh -s /bin/bash "$USER"
  log "Changed shell to /bin/bash for user: $USER"
fi

# Enforce UTF-8 locale
log "Ensuring UTF-8 locale settings..."

# Add if not already present
grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen

# Generate locales
locale-gen

# Export locale properly (avoid = instead of space)
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Set persistent system-wide
update-locale LANG="en_US.UTF-8" LC_ALL="en_US.UTF-8"

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
log "Locale set to en_US.UTF-8."

# Harden bash environment
HARDENED_BASHRC="/etc/profile.d/hardened_bash.sh"
cat <<'EOF' > "$HARDENED_BASHRC"
# Hardened bash profile defaults
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T "
export TMOUT=900
export PATH="$PATH:/usr/local/bin"
EOF

chmod 644 "$HARDENED_BASHRC"
log "Hardened bash profile written to $HARDENED_BASHRC"

# Disable core dumps
echo '* hard core 0' >> /etc/security/limits.conf
log "Disabled core dumps."

# Ensure essential packages
log "Ensuring baseline packages..."
apt-get update -qq
apt-get install -yqq curl wget vim gnupg2 ca-certificates lsb-release sudo software-properties-common bash-completion
log "Baseline packages installed."

log "Initial environment provisioning complete."

exit 0
