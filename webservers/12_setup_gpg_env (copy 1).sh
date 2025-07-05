#!/bin/bash

# File: /srv/provision/12_setup_gpg_env.sh
# Created: 2025-07-05
# Description: Creates a GPG-encrypted .env file for Woodpecker CI secrets and instructions to decrypt during provisioning.
# Usage: sudo bash /srv/provision/12_setup_gpg_env.sh

set -euo pipefail
umask 027

# === Colors ===
BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Ensure script is run as root
[[ $EUID -ne 0 ]] && { error "Run as root."; exit 1; }

SECRETS_DIR="/root"
ENV_PLAIN="$SECRETS_DIR/.woodpecker.env"
ENV_ENC="$SECRETS_DIR/.woodpecker.env.gpg"

# Check if .env already exists
if [[ -f "$ENV_PLAIN" ]]; then
  error "$ENV_PLAIN already exists. Back it up before proceeding."
  exit 1
fi

log "Creating Woodpecker .env file template at $ENV_PLAIN..."

cat > "$ENV_PLAIN" << EOF
# Woodpecker CI Environment Variables - DO NOT COMMIT TO VCS
WOODPECKER_GITHUB_CLIENT_ID="your_github_oauth_client_id"
WOODPECKER_GITHUB_CLIENT_SECRET="your_github_oauth_client_secret"
WOODPECKER_AGENT_SECRET="a_very_secret_random_string"
WOODPECKER_GPG_KEY="-----BEGIN PGP PRIVATE KEY BLOCK-----
...your armored private key here...
-----END PGP PRIVATE KEY BLOCK-----"
EOF

ok "Template .env file created."

log "Encrypting .env file to $ENV_ENC with GPG..."

# Encrypt with symmetric cipher, no passphrase to force usage of gpg agent or manual
gpg --batch --yes --symmetric --cipher-algo AES256 --output "$ENV_ENC" "$ENV_PLAIN"

ok "Encrypted .env file created."

log "Removing plain .env file for security..."
rm -f "$ENV_PLAIN"

ok "Setup complete."

echo -e "${GREEN}IMPORTANT:${NC} To decrypt during provisioning, use:"
echo "gpg --decrypt /root/.woodpecker.env.gpg > /root/.woodpecker.env"

exit 0
