#!/bin/bash
# File: /srv/provision/09_secure_env_gpg.sh
# Description: GPG-encrypts Woodpecker `.env` secrets and installs secure sourcing wrapper

set -euo pipefail
umask 027

# === Config ===
GPG_RECIPIENT="root"
ENV_PLAINTEXT="/root/.woodpecker.env"
ENV_ENCRYPTED="/root/.woodpecker.env.gpg"
ENV_WRAPPER="/usr/local/bin/load-woodpecker-env"

log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

[[ $EUID -ne 0 ]] && { err "Run as root."; exit 1; }

[[ -f "$ENV_PLAINTEXT" ]] || { err "$ENV_PLAINTEXT not found"; exit 1; }

log "Encrypting $ENV_PLAINTEXT to $ENV_ENCRYPTED..."
gpg --yes --batch -r "$GPG_RECIPIENT" -o "$ENV_ENCRYPTED" --encrypt "$ENV_PLAINTEXT"
chmod 600 "$ENV_ENCRYPTED"
rm -f "$ENV_PLAINTEXT"

log "Installing secure sourcing wrapper at $ENV_WRAPPER..."
cat > "$ENV_WRAPPER" <<EOF
#!/bin/bash
# Secure loader for GPG-encrypted .env secrets
set -euo pipefail
gpg --quiet --batch --decrypt "$ENV_ENCRYPTED" | grep -v '^#' | while IFS='=' read -r key value; do
  export "\$key"="\$value"
done
EOF

chmod 750 "$ENV_WRAPPER"
ok "Wrapper installed. Use \`source <(load-woodpecker-env)\` in scripts."

log "Testing decryption..."
source <("$ENV_WRAPPER")
[[ -n "\${WOODPECKER_AGENT_SECRET:-}" ]] && ok "Secrets successfully loaded."

