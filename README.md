# debian-ci-hardening — Zero-Trust Debian Host Hardening & Self-Hosted CI Gatekeeper

![CI](https://github.com/lucidityflows/debian-ci-hardening/actions/workflows/ci.yml/badge.svg)

A production-oriented toolkit of idempotent Debian server provisioning scripts, a tested **Go HMAC-SHA256 webhook gatekeeper daemon**, deterministic post-provisioning security posture verification, and reference **Woodpecker CI** pipeline templates.

---

## Architectural Highlights

1. **Defense-in-Depth Webhook Gatekeeper (`cmd/webhook-verifier/`)**:
   - Rather than exposing a self-hosted CI container's webhook endpoint directly to the public internet, NGINX restricts `/hook` to official GitHub webhook CIDR blocks (`https://api.github.com/meta`) and proxies requests to a sandboxed Go daemon (`127.0.0.1:9900`).
   - Enforces a `1 MiB` `http.MaxBytesReader` payload cap (mitigating memory-exhaustion DoS), strict HTTP read/write timeouts, and constant-time `hmac.Equal` verification of `X-Hub-Signature-256` before forwarding events to Woodpecker CI.
2. **Idempotent Host, SSH, Firewall & Kernel Hardening (`provision/01_provision_server.sh`)**:
   - **SSH Daemon**: Disables root login, password auth, and X11/TCP forwarding; enforces modern AEAD ciphers (`chacha20-poly1305`, `aes256-gcm`); validates configurations with `sshd -t` prior to reload with automatic backup rollback.
   - **UFW + Docker Forwarding Fix**: Restricts `22/tcp` to explicit admin IPs and sets `DEFAULT_FORWARD_POLICY="DROP"` in `/etc/default/ufw` so container bridges cannot bypass host firewall policy.
   - **Kernel (`sysctl`)**: Enables reverse-path filtering (`rp_filter=1`), TCP SYN cookies, martian logging, full ASLR (`randomize_va_space=2`), and disables ICMP redirects, source routing, and `kexec_load`.
3. **Deterministic Posture Audit (`provision/03_verify_hardening.sh`)**:
   - Verifies that every SSHD directive, `sysctl` kernel invariant, UFW forwarding rule, and webhook signature check (confirming unsigned `POST /hook` requests return `HTTP 403 Forbidden`) is actively enforced on the host.

---

## Repository Structure

```text
.
├── cmd/
│   └── webhook-verifier/
│       ├── main.go                   # Hardened Go HMAC-SHA256 webhook proxy with DoS caps & timeouts
│       └── main_test.go              # Unit & integration tests (valid/invalid HMAC, 413 cap, 405/403)
├── provision/
│   ├── 01_provision_server.sh        # Base Debian OS hardening, Docker, GitHub SSH sync, UFW & sysctl
│   ├── 02_install_woodpecker_ci.sh   # Woodpecker CI, NGINX TLS 1.3, Certbot & systemd webhook service
│   └── 03_verify_hardening.sh        # Deterministic post-deployment security posture verifier
├── examples/
│   └── .woodpecker.yml               # Reference 3-stage CI/CD pipeline (Test -> Trivy CVE Scan -> Atomic Rollout)
├── scripts/
│   └── reports-cleanup.sh            # Categorized operational report retention & GZIP archival utility
├── .env.example                      # Template environment configuration
├── go.mod                            # Go module definition
└── LICENSE                           # MIT License
```

---

## Quick Start & Usage

### 1. Run Unit Tests Locally (Webhook Verifier)

```bash
go test -v -race ./...
```

### 2. Provision & Harden Base Server

Review the configuration variables at the top of `provision/01_provision_server.sh` (or export environment overrides from `.env.example`) and run as root:

```bash
chmod +x provision/*.sh
sudo ./provision/01_provision_server.sh
```

### 3. Deploy Woodpecker CI & HMAC Gatekeeper

Ensure your DNS `A` record points `CI_HOSTNAME` to the server IP, export your OAuth and webhook secrets, and execute:

```bash
export CI_HOSTNAME="ci.example.com"
export LETSENCRYPT_EMAIL="admin@example.com"
export WOODPECKER_ADMIN_USER="lucidityflows"

export WOODPECKER_GITHUB_CLIENT_ID="your_github_oauth_client_id"
export WOODPECKER_GITHUB_CLIENT_SECRET="your_github_oauth_client_secret"
export GITHUB_WEBHOOK_SECRET="$(openssl rand -hex 32)"

sudo -E ./provision/02_install_woodpecker_ci.sh
```

### 4. Verify Host Hardening & Gatekeeper Posture

```bash
sudo ./provision/03_verify_hardening.sh
```

---

## License

Released under the [MIT License](LICENSE). Copyright © Robert Torres.
