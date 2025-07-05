#!/bin/bash
#
# File: /srv/provision/03_secure_kernel.sh
# Created: 2025-07-05
# Description: Harden kernel parameters and restrict unsafe syscalls using sysctl and GRUB boot flags.
#

set -euo pipefail
umask 027

# === Constants ===
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="/var/log/provision"
LOG_FILE="${LOG_DIR}/03_secure_kernel.log"
SYSCTL_CONF="/etc/sysctl.d/99-hardening.conf"
GRUB_CFG="/etc/default/grub"
TIMESTAMP() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# === Logging functions ===
log()    { echo -e "[\033[1;34mINFO\033[0m] $*"; echo "[$(TIMESTAMP)] INFO: $*" >> "$LOG_FILE"; }
warn()   { echo -e "[\033[1;33mWARN\033[0m] $*"; echo "[$(TIMESTAMP)] WARN: $*" >> "$LOG_FILE"; }
error()  { echo -e "[\033[1;31mERROR\033[0m] $*" >&2; echo "[$(TIMESTAMP)] ERROR: $*" >> "$LOG_FILE"; }
fatal()  { error "$*"; exit 1; }

# === Setup log directory and file ===
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# === Confirm prompt ===
read -rp $'\033[1;33mThis script will apply kernel-level security hardening. Proceed? [y/N]: \033[0m' confirm
[[ "$confirm" =~ ^[Yy]$ ]] || {
  log "Aborted by user."
  exit 0
}

log "Starting kernel hardening process..."

# === Sysctl Hardening ===
log "Writing sysctl kernel hardening parameters to $SYSCTL_CONF"
cat > "$SYSCTL_CONF" <<EOF
# Kernel hardening parameters applied on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore broadcast ICMP requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 if unused (adjust if IPv6 is required)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1

# Kernel panic on OOM
vm.panic_on_oom = 1
kernel.panic = 10

# Enable ASLR (Address Space Layout Randomization)
kernel.randomize_va_space = 2

# Disable kexec system call (prevents loading new kernel without reboot)
kernel.kexec_load_disabled = 1
EOF

chmod 644 "$SYSCTL_CONF"

log "Applying sysctl settings system-wide"
if sysctl --system >>"$LOG_FILE" 2>&1; then
  log "Sysctl parameters successfully applied"
else
  fatal "Failed to apply sysctl parameters; check $LOG_FILE for details"
fi

# === Verify critical kernel settings ===
log "Verifying applied kernel parameters..."
[[ "$(sysctl -n kernel.kexec_load_disabled)" == "1" ]] || fatal "kexec not disabled as expected"
[[ "$(sysctl -n kernel.randomize_va_space)" == "2" ]] || fatal "ASLR not fully enabled"
log "Kernel parameters verified"

# === GRUB Boot Flags Hardening ===
log "Hardening GRUB bootloader configuration"

# Backup GRUB config
cp -a "$GRUB_CFG" "${GRUB_CFG}.bak.$(date +%s)"
log "Backup of GRUB config saved"

# Prepare GRUB kernel flags
GRUB_FLAGS='slab_nomerge pti=on page_alloc.shuffle=1 vsyscall=none random.trust_cpu=off'

# Idempotent replacement or insertion of GRUB_CMDLINE_LINUX line
if grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB_CFG"; then
  CURRENT_FLAGS=$(grep '^GRUB_CMDLINE_LINUX=' "$GRUB_CFG" | cut -d= -f2- | tr -d '"')
  if [[ "$CURRENT_FLAGS" == *"$GRUB_FLAGS"* ]]; then
    log "GRUB_CMDLINE_LINUX already contains hardened flags"
  else
    # Append flags without duplication
    UPDATED_FLAGS="$CURRENT_FLAGS $GRUB_FLAGS"
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$UPDATED_FLAGS\"|" "$GRUB_CFG"
    log "Appended hardening flags to existing GRUB_CMDLINE_LINUX"
  fi
else
  echo "GRUB_CMDLINE_LINUX=\"$GRUB_FLAGS\"" >> "$GRUB_CFG"
  log "Added new GRUB_CMDLINE_LINUX with hardening flags"
fi

# Verify grub update command exists
if ! command -v update-grub >/dev/null; then
  fatal "update-grub command not found"
fi

log "Updating GRUB configuration"
if update-grub >> "$LOG_FILE" 2>&1; then
  log "GRUB updated successfully"
else
  fatal "GRUB update failed; check $LOG_FILE for details"
fi

log "Kernel-level security hardening completed successfully."

# === Automated reboot prompt ===
read -rp $'\033[1;33mKernel hardening requires a reboot to take effect. Reboot now? [y/N]: \033[0m' reboot_confirm
if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
  log "User accepted reboot. Rebooting now..."
  # Sync disk buffers before reboot
  sync
  # Reboot with explicit command
  exec /sbin/reboot
else
  warn "Reboot deferred by user. Please reboot manually to apply all changes."
fi

exit 0
