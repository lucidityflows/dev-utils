#!/bin/bash
#------------------------------------------------------------------------------
# Name:        03_ufw_setup.sh
# Created:     2025-07-05
# Description: Configures and hardens UFW firewall settings for Debian server.
# Path:        /srv/provision/firewall/ufw_setup.sh
#------------------------------------------------------------------------------

set -euo pipefail

### Constants ###
SSH_PORT=22
HTTP_PORT=80
HTTPS_PORT=443
ADMIN_IPS=("165.227.206.120" "104.14.153.66" "136.49.24.198")
LOG_PREFIX="[UFW_SETUP]"

### Colors ###
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()    { echo -e "${GREEN}${LOG_PREFIX} $*${NC}"; }
warn()   { echo -e "${YELLOW}${LOG_PREFIX} $*${NC}"; }
error()  { echo -e "${RED}${LOG_PREFIX} $*${NC}" >&2; }

# Require root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root or via sudo"
  exit 1
fi

# Verify and install ufw if missing
if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw is not installed. Attempting to install..."
    apt-get update -qq && apt-get install -y ufw >/dev/null
    if ! command -v ufw >/dev/null 2>&1; then
        error "Failed to install ufw. Aborting."
        exit 1
    fi
    log "ufw installed successfully."
else
    log "ufw is already installed."
fi

log "Resetting UFW to default settings..."
ufw --force reset

log "Setting default UFW policies..."
ufw default deny incoming
ufw default allow outgoing

log "Allowing SSH access from trusted admin IPs..."
for ip in "${ADMIN_IPS[@]}"; do
    ufw allow from "$ip" to any port ${SSH_PORT} proto tcp comment "Allow SSH from admin IP: $ip"
done

log "Allowing HTTP and HTTPS traffic..."
ufw allow ${HTTP_PORT}/tcp comment 'Allow HTTP'
ufw allow ${HTTPS_PORT}/tcp comment 'Allow HTTPS'

log "Enabling UFW logging..."
ufw logging on

log "Hardening Docker forwarding rules for UFW compatibility..."

UFW_DEFAULT="/etc/default/ufw"
UFW_DEFAULT_BACKUP="${UFW_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
cp -p "$UFW_DEFAULT" "$UFW_DEFAULT_BACKUP"

if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' "$UFW_DEFAULT"; then
    log "DEFAULT_FORWARD_POLICY already set to DROP"
else
    sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' "$UFW_DEFAULT" || \
    echo 'DEFAULT_FORWARD_POLICY="DROP"' >> "$UFW_DEFAULT"
    log "Set DEFAULT_FORWARD_POLICY to DROP"
fi

SYSCTL_CONF="/etc/ufw/sysctl.conf"
SYSCTL_CONF_BACKUP="${SYSCTL_CONF}.bak.$(date +%Y%m%d%H%M%S)"
cp -p "$SYSCTL_CONF" "$SYSCTL_CONF_BACKUP"

if grep -q '^net.ipv4.ip_forward=1' "$SYSCTL_CONF"; then
    log "net.ipv4.ip_forward already enabled in sysctl.conf"
else
    sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' "$SYSCTL_CONF" || \
    echo 'net.ipv4.ip_forward=1' >> "$SYSCTL_CONF"
    log "Enabled net.ipv4.ip_forward in sysctl.conf"
fi

log "Applying sysctl settings for UFW..."
sysctl -p "$SYSCTL_CONF"

log "Enabling and applying UFW rules..."
ufw --force enable
ufw reload

log "UFW status:"
ufw status verbose

log "UFW firewall hardening complete."
