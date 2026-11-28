#!/bin/bash
#
# File: provision/03_verify_hardening.sh
# Description: Deterministic post-provisioning security and compliance audit script.
# Verifies SSH daemon hardening, UFW firewall & Docker forward policy, sysctl kernel
# parameters, and the local HMAC-SHA256 webhook gatekeeper service.
#
# Usage: sudo bash provision/03_verify_hardening.sh
#

set -euo pipefail

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() { echo -e "\033[1;32m[PASS]\033[0m $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "\033[1;31m[FAIL]\033[0m $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; WARN_COUNT=$((WARN_COUNT + 1)); }

check_sshd_directive() {
    local key="$1"
    local expected="$2"
    local sshd_conf="/etc/ssh/sshd_config"

    if [[ ! -f "$sshd_conf" ]]; then
        warn "SSH config ($sshd_conf) not found"
        return
    fi

    if grep -qE "^${key}\s+${expected}\b" "$sshd_conf"; then
        pass "SSHD: ${key} is enforced as '${expected}'"
    else
        fail "SSHD: ${key} is NOT set to '${expected}' in ${sshd_conf}"
    fi
}

check_sysctl_param() {
    local key="$1"
    local expected="$2"
    local actual
    actual=$(sysctl -n "$key" 2>/dev/null || echo "unset")

    if [[ "$actual" == "$expected" ]]; then
        pass "Kernel (sysctl): ${key} = ${actual}"
    else
        fail "Kernel (sysctl): ${key} is '${actual}' (expected '${expected}')"
    fi
}

check_ufw_posture() {
    if [[ -f /etc/default/ufw ]]; then
        if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
            pass "UFW: DEFAULT_FORWARD_POLICY is set to DROP (Docker container isolation)"
        else
            fail "UFW: DEFAULT_FORWARD_POLICY is not DROP in /etc/default/ufw"
        fi
    else
        warn "UFW: /etc/default/ufw not present"
    fi
}

check_webhook_verifier() {
    local health_url="http://127.0.0.1:9900/healthz"
    local hook_url="http://127.0.0.1:9900/hook"

    if ! systemctl is-active --quiet webhook-verifier.service 2>/dev/null; then
        warn "Webhook Verifier: systemd unit webhook-verifier.service is not currently active"
        return
    fi

    local health_code
    health_code=$(curl -s -o /dev/null -w "%{http_code}" "$health_url" || echo "000")
    if [[ "$health_code" == "200" ]]; then
        pass "Webhook Verifier: /healthz responded HTTP 200"
    else
        fail "Webhook Verifier: /healthz responded HTTP ${health_code}"
    fi

    # Verify that an unsigned POST request is rejected with 403 Forbidden
    local unsigned_code
    unsigned_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -d '{"test":true}' "$hook_url" || echo "000")
    if [[ "$unsigned_code" == "403" ]]; then
        pass "Webhook Verifier: Unsigned POST /hook deterministically rejected with HTTP 403"
    else
        fail "Webhook Verifier: Unsigned POST /hook returned HTTP ${unsigned_code} (expected 403)"
    fi
}

main() {
    echo "=================================================================="
    echo " Hardened Host & CI Gatekeeper Posture Verification"
    echo "=================================================================="

    check_sshd_directive "PermitRootLogin" "no"
    check_sshd_directive "PasswordAuthentication" "no"
    check_sshd_directive "X11Forwarding" "no"
    check_sshd_directive "AllowTcpForwarding" "no"

    check_sysctl_param "net.ipv4.conf.all.rp_filter" "1"
    check_sysctl_param "net.ipv4.conf.all.accept_redirects" "0"
    check_sysctl_param "net.ipv4.conf.all.accept_source_route" "0"
    check_sysctl_param "net.ipv4.tcp_syncookies" "1"
    check_sysctl_param "kernel.randomize_va_space" "2"
    check_sysctl_param "kernel.kexec_load_disabled" "1"

    check_ufw_posture
    check_webhook_verifier

    echo "=================================================================="
    echo " Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${WARN_COUNT} warnings"
    echo "=================================================================="

    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
