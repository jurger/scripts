#!/usr/bin/env bash
#
# install-docker.sh - install latest Docker Engine + Docker Compose plugin
# with automatic OS/distro detection.
#
# Supported families: Ubuntu, Debian, CentOS/RHEL/Rocky/AlmaLinux, Fedora
#
# Usage:
#   sudo bash install-docker.sh
#

set -euo pipefail

# ---------- Helper functions ----------

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
err()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; }

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        err "This script must be run as root (or via sudo)."
        exit 1
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        err "Cannot find /etc/os-release - unable to detect distro."
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID:-}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"

    # For Debian/Ubuntu, codename may be missing in minimal images
    if [[ -z "$OS_CODENAME" ]] && command -v lsb_release >/dev/null 2>&1; then
        OS_CODENAME="$(lsb_release -cs)"
    fi

    log "Detected distro: ID=$OS_ID, ID_LIKE=$OS_ID_LIKE, VERSION=$OS_VERSION_ID, CODENAME=${OS_CODENAME:-unknown}"
}

already_installed() {
    if command -v docker >/dev/null 2>&1; then
        warn "Docker is already installed: $(docker --version)"
        read -rp "Reinstall/upgrade anyway? [y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
    fi
}

# ---------- Install for Debian/Ubuntu (apt) ----------

install_apt_family() {
    local distro="$1"   # ubuntu | debian

    log "Installing dependencies..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

    log "Adding Docker's official GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${distro}/gpg" \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    log "Adding Docker repository for ${distro} (${OS_CODENAME})..."
    local arch
    arch="$(dpkg --print-architecture)"
    cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${distro} ${OS_CODENAME} stable
EOF

    log "Updating package index and installing Docker..."
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# ---------- Install for RHEL-based (dnf/yum) ----------

install_rpm_family() {
    local distro="$1"   # centos | rhel | fedora

    local pkg_mgr="dnf"
    command -v dnf >/dev/null 2>&1 || pkg_mgr="yum"

    log "Installing dependencies (${pkg_mgr})..."
    $pkg_mgr install -y $( [[ "$pkg_mgr" == "dnf" ]] && echo "dnf-plugins-core" || echo "yum-utils")

    log "Adding Docker repository for ${distro}..."
    if [[ "$distro" == "fedora" ]]; then
        $pkg_mgr config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    else
        $pkg_mgr config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    fi

    log "Installing Docker..."
    $pkg_mgr install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# ---------- Common post-install steps ----------

post_install() {
    log "Enabling and starting docker service..."
    systemctl enable --now docker

    if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
        log "Adding user '${SUDO_USER}' to the docker group..."
        usermod -aG docker "$SUDO_USER"
        warn "User ${SUDO_USER} must log out and back in (or run: newgrp docker) for group changes to take effect."
    fi

    log "Version check:"
    docker --version
    docker compose version
}

# ---------- Main ----------

main() {
    require_root
    detect_os
    already_installed

    case "$OS_ID" in
        ubuntu)
            install_apt_family "ubuntu"
            ;;
        debian)
            install_apt_family "debian"
            ;;
        centos|rhel|rocky|almalinux)
            install_rpm_family "centos"
            ;;
        fedora)
            install_rpm_family "fedora"
            ;;
        *)
            # Fallback based on ID_LIKE if ID is not directly recognized
            if [[ "$OS_ID_LIKE" == *debian* ]]; then
                warn "Unknown ID='$OS_ID', but looks like Debian family (ID_LIKE=$OS_ID_LIKE)."
                install_apt_family "debian"
            elif [[ "$OS_ID_LIKE" == *rhel* || "$OS_ID_LIKE" == *fedora* ]]; then
                warn "Unknown ID='$OS_ID', but looks like RHEL family (ID_LIKE=$OS_ID_LIKE)."
                install_rpm_family "centos"
            else
                err "Distro '$OS_ID' is not supported by this script."
                err "Supported: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, Fedora."
                exit 1
            fi
            ;;
    esac

    post_install
    log "Done! Docker and Docker Compose have been installed."
}

main "$@"
