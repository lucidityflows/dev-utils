#!/bin/bash
#
# setup_ssh_config.sh
# Created: 2025-07-05
# Description: Idempotent script to create and configure a production-ready ~/.ssh/config file
# Path: ~/bin/setup_ssh_config.sh
#
# Usage: bash ~/bin/setup_ssh_config.sh
#
# Preconditions: Run as the user who owns ~/.ssh (not root)
#

set -euo pipefail

# ANSI colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m" # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
fatal()   { error "$*"; exit 1; }

SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
CONFIG_D="$SSH_DIR/config.d"

# Check user ownership and environment sanity
if [[ ! -d "$HOME" ]]; then
    fatal "User home directory not found or $HOME not set"
fi

# 1. Create ~/.ssh directory with correct perms
if [[ ! -d "$SSH_DIR" ]]; then
    info "Creating SSH directory $SSH_DIR"
    mkdir -p "$SSH_DIR"
else
    info "SSH directory $SSH_DIR already exists"
fi
chmod 700 "$SSH_DIR"

# 2. Create ~/.ssh/config.d directory with correct perms
if [[ ! -d "$CONFIG_D" ]]; then
    info "Creating SSH config.d directory $CONFIG_D"
    mkdir -p "$CONFIG_D"
else
    info "SSH config.d directory $CONFIG_D already exists"
fi
chmod 700 "$CONFIG_D"

# 3. Write SSH config content idempotently
info "Writing SSH config to $SSH_CONFIG"
cat > "$SSH_CONFIG" <<'EOF'
# ~/.ssh/config
# Created: 2025-07-05
# Description: Production SSH client config for secure, maintainable, and scalable access.

Host *
    ForwardAgent no
    ForwardX11 no
    ServerAliveInterval 60
    ServerAliveCountMax 5
    IdentitiesOnly yes
    StrictHostKeyChecking ask
    UserKnownHostsFile ~/.ssh/known_hosts
    LogLevel ERROR

Host prod-*
    User deploy
    IdentityFile ~/.ssh/prod_deploy_key
    Compression yes


# Host prod-web-01
#     HostName prod-web-01.prod.example.com
#     ProxyJump bastion.prod.example.com

# Host prod-db-01
#     HostName prod-db-01.prod.example.com
#     ProxyJump bastion.prod.example.com

Host dev-*
    User devuser
    IdentityFile ~/.ssh/dev_key
    ForwardAgent yes
    StrictHostKeyChecking accept-new

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_ed25519
    IdentitiesOnly yes

Include ~/.ssh/config.d/*.conf
EOF

chmod 600 "$SSH_CONFIG"

# 4. Validate SSH config syntax
info "Validating SSH config syntax"
if ssh -G dummyhost >/dev/null 2>&1; then
    info "SSH config syntax is valid"
else
    fatal "SSH config syntax check failed"
fi

info "Setup complete. Your ~/.ssh/config is ready for production use."
