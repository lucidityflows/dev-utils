# Automated Server Provisioning

This repository contains a set of robust, idempotent, and automated Bash scripts designed to provision a Debian-based web server from a fresh installation. The goal is to create a secure, production-ready environment that includes user management, system hardening, Docker, and a self-hosted Woodpecker CI/CD system.

## Project Structure

- `provision_server.sh`: The core script for initial server setup, user management, system hardening, and deploy key generation.
- `install_woodpecker_ci.sh`: Installs and configures Woodpecker CI, NGINX with automated SSL, and a hardened webhook verifier.

## `provision_server.sh`

This script prepares the operating system, sets up user accounts with GitHub-based SSH key authentication, configures the firewall, hardens the kernel, and creates a dedicated deploy key for the server.

### Usage

1.  **Copy the script** to your new Debian server (e.g., `/root/provision_server.sh`).
2.  **Edit the Configuration Section:** Open the script and modify the variables in the `--- Configuration ---` section to match your environment:
    -   `USERS`: Map desired server usernames to their GitHub usernames (e.g., `["rob"]="lucidityflows"`).
    -   `DEV_GROUP`: The group for developers (default: `devteam`).
    -   `PROJECT_DIR`: The root directory for your web application (e.g., `/srv/www/your-app-name`).
    -   `ADMIN_IPS`: A space-separated list of IP addresses allowed to SSH into the server.
    -   `DISABLE_IPV6`: Set to `true` or `false` to disable IPv6.
3.  **Make it Executable:**
    ```bash
    chmod +x /root/provision_server.sh
    ```
4.  **Run the Script:**
    ```bash
    sudo /root/provision_server.sh
    ```
5.  **Action Required (Deploy Key):** After execution, the script will output a public SSH deploy key. You **must** add this key to your application's GitHub repository (under `Settings > Deploy Keys`) to allow the server to clone your application code.

## `install_woodpecker_ci.sh`

This script installs and configures Woodpecker CI, NGINX as a reverse proxy, automates Let's Encrypt SSL certificate acquisition, and sets up a hardened webhook verifier for GitHub integration.

### Prerequisites

-   **DNS A Record:** Ensure that the `CI_HOSTNAME` (e.g., `ci.your-domain.com`) points to your server's public IP address **before** running this script. Let's Encrypt requires this for certificate validation.
-   **`provision_server.sh` completed:** This script assumes the base system setup (Docker, users, etc.) has been performed by `provision_server.sh`.

### Usage

1.  **Copy the script** to your server (e.g., `/root/install_woodpecker_ci.sh`).
2.  **Edit the Configuration Section:** Open the script and modify the variables:
    -   `CI_HOSTNAME`: The fully qualified domain name for your Woodpecker CI instance.
    -   `LETSENCRYPT_EMAIL`: Your email for Let's Encrypt registration.
    -   `WOODPECKER_ADMIN_USER`: The GitHub username of the primary Woodpecker administrator.
3.  **Set Environment Variables (Secrets):** Before running, you **must** export the following GitHub OAuth secrets into your terminal session. These are sensitive and should not be hardcoded in the script:
    ```bash
    export WOODPECKER_GITHUB_CLIENT_ID="your_github_oauth_client_id"
    export WOODPECKER_GITHUB_CLIENT_SECRET="your_github_oauth_client_secret"
    export GITHUB_WEBHOOK_SECRET="a_long_random_string_for_webhook_hmac_verification"
    ```
    *   You can generate `GITHUB_WEBHOOK_SECRET` using `openssl rand -hex 32`.
    *   `WOODPECKER_GITHUB_CLIENT_ID` and `WOODPECKER_GITHUB_CLIENT_SECRET` are obtained by registering a new OAuth App on GitHub (under your organization or personal settings).
4.  **Make it Executable:**
    ```bash
    chmod +x /root/install_woodpecker_ci.sh
    ```
5.  **Run the Script:**
    ```bash
    sudo /root/install_woodpecker_ci.sh
    ```

## Overall Workflow

1.  Provision a new Debian server.
2.  Copy `provision_server.sh` to the server, configure it, and run it.
3.  Copy `install_woodpecker_ci.sh` to the server, configure it, set environment variables, and run it.
4.  Add the deploy key (output by `provision_server.sh`) to your application's GitHub repository.
5.  Create a `.woodpecker.yml` file in your application's repository to define your CI/CD pipeline.
6.  Push code to your application's repository, and Woodpecker CI will automatically build and deploy it.
