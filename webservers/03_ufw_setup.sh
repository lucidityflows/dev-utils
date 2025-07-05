#!/bin/bash
#
# File:        ufw_setup.sh
# Created:     2025-07-05
# Description: Install and configure UFW with secure Docker and Nginx access.
# Path:        /srv/provision/firewall/ufw_setup.sh

set -euo pipefail
umask 027

# === ANSI Colors ===
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# === Root Check ===
[[ $EUID -eq 0 ]] || { log_error "Run as root."; exit 1; }

log_info "Installing ufw if needed..."
if ! command -v ufw >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y ufw
  log_success "ufw installed."
else
  log_info "ufw already present."
fi

log_info "Setting default UFW policies..."
ufw default deny incoming
ufw default allow outgoing

log_info "Allowing essential services..."
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP (Nginx)'
ufw allow 443/tcp comment 'HTTPS (Nginx)'

log_info "Allowing Docker bridge interface..."
DOCKER_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^docker0$' || true)
if [[ -n "$DOCKER_IFACE" ]]; then
  ufw allow in on docker0 comment 'Allow Docker bridge traffic'
else
  log_warn "Docker bridge interface (docker0) not found. Skipping bridge rule."
fi

log_info "Allowing inter-container communication (local Docker subnet)..."
# Typical Docker default: 172.17.0.0/16 (bridge), but adapt as needed
ufw allow from 172.17.0.0/16 comment 'Allow Docker internal container comms'

# Additional user-defined bridge networks (optional)
# ufw allow from 172.18.0.0/16 comment 'User-defined Docker network'

log_warn "This will activate the firewall with current rules."
read -rp "Enable UFW now? [y/N]: " confirm
if [[ "${confirm,,}" == "y" ]]; then
  log_info "Enabling UFW..."
  ufw --force enable
  log_success "UFW is now active."
else
  log_warn "UFW not enabled. Run 'ufw enable' manually when ready."
fi

log_info "UFW status summary:"
ufw status verbose
