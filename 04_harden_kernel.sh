#!/bin/bash
# File: /srv/provision/03_secure_kernel.sh
# Created: 2025-07-05
# Description: Harden kernel parameters and restrict unsafe syscalls using sysctl and GRUB flags.

set -euo pipefail
umask 027

# === Constants ===
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="/var/log/provision"
LOG_FILE="${LOG_DIR}/03_secure_kernel.log"
SYSCTL_CONF="/etc/sysctl.d/99-hardening.conf"
GRUB_CFG="/etc/default/grub"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# === Logging ===
log()    { echo -e "[\033[1;34mINFO\033[0m] $1"; echo "[$TIMESTAMP] $1" >> "$LOG_FILE"; }
error()  { echo -e "[\033[1;31mERROR\033[0m] $1" >&2; echo "[$TIMESTAMP] ERROR: $1" >> "$LOG_FILE"; }

# === Setup ===
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

read -rp $'\033[1;33mThis script will apply kernel-level security hardening. Proceed? [y/N]: \033[0m' confirm
[[ "$confirm" =~ ^[Yy]$ ]] || {
  log "Aborted by user."
  exit 1
}

log "Applying sysctl kernel hardening parameters..."

# === Sysctl Hardening ===
cat <<EOF > "$SYSCTL_CONF"
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Enable IP spoofing protection
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore broadcast ICMP
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bad error messages
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 (if not needed)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1

# Kernel panic on OOM
vm.panic_on_oom = 1
kernel.panic = 10

# Enable ASLR
kernel.randomize_va_space = 2

# Disable kexec
kernel.kexec_load_disabled = 1
EOF

chmod 644 "$SYSCTL_CONF"
sysctl --system &>> "$LOG_FILE"
log "Sysctl parameters applied from $SYSCTL_CONF"

# === GRUB Hardening Flags ===
log "Harden GRUB boot flags..."
if grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB_CFG"; then
  sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="slab_nomerge pti=on page_alloc.shuffle=1 vsyscall=none random.trust_cpu=off"/' "$GRUB_CFG"
else
  echo 'GRUB_CMDLINE_LINUX="slab_nomerge pti=on page_alloc.shuffle=1 vsyscall=none random.trust_cpu=off"' >> "$GRUB_CFG"
fi

update-grub >> "$LOG_FILE" 2>&1
log "GRUB bootloader flags hardened."

log "Kernel-level security configuration complete. Reboot required to finalize GRUB-level flags."
exit 0
