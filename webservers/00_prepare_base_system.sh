#!/bin/bash
#
# File: /srv/provision/00_prepare_system.sh
# Created: 2025-07-05
# Description: Base system preparation including updates, essential packages, locale, timezone, and security pre-hardening.
# Usage: sudo bash /srv/provision/00_prepare_system.sh
#

set -euo pipefail
umask 027

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="/var/log/provision"
LOG_FILE="${LOG_DIR}/00_prepare_system.log"
TIMESTAMP() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log()    { echo -e "[${BLUE}INFO${NC}] $1"; echo "[$(TIMESTAMP)] INFO: $1" >> "$LOG_FILE"; }
warn()   { echo -e "[${YELLOW}WARN${NC}] $1"; echo "[$(TIMESTAMP)] WARN: $1" >> "$LOG_FILE"; }
error()  { echo -e "[${RED}ERROR${NC}] $1" >&2; echo "[$(TIMESTAMP)] ERROR: $1" >> "$LOG_FILE"; }
fatal()  { error "$1"; exit 1; }

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

[[ $EUID -eq 0 ]] || fatal "Run this script as root or with sudo."

read -rp $'\033[1;33mThis will update system packages and install essentials. Proceed? [y/N]: \033[0m' confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { log "User aborted."; exit 0; }

log "Updating package cache and upgrading installed packages..."
if apt-get update >> "$LOG_FILE" 2>&1 && apt-get -y upgrade >> "$LOG_FILE" 2>&1; then
    log "System packages updated successfully."
else
    fatal "Package update/upgrade failed. See $LOG_FILE."
fi

log "Installing essential packages..."
ESSENTIALS=(curl wget gnupg ca-certificates apt-transport-https software-properties-common unattended-upgrades fail2ban)
if apt-get install -y "${ESSENTIALS[@]}" >> "$LOG_FILE" 2>&1; then
    log "Essential packages installed."
else
    fatal "Failed to install essential packages. See $LOG_FILE."
fi

# Configure unattended-upgrades
log "Configuring unattended-upgrades for security patches..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::Automatic-Reboot "true";
EOF
chmod 644 /etc/apt/apt.conf.d/50unattended-upgrades

systemctl enable --now unattended-upgrades
log "Unattended upgrades enabled."

# Timezone configuration (default to UTC)
log "Setting system timezone to UTC..."
timedatectl set-timezone UTC

# Locale configuration (en_US.UTF-8)
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Installing locale packages..."
apt-get update -qq
apt-get install -y locales

echo "[INFO] Generating en_US.UTF-8 locale..."
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "[INFO] Setting LANG and LC_ALL to en_US.UTF-8..."
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Disable core dumps globally for security
log "Disabling core dumps for all users..."
cat > /etc/security/limits.d/99-nocoredump.conf <<EOF
*               hard    core            0
EOF

# Disable unnecessary services (example: avahi-daemon)
if systemctl list-unit-files | grep -q '^avahi-daemon.service'; then
    log "Disabling avahi-daemon.service..."
    systemctl disable --now avahi-daemon.service
fi

log "Base system preparation completed successfully."

exit 0
