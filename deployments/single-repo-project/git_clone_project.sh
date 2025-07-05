#!/bin/bash

###############################################################################
# File:        git_clone_project.sh
# Created:     2025-07-03
# Description: Clone a Git repository into /srv/www/<project> with permissions
# Path:        /srv/provision/git_clone_project.sh
###############################################################################

set -euo pipefail

# Constants (edit as needed)
REPO_URL="git@github.com:your-org/your-repo.git"
PROJECT_NAME="lucidstack-api"
DEST_DIR="/srv/www/${PROJECT_NAME}"
GROUP_NAME="devteam"
GIT_BRANCH="main"

# ANSI colors
RED=$(tput setaf 1)
GRN=$(tput setaf 2)
YLW=$(tput setaf 3)
BLU=$(tput setaf 4)
RST=$(tput sgr0)

log() { echo -e "${BLU}[INFO]${RST} $*"; }
warn() { echo -e "${YLW}[WARN]${RST} $*"; }
error() { echo -e "${RED}[ERROR]${RST} $*" >&2; }

confirm() {
    read -rp "$(echo -e "${YLW}[PROMPT]${RST} Proceed with cloning to ${DEST_DIR}? (y/N): ")" yn
    [[ "$yn" =~ ^[Yy]$ ]] || exit 1
}

# Ensure group exists
if ! getent group "${GROUP_NAME}" >/dev/null; then
    log "Creating group: ${GROUP_NAME}"
    sudo groupadd "${GROUP_NAME}"
fi

# Ensure destination parent
sudo mkdir -p "${DEST_DIR}"
sudo chown root:"${GROUP_NAME}" "${DEST_DIR}"
sudo chmod 2775 "${DEST_DIR}" # sticky group bit

# Clone repo if not present
if [ ! -d "${DEST_DIR}/.git" ]; then
    confirm
    log "Cloning ${REPO_URL} into ${DEST_DIR}"
    sudo git clone --branch "${GIT_BRANCH}" "${REPO_URL}" "${DEST_DIR}"
    sudo chown -R root:"${GROUP_NAME}" "${DEST_DIR}"
    sudo find "${DEST_DIR}" -type d -exec chmod 2775 {} +
    sudo find "${DEST_DIR}" -type f -exec chmod 0664 {} +
else
    warn "Git repository already exists at ${DEST_DIR}"
    log "Fetching latest changes from ${GIT_BRANCH}"
    cd "${DEST_DIR}" && sudo git pull origin "${GIT_BRANCH}"
fi

# Optional: Set up hooks or post-clone actions
if [ -f "${DEST_DIR}/.deploy/hooks/post-clone.sh" ]; then
    log "Running post-clone hook..."
    bash "${DEST_DIR}/.deploy/hooks/post-clone.sh"
fi

log "✅ Project cloned to ${DEST_DIR}"
