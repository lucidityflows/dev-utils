#!/bin/bash
#
# File: provision_server.sh
# Description: A consolidated, idempotent script to provision a production web server.
# It handles system preparation, Docker installation, user/group provisioning,
# project directory setup, SSH server hardening, firewall configuration,
# kernel hardening, and deploy key generation.
#
# Usage: sudo bash provision_server.sh
#

set -euo pipefail
umask 027 # Secure default file permissions

#------------------------------------------------------------------------------
# --- Configuration ---
#------------------------------------------------------------------------------

# Map server usernames to their GitHub usernames to fetch public keys automatically.
# The server username is the key, the GitHub username is the value.
declare -A USERS
USERS=(
    ["rob"]="lucidityflows"
    ["zac"]="zackledotcom"
)

# The group for developers. They will be able to write to the project directory.
DEV_GROUP="devteam"

# The root directory for your web application.
PROJECT_DIR="/srv/www/stackrco"

# Admin IPs that are allowed to connect via SSH (Port 22).
ADMIN_IPS=("165.227.206.120" "104.14.153.66" "167.172.135.124", "136.49.24.198")

# Set to true to disable IPv6 system-wide. Recommended if you do not use it.
DISABLE_IPV6=true

#------------------------------------------------------------------------------
# --- Helper Functions ---
#------------------------------------------------------------------------------

log()   { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

#------------------------------------------------------------------------------
# --- Main Logic ---
#------------------------------------------------------------------------------

main() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This script must be run as root or with sudo."
        exit 1
    fi

    log "Starting full server provisioning..."

    prepare_system
    harden_sudo
    install_docker
    setup_project
    provision_users
    harden_ssh_server
    setup_firewall
    harden_kernel
    setup_dev_directories
    setup_deploy_key

    log "Provisioning script finished!"
    warn "A REBOOT is required to apply all kernel hardening changes."
}

#------------------------------------------------------------------------------
# --- Provisioning Functions ---
#------------------------------------------------------------------------------

# 1. Prepare Base System
prepare_system() {
    log "Preparing base system (updates, essentials)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get -y -qq upgrade
    apt-get install -y -qq curl git unattended-upgrades fail2ban ca-certificates gnupg lsb-release \
        vim bash-completion net-tools make unzip build-essential

    timedatectl set-timezone UTC
    ok "System timezone set to UTC."

    echo 'Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };' > /etc/apt/apt.conf.d/50unattended-upgrades
    echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> /etc/apt/apt.conf.d/50unattended-upgrades
    systemctl enable --now unattended-upgrades &>/dev/null
    ok "System prepared and unattended security upgrades are enabled."
}

# 2. Harden Sudo Configuration
harden_sudo() {
    log "Hardening sudo configuration..."
    local sudo_conf_file="/etc/sudoers.d/90-hardening"

    # Ensure sudoers.d directory exists and has correct permissions
    mkdir -p /etc/sudoers.d
    chmod 0755 /etc/sudoers.d

    cat > "$sudo_conf_file" <<EOF
# Sudo hardening rules
Defaults requiretty
Defaults log_output
Defaults syslog=auth.info
EOF
    chmod 0440 "$sudo_conf_file"
    ok "Sudo hardened (requiretty, logging enabled)."
}

# 3. Install Docker Engine and Compose
install_docker() {
    log "Installing Docker Engine and Docker Compose..."
    if command -v docker &> /dev/null; then
        ok "Docker is already installed."
        return
    fi

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker &>/dev/null
    ok "Docker and Docker Compose installed and enabled."
}

# 4. Setup Project Directory and Group
setup_project() {
    log "Setting up project directory and developer group..."
    if ! getent group "$DEV_GROUP" >/dev/null; then
        groupadd "$DEV_GROUP"
        ok "Group '$DEV_GROUP' created."
    else
        ok "Group '$DEV_GROUP' already exists."
    fi

    mkdir -p "$PROJECT_DIR"
    chown -R root:"$DEV_GROUP" "$PROJECT_DIR"
    chmod 2775 "$PROJECT_DIR"
    ok "Project directory '$PROJECT_DIR' configured."
}

# 5. Create Users and Authorize Their SSH Keys from GitHub
provision_users() {
    log "Provisioning user accounts..."
    for user in "${!USERS[@]}"; do
        local github_user="${USERS[$user]}"
        
        if ! id "$user" &>/dev/null; then
            useradd --create-home --shell /bin/bash --groups sudo,"$DEV_GROUP" "$user"
            ok "User '$user' created."
        else
            usermod -aG sudo,"$DEV_GROUP" "$user"
            ok "User '$user' already exists. Ensured group membership."
        fi

        # Add user to docker group for passwordless docker access
        usermod -aG docker "$user"

        local ssh_dir="/home/$user/.ssh"
        local auth_keys_file="$ssh_dir/authorized_keys"
        mkdir -p -m 700 "$ssh_dir"
        
        log "Fetching SSH keys for '$user' from GitHub user '$github_user'..."
        if curl -s "https://github.com/${github_user}.keys" -o "$auth_keys_file" && [ -s "$auth_keys_file" ]; then
            chmod 600 "$auth_keys_file"
            chown -R "$user:$user" "$ssh_dir"
            ok "Installed SSH keys for user '$user'."
        else
            rm -f "$auth_keys_file"
            warn "No SSH keys found for GitHub user '$github_user'. User '$user' cannot log in via SSH."
        fi
    done
}

# 6. Harden SSH Server Configuration
harden_ssh_server() {
    log "Hardening SSH server configuration..."
    local config_file="/etc/ssh/sshd_config"
    cp -p "$config_file" "${config_file}.bak.$(date +%s)"

    # Idempotently add or replace a setting in sshd_config
    upsert_sshd_config() {
        sed -i -E "s/^[# ]*${1}(\s+.*)?$/${1} ${2}/" "$config_file" || echo "${1} ${2}" >> "$config_file"
    }

    upsert_sshd_config "PermitRootLogin" "no"
    upsert_sshd_config "PasswordAuthentication" "no"
    upsert_sshd_config "ChallengeResponseAuthentication" "no"
    upsert_sshd_config "PubkeyAuthentication" "yes"
    upsert_sshd_config "UsePAM" "yes"
    upsert_sshd_config "X11Forwarding" "no"
    upsert_sshd_config "AllowTcpForwarding" "no"
    upsert_sshd_config "AllowUsers" "$(IFS=" "; echo "${!USERS[*]}")"
    upsert_sshd_config "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
    upsert_sshd_config "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com"
    upsert_sshd_config "LogLevel" "VERBOSE"

    if systemctl reload sshd; then
        ok "SSH server configuration hardened and reloaded."
    else
        error "sshd failed to reload. Restoring backup."
        cp -p "${config_file}.bak.$(date +%s)" "$config_file"
        systemctl reload sshd
        exit 1
    fi
}

# 7. Configure UFW Firewall
setup_firewall() {
    log "Configuring UFW firewall..."
    if ! command -v ufw &>/dev/null; then apt-get install -y -qq ufw; fi

    ufw --force reset >/dev/null
    ufw default deny incoming
    ufw default allow outgoing

    for ip in "${ADMIN_IPS[@]}"; do
        ufw allow from "$ip" to any port 22 proto tcp comment "Allow SSH from admin IP: $ip"
    done

    ufw allow 80/tcp comment 'Allow HTTP'
    ufw allow 443/tcp comment 'Allow HTTPS'
    ufw logging on

    # Harden Docker forwarding rules for UFW compatibility
    sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="DROP"/' /etc/default/ufw

    ufw --force enable
    ok "UFW firewall is enabled and hardened."
}

# 8. Harden Kernel Parameters
harden_kernel() {
    log "Applying kernel hardening parameters via sysctl..."
    local conf_file="/etc/sysctl.d/99-hardening.conf"
    cat > "$conf_file" <<EOF
# Network Hardening
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.log_martians=1
net.ipv4.tcp_syncookies=1

# Security Hardening
kernel.randomize_va_space=2
kernel.kexec_load_disabled=1
EOF

    if [ "$DISABLE_IPV6" = true ]; then
        echo "net.ipv6.conf.all.disable_ipv6=1" >> "$conf_file"
        echo "net.ipv6.conf.default.disable_ipv6=1" >> "$conf_file"
    fi

    sysctl -p "$conf_file" >/dev/null
    ok "Kernel parameters hardened. Reboot is required to apply all changes."
}

# 9. Setup Developer Directories
setup_dev_directories() {
    log "Setting up developer directories..."
    local admin_scripts_dir="/usr/local/sbin/admin-scripts"
    local devops_dir="/srv/devops"
    local projects_dir="/srv/projects"

    mkdir -p "$admin_scripts_dir" "$devops_dir" "$projects_dir"
    chown root:root "$admin_scripts_dir"
    chmod 0755 "$admin_scripts_dir"

    chown root:"$DEV_GROUP" "$devops_dir" "$projects_dir"
    chmod 2775 "$devops_dir" "$projects_dir"
    ok "Developer directories created and configured."
}

# 10. Generate a Server-Specific Deploy Key
setup_deploy_key() {
    log "Setting up a server-specific deploy key..."
    local key_file="/etc/ssh/github_deploy_key"

    if [ ! -f "${key_file}" ]; then
        ssh-keygen -t ed25519 -f "$key_file" -N "" -C "deploy-key-$(hostname)"
        chmod 600 "$key_file"
        chmod 644 "${key_file}.pub"
        ok "New deploy key generated at ${key_file}."
    else
        ok "Deploy key already exists at ${key_file}."
    fi

    echo -e "\n\033[1;33m[ACTION REQUIRED]\033[0m"
    echo "To allow this server to clone repositories, add the following public key"
    echo "to your GitHub repository's 'Deploy Keys' section (read-only is recommended):"
    echo -e "\033[1;32m"
    cat "${key_file}.pub"
    echo -e "\033[0m"
}

# --- Run Script ---
main
