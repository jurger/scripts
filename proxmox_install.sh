#!/usr/bin/env bash
#
# Automatic installation of Proxmox VE 9 on Debian 13 (Trixie)
# The primary IP is assigned to the vmbr0 bridge
#
# Stage 1 runs on first launch and then reboots.
# Stage 2 runs AUTOMATICALLY after the reboot via a one-shot systemd service,
# with progress shown on the console (and available in journalctl).
#
# Usage:
#   ./install-pve.sh   # first run -> stage 1 -> reboot -> stage 2 runs by itself
#
set -euo pipefail

### ------------------------- Settings --------------------------------------
# Leave empty to auto-detect the values from the current network.
IFACE=""          # physical interface, e.g. "eno1" (empty = auto-detect)
IPCIDR=""         # IP in CIDR format, e.g. "192.168.1.10/24" (empty = auto-detect)
GATEWAY=""        # gateway, e.g. "192.168.1.1" (empty = auto-detect)
BRIDGE="vmbr0"    # bridge name

STATE_FILE="/var/lib/pve-autoinstall.stage"
SERVICE_NAME="pve-autoinstall.service"
SCRIPT_PATH="$(readlink -f "$0")"

# Packages that must be present before the Proxmox installation can start.
REQUIRED_PKGS=(curl gnupg ca-certificates iproute2 bridge-utils sudo)
### -------------------------------------------------------------------------

log()  { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err()  { echo -e "\e[1;31m[x]\e[0m $*" >&2; }

# --- progress helper -------------------------------------------------------
CURRENT_STAGE=0
STEP=0
TOTAL_STEPS=0
progress() {
    STEP=$((STEP + 1))
    echo -e "\e[1;36m========================================================\e[0m"
    echo -e "\e[1;36m[Stage ${CURRENT_STAGE} - step ${STEP}/${TOTAL_STEPS}]\e[0m $*"
    echo -e "\e[1;36m========================================================\e[0m"
}

require_root() {
    [[ $EUID -eq 0 ]] || { err "Please run the script as root."; exit 1; }
}

ensure_prerequisites() {
    progress "Checking required packages: ${REQUIRED_PKGS[*]}"
    local missing=() pkg
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            log "  $pkg: already installed"
        else
            warn "  $pkg: missing -> will be installed"
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Installing missing packages: ${missing[*]}"
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    else
        log "All required packages are present."
    fi
}

detect_network() {
    progress "Detecting network parameters"
    local def_line
    def_line=$(ip -4 route show default | head -n1)
    [[ -n "$def_line" ]] || { err "No default route found."; exit 1; }

    [[ -n "$IFACE" ]]   || IFACE=$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' <<<"$def_line")
    [[ -n "$GATEWAY" ]] || GATEWAY=$(awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' <<<"$def_line")
    [[ -n "$IPCIDR" ]]  || IPCIDR=$(ip -4 -o addr show dev "$IFACE" scope global | awk '{print $4; exit}')

    if [[ -z "$IFACE" || -z "$IPCIDR" || -z "$GATEWAY" ]]; then
        err "Could not determine the network. Set IFACE/IPCIDR/GATEWAY manually."
        exit 1
    fi
    log "Interface: $IFACE | IP: $IPCIDR | Gateway: $GATEWAY | Bridge: $BRIDGE"
}

fix_hosts() {
    progress "Configuring /etc/hosts"
    local hostname fqdn ipaddr
    hostname=$(hostname -s)
    fqdn=$(hostname -f 2>/dev/null || echo "$hostname")
    ipaddr=${IPCIDR%/*}

    log "hostname -> $ipaddr"
    sed -i '/127\.0\.1\.1/d' /etc/hosts
    if ! grep -qE "^\s*${ipaddr}\s" /etc/hosts; then
        echo "${ipaddr} ${fqdn} ${hostname}" >> /etc/hosts
    fi
    if ! hostname --ip-address >/dev/null 2>&1; then
        warn "hostname --ip-address does not resolve, check /etc/hosts manually."
    fi
}

add_pve_repo() {
    progress "Adding the Proxmox VE repository (no-subscription) and key"
    curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
        -o /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
    chmod 644 /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg

    cat > /etc/apt/sources.list.d/pve-install-repo.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg
EOF

    for f in /etc/apt/sources.list.d/pve-enterprise.sources \
             /etc/apt/sources.list.d/ceph.sources; do
        [[ -f "$f" ]] && sed -i 's/^Enabled:.*/Enabled: false/' "$f" || true
    done

    apt-get update
    log "Upgrading the system (dist-upgrade)"
    DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade
}

install_pve_kernel() {
    progress "Installing the Proxmox VE kernel"
    DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-default-kernel
}

configure_bridge() {
    progress "Configuring the ${BRIDGE} bridge with the primary IP ${IPCIDR}"
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    cp /etc/network/interfaces "/etc/network/interfaces.bak-${ts}"

    cat > /etc/network/interfaces <<EOF
# File generated by install-pve.sh (${ts})
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

# Physical interface (no IP - used as a bridge port)
iface ${IFACE} inet manual

# Primary Proxmox bridge - the primary IP is assigned here
auto ${BRIDGE}
iface ${BRIDGE} inet static
    address ${IPCIDR}
    gateway ${GATEWAY}
    bridge-ports ${IFACE}
    bridge-stp off
    bridge-fd 0
EOF
    log "Backup of the old config: /etc/network/interfaces.bak-${ts}"
}

install_stage2_service() {
    progress "Installing a one-shot systemd service to run stage 2 after reboot"
    cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=Proxmox VE auto-install - stage 2 (after reboot)
After=network-online.target
Wants=network-online.target
ConditionPathExists=${STATE_FILE}

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH}
# Show progress on the console AND keep it in the journal
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=3600

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    log "Stage 2 will start automatically on next boot."
    log "You can follow it live with: journalctl -fu ${SERVICE_NAME}"
}

cleanup_stage2_service() {
    progress "Removing the one-shot stage 2 service"
    systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}"
    systemctl daemon-reload
    rm -f "$STATE_FILE"
}

install_pve_stack() {
    progress "Installing proxmox-ve, postfix, open-iscsi, chrony"
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        proxmox-ve postfix open-iscsi chrony

    log "Removing the Debian kernel and os-prober"
    DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        linux-image-amd64 'linux-image-6.*-amd64' os-prober 2>/dev/null || true
    update-grub
}

stage1() {
    CURRENT_STAGE=1
    STEP=0
    TOTAL_STEPS=7
    require_root
    ensure_prerequisites
    detect_network
    fix_hosts
    add_pve_repo
    install_pve_kernel
    configure_bridge
    install_stage2_service

    echo "stage2" > "$STATE_FILE"
    log "Stage 1 complete. Rebooting into the Proxmox VE kernel..."
    log "Stage 2 will run automatically after the reboot."
    sleep 3
    reboot
}

stage2() {
    CURRENT_STAGE=2
    STEP=0
    TOTAL_STEPS=5
    require_root

    progress "Verifying the running kernel"
    if ! uname -r | grep -qi 'pve'; then
        warn "The current kernel ($(uname -r)) is not a PVE kernel."
        warn "The system may not have booted into the Proxmox kernel."
        warn "Fix the boot order and reboot; stage 2 will run again automatically."
        exit 1
    fi
    log "Booted kernel: $(uname -r)"

    ensure_prerequisites

    progress "Refreshing package lists"
    apt-get update

    install_pve_stack

    cleanup_stage2_service

    local ipaddr=${IPCIDR:-$(ip -4 -o addr show dev "${BRIDGE}" 2>/dev/null | awk '{print $4}')}
    log "Installation complete!"
    echo "-----------------------------------------------------------"
    echo " Proxmox VE web interface:  https://${ipaddr%/*}:8006"
    echo " Login: root (system root password), Realm: Linux PAM"
    echo "-----------------------------------------------------------"
    log "Rebooting once more for a clean state in 5 seconds..."
    sleep 5
    reboot
}

### -------------------------- Entry point -----------------------------------
main() {
    if [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "stage2" ]]; then
        stage2
    else
        stage1
    fi
}
main "$@"