#!/bin/bash
# Name: install_docker.sh
# Description: Installs Docker Engine and Docker Compose v2 on Debian (10/11/12)
# Author: Jib
# Created: 2025-07-04
# Path: /srv/provision/install_docker.sh

set -euo pipefail

# Logging
log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# Safety Prompt
read -rp $'\033[1;34m[?]\033[0m This will install Docker and Docker Compose v2. Continue? [y/N] ' confirm
[[ "${confirm,,}" =~ ^y$ ]] || { warn "Aborted by user."; exit 1; }

# 1. Uninstall old versions
log "Removing old Docker versions (if any)..."
apt-get remove -y docker docker-engine docker.io containerd runc || true

# 2. Install dependencies
log "Installing dependencies..."
apt-get update -qq
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

# 3. Add Docker GPG key
log "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 4. Set up Docker repository
log "Setting up Docker apt repository..."
arch=$(dpkg --print-architecture)
codename=$(lsb_release -cs)

echo \
  "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  ${codename} stable" > /etc/apt/sources.list.d/docker.list

# 5. Install Docker Engine + Compose v2 plugin
log "Installing Docker Engine and Compose v2..."
apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 6. Post-install: group add
log "Adding current user (${USER}) to 'docker' group..."
usermod -aG docker "$USER"

# 7. Enable and start Docker
log "Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker

# 8. Verify installation
log "Verifying Docker installation..."
docker --version
docker compose version

log "✅ Docker and Docker Compose v2 installed successfully."

log "ℹ️ Log out and log back in to use Docker without sudo."
