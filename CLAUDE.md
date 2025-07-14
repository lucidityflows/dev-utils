# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a server provisioning automation project that contains bash scripts to set up a production-ready Debian web server with Docker, Woodpecker CI/CD, and security hardening.

## Key Scripts

- `provision/01_provision_server.sh` - Core server provisioning script that handles:
  - System preparation and Docker installation
  - User/group management with GitHub SSH key authentication
  - Project directory setup
  - SSH server hardening and firewall configuration
  - Kernel hardening and deploy key generation

- `provision/02_install_woodpecker_ci.sh` - Woodpecker CI installation script that:
  - Installs and configures Woodpecker CI with Docker Compose
  - Sets up NGINX reverse proxy with Let's Encrypt SSL
  - Configures GitHub webhook integration
  - Creates systemd services for automated management

## Configuration Requirements

### provision_server.sh
Edit these variables before running:
- `USERS`: Map server usernames to GitHub usernames for SSH key fetching
- `DEV_GROUP`: Developer group name (default: devteam)
- `PROJECT_DIR`: Web application root directory
- `ADMIN_IPS`: IP addresses allowed SSH access
- `DISABLE_IPV6`: Set to true/false for IPv6 configuration

### install_woodpecker_ci.sh
Edit these variables before running:
- `CI_HOSTNAME`: FQDN for Woodpecker CI instance
- `LETSENCRYPT_EMAIL`: Email for Let's Encrypt registration
- `WOODPECKER_ADMIN_USER`: GitHub username for primary admin

Required environment variables (set before running):
- `WOODPECKER_GITHUB_CLIENT_ID`
- `WOODPECKER_GITHUB_CLIENT_SECRET`
- `GITHUB_WEBHOOK_SECRET`

## Usage Workflow

1. Run `provision_server.sh` first to set up base system
2. Add generated deploy key to GitHub repository
3. Run `install_woodpecker_ci.sh` to install CI/CD system
4. Create `.woodpecker.yml` in application repository for CI pipeline

## Security Considerations

- Scripts use secure defaults (umask 027)
- IP-based SSH access restrictions
- Kernel hardening configurations
- GitHub OAuth integration for authentication
- HMAC webhook verification
- Automated SSL certificate management

## File Structure

- `provision/` - Contains the two main provisioning scripts
- `config/` - Configuration files directory
- `docs/` - Documentation directory
- `scripts/` - Additional utility scripts directory