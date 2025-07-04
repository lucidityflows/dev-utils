#!/bin/bash
# File: /srv/provision/01_create_users.sh
# Description: Create secure non-root users with SSH access and sudo privileges.
# Created: 2025-07-04

set -euo pipefail

### CONFIG ###
USERS=("rob" "zac")
GITHUB_USERS=("rob-gh" "zac-gh")  # GitHub usernames
SSH_DIR_MODE=700
AUTH_KEYS_MODE=600
LOG_PREFIX="[USER_SETUP]"

### FUNCTIONS ###

log() {
  echo -e "\033[1;32m$LOG_PREFIX $1\033[0m"
}

err() {
  echo -e "\033[1;31m$LOG_PREFIX ERROR: $1\033[0m" >&2
}

create_user() {
  local user="$1"
  if id "$user" &>/dev/null; then
    log "User '$user' already exists. Skipping."
  else
    useradd -m -s /bin/bash "$user"
    log "Created user '$user'."
    usermod -aG sudo "$user"
    log "Added '$user' to sudo group."
  fi
}

setup_ssh() {
  local user="$1"
  local gh_user="$2"
  local ssh_dir="/home/$user/.ssh"
  local auth_keys="$ssh_dir/authorized_keys"

  mkdir -p "$ssh_dir"
  chmod "$SSH_DIR_MODE" "$ssh_dir"
  chown "$user:$user" "$ssh_dir"

  if curl -sf "https://github.com/$gh_user.keys" | grep "ssh-ed25519" >"$auth_keys"; then
    log "Fetched GitHub keys for '$user'."
  else
    log "No GitHub keys found for '$user'. Generating new ed25519 key."
    sudo -u "$user" ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -C "$user@$(hostname)"
    cp "$ssh_dir/id_ed25519.pub" "$auth_keys"
  fi

  chmod "$AUTH_KEYS_MODE" "$auth_keys"
  chown "$user:$user" "$auth_keys"
}

main() {
  log "Creating user accounts..."
  for i in "${!USERS[@]}"; do
    create_user "${USERS[$i]}"
    setup_ssh "${USERS[$i]}" "${GITHUB_USERS[$i]}"
  done
  log "User provisioning complete."
}

main "$@"
