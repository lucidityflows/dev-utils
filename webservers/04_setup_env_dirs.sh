#!/bin/bash
# File: /srv/provision/04_create_users.sh
# Description: Creates users rob and zac with SSH access and sudo privileges
# Created: 2025-07-04

set -euo pipefail

USERS=("rob" "zac")
LOG_PREFIX="[USER_SETUP]"

log() { echo -e "\033[1;34m$LOG_PREFIX $1\033[0m"; }
warn() { echo -e "\033[1;33m$LOG_PREFIX WARNING: $1\033[0m"; }
err() { echo -e "\033[1;31m$LOG_PREFIX ERROR: $1\033[0m" >&2; }

ensure_user() {
  local username="$1"
  log "Checking if user '$username' exists..."
  if id "$username" &>/dev/null; then
    warn "User '$username' already exists. Skipping creation."
  else
    log "Creating user '$username'..."
    useradd -m -s /bin/bash "$username"
    passwd -l "$username"
    usermod -aG sudo "$username"
  fi

  local ssh_dir="/home/$username/.ssh"
  local auth_keys="$ssh_dir/authorized_keys"
  local github_url="https://github.com/${username}.keys"

  log "Ensuring .ssh directory exists at $ssh_dir..."
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  chown "$username:$username" "$ssh_dir"

  log "Fetching public SSH keys for $username from GitHub..."
  if curl -sfL "$github_url" -o "$auth_keys" && [[ -s "$auth_keys" ]]; then
    log "Successfully retrieved GitHub keys for $username."
  else
    warn "No GitHub keys found for $username. Generating local key..."
    su - "$username" -c "ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519"
    cp "/home/$username/.ssh/id_ed25519.pub" "$auth_keys"
  fi

  chmod 600 "$auth_keys"
  chown "$username:$username" "$auth_keys"
  log "SSH setup complete for $username."
}

main() {
  for user in "${USERS[@]}"; do
    ensure_user "$user"
  done
  log "All requested users configured."
}

main "$@"
