#!/bin/bash

# File: /srv/provision/01_create_users.sh
# Created: 2025-07-05
# Updated: 2025-07-06
# Description: Creates USER1 and USER2 with sudo access, GitHub-based SSH keys, and default passwords.
# Usage: sudo bash /srv/provision/01_create_users.sh

set -euo pipefail
umask 027

USER1="rob"
USER2="zac"
DEFAULT_PASSWORD="Solstice219!!"

USER1_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJhIJ5QiJcK4/6DuEm/zhCR3RneA6pgcAhzl7ezTONVA solsticeskies19@gmail.com"
USER2_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAtw1mq8d0FPLBDDBDX4ULf8kQTtrmJgeY1EVPTVSrIW"

BLUE='\033[1;34m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

[[ $EUID -ne 0 ]] && { error "Run as root or with sudo"; exit 1; }

set_password() {
    local username="$1"
    echo "${username}:${DEFAULT_PASSWORD}" | chpasswd
    passwd --expire "$username"
    ok "Password set for $username (password will be forced to change on first login)."
}

create_user() {
    local username="$1"
    log "Creating user: $username"

    if ! id "$username" &>/dev/null; then
        useradd --create-home --shell /bin/bash --groups sudo --password '!' "$username"
        ok "User $username created with sudo access."
    else
        log "User $username already exists. Skipping creation."
    fi

    # Set home permissions
    chmod 750 "/home/$username"
    chown "$username:$username" "/home/$username"

    # Set default password
    set_password "$username"

    # Setup SSH directory
    local ssh_dir="/home/$username/.ssh"
    mkdir -p -m 700 "$ssh_dir"
    chown "$username:$username" "$ssh_dir"
}

validate_ssh_key() {
    local key="$1"
    [[ "$key" =~ ^ssh-(rsa|ed25519|dss|ecdsa) ]] && return 0 || return 1
}

setup_user_ssh() {
    local username="$1"
    local pubkey="$2"
    log "Setting up SSH key for $username"

    if ! validate_ssh_key "$pubkey"; then
        error "Invalid SSH public key format for $username"
        exit 1
    fi

    local auth_keys="/home/$username/.ssh/authorized_keys"
    local tmpfile
    tmpfile="$(mktemp)"

    echo "$pubkey" > "$tmpfile"
    chown "$username:$username" "$tmpfile"
    chmod 600 "$tmpfile"
    mv "$tmpfile" "$auth_keys"

    ok "SSH key for $username installed."
}

create_user "$USER1"
setup_user_ssh "$USER1" "$USER1_PUBKEY"

create_user "$USER2"
setup_user_ssh "$USER2" "$USER2_PUBKEY"

ok "User provisioning complete."
