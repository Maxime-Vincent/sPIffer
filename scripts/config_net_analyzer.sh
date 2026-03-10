#!/bin/bash
set -euo pipefail

# sPIffer network bridge setup for Raspberry Pi OS Bookworm / NetworkManager
# Usage:
#   config_net_analyzer.sh apply
#   config_net_analyzer.sh stop
#   config_net_analyzer.sh status

SCRIPT_NAME="$(basename "$0")"
CONFIG_FILE="/etc/spiffer/spiffer.env"
DEBUG="${DEBUG:-false}"

# ---------- logging ----------

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    echo "$(timestamp) [INFO] $*"
}

warn() {
    echo "$(timestamp) [WARN] $*" >&2
}

error() {
    echo "$(timestamp) [ERROR] $*" >&2
}

die() {
    error "$*"
    exit 1
}

debug() {
    if [ "$DEBUG" = "true" ]; then
        echo "$(timestamp) [DEBUG] $*"
    fi
}

trap 'error "Command failed at line $LINENO: $BASH_COMMAND"' ERR

# ---------- config ----------

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "Loading configuration from $CONFIG_FILE"
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
    else
        warn "Configuration file not found: $CONFIG_FILE"
        warn "Falling back to default values"
    fi

    BRIDGE_NAME="${BRIDGE_NAME:-br0}"
    MGMT_IF="${MGMT_IF:-eth0}"
    BRIDGE_PORT_A="${BRIDGE_PORT_A:-eth1}"
    BRIDGE_PORT_B="${BRIDGE_PORT_B:-eth2}"
    BRIDGE_CONN="${BRIDGE_CONN:-spiffer-br0}"
    BRIDGE_PORT_A_CONN="${BRIDGE_PORT_A_CONN:-spiffer-port-a}"
    BRIDGE_PORT_B_CONN="${BRIDGE_PORT_B_CONN:-spiffer-port-b}"
    MTU="${MTU:-1500}"
    DISABLE_WIFI="${DISABLE_WIFI:-false}"
    WIFI_IF="${WIFI_IF:-wlan0}"
    PROMISC="${PROMISC:-true}"
    DISABLE_OFFLOADS="${DISABLE_OFFLOADS:-true}"
}

print_config() {
    log "Using configuration:"
    log "  CONFIG_FILE=$CONFIG_FILE"
    log "  BRIDGE_NAME=$BRIDGE_NAME"
    log "  MGMT_IF=$MGMT_IF"
    log "  BRIDGE_PORT_A=$BRIDGE_PORT_A"
    log "  BRIDGE_PORT_B=$BRIDGE_PORT_B"
    log "  BRIDGE_CONN=$BRIDGE_CONN"
    log "  BRIDGE_PORT_A_CONN=$BRIDGE_PORT_A_CONN"
    log "  BRIDGE_PORT_B_CONN=$BRIDGE_PORT_B_CONN"
    log "  MTU=$MTU"
    log "  DISABLE_WIFI=$DISABLE_WIFI"
    log "  WIFI_IF=$WIFI_IF"
    log "  PROMISC=$PROMISC"
    log "  DISABLE_OFFLOADS=$DISABLE_OFFLOADS"
    log "  DEBUG=$DEBUG"
}

# ---------- helpers ----------

require_cmd() {
    local cmd="$1"
    debug "Checking command availability: $cmd"
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

check_interface_exists() {
    local iface="$1"
    debug "Checking interface exists: $iface"
    ip link show "$iface" >/dev/null 2>&1 || die "Interface $iface is not available"
}

print_detected_interfaces() {
    log "Detected network interfaces:"
    ip -br link || true
}

nm_con_exists() {
    local con="$1"
    nmcli -t -f NAME connection show | grep -Fxq "$con"
}

nm_delete_connection_if_exists() {
    local con="$1"
    if nm_con_exists "$con"; then
        log "Deleting existing NetworkManager connection: $con"
        nmcli connection delete "$con" >/dev/null
    else
        debug "NetworkManager connection not found, nothing to delete: $con"
    fi
}

set_link_promisc() {
    local iface="$1"
    local state="$2"

    if ip link show "$iface" >/dev/null 2>&1; then
        log "Setting promiscuous mode '$state' on $iface"
        ip link set dev "$iface" promisc "$state" || warn "Unable to set promisc $state on $iface"
    else
        warn "Interface $iface not found while setting promisc=$state"
    fi
}

set_link_mtu() {
    local iface="$1"
    local mtu="$2"

    if ip link show "$iface" >/dev/null 2>&1; then
        log "Setting MTU $mtu on $iface"
        ip link set dev "$iface" mtu "$mtu" || warn "Unable to set MTU $mtu on $iface"
    else
        warn "Interface $iface not found while setting MTU"
    fi
}

disable_offloads() {
    local iface="$1"

    if ! command -v ethtool >/dev/null 2>&1; then
        warn "ethtool not found, cannot disable offloads on $iface"
        return 0
    fi

    log "Disabling offloading features on $iface"
    ethtool -K "$iface" tso off gso off gro off lro off rx off tx off 2>/dev/null || \
    ethtool -K "$iface" tso off gso off gro off lro off 2>/dev/null || \
    warn "Could not disable all offloads on $iface"
}

enable_ipv4_forwarding() {
    log "Enabling IPv4 forwarding"
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

validate_interfaces() {
    log "Validating configured interfaces"
    check_interface_exists "$MGMT_IF"
    check_interface_exists "$BRIDGE_PORT_A"
    check_interface_exists "$BRIDGE_PORT_B"

    [ "$MGMT_IF" != "$BRIDGE_PORT_A" ] || die "MGMT_IF must be different from BRIDGE_PORT_A"
    [ "$MGMT_IF" != "$BRIDGE_PORT_B" ] || die "MGMT_IF must be different from BRIDGE_PORT_B"
    [ "$BRIDGE_PORT_A" != "$BRIDGE_PORT_B" ] || die "BRIDGE_PORT_A and BRIDGE_PORT_B must be different"

    log "Interface validation successful"
}

cleanup_previous_runtime_state() {
    log "Cleaning previous NetworkManager state"
    nm_delete_connection_if_exists "$BRIDGE_PORT_A_CONN"
    nm_delete_connection_if_exists "$BRIDGE_PORT_B_CONN"
    nm_delete_connection_if_exists "$BRIDGE_CONN"
}

apply_bridge() {
    log "Starting bridge configuration apply"
    print_detected_interfaces
    print_config
    validate_interfaces

    if [ "$DISABLE_WIFI" = "true" ]; then
        if ip link show "$WIFI_IF" >/dev/null 2>&1; then
            log "Disabling Wi-Fi interface: $WIFI_IF"
            nmcli device disconnect "$WIFI_IF" >/dev/null 2>&1 || warn "Could not disconnect Wi-Fi interface via nmcli: $WIFI_IF"
            ip link set "$WIFI_IF" down || warn "Could not bring Wi-Fi interface down: $WIFI_IF"
        else
            warn "Wi-Fi interface $WIFI_IF not found, skipping disable step"
        fi
    else
        debug "Wi-Fi disable skipped because DISABLE_WIFI=false"
    fi

    cleanup_previous_runtime_state

    log "Creating bridge connection: $BRIDGE_CONN (ifname=$BRIDGE_NAME)"
    nmcli connection add \
        type bridge \
        ifname "$BRIDGE_NAME" \
        con-name "$BRIDGE_CONN" \
        autoconnect yes \
        bridge.stp no \
        ipv4.method disabled \
        ipv6.method ignore >/dev/null

    log "Creating bridge slave connection: $BRIDGE_PORT_A_CONN (ifname=$BRIDGE_PORT_A)"
    nmcli connection add \
        type bridge-slave \
        ifname "$BRIDGE_PORT_A" \
        master "$BRIDGE_NAME" \
        con-name "$BRIDGE_PORT_A_CONN" \
        autoconnect yes >/dev/null

    log "Creating bridge slave connection: $BRIDGE_PORT_B_CONN (ifname=$BRIDGE_PORT_B)"
    nmcli connection add \
        type bridge-slave \
        ifname "$BRIDGE_PORT_B" \
        master "$BRIDGE_NAME" \
        con-name "$BRIDGE_PORT_B_CONN" \
        autoconnect yes >/dev/null

    log "Applying MTU configuration: $MTU"
    nmcli connection modify "$BRIDGE_CONN" 802-3-ethernet.mtu "$MTU" || warn "Unable to set MTU on $BRIDGE_CONN"
    nmcli connection modify "$BRIDGE_PORT_A_CONN" 802-3-ethernet.mtu "$MTU" || warn "Unable to set MTU on $BRIDGE_PORT_A_CONN"
    nmcli connection modify "$BRIDGE_PORT_B_CONN" 802-3-ethernet.mtu "$MTU" || warn "Unable to set MTU on $BRIDGE_PORT_B_CONN"

    log "Bringing up bridge connection: $BRIDGE_CONN"
    nmcli connection up "$BRIDGE_CONN" >/dev/null

    log "Bringing up bridge slave connection: $BRIDGE_PORT_A_CONN"
    nmcli connection up "$BRIDGE_PORT_A_CONN" >/dev/null

    log "Bringing up bridge slave connection: $BRIDGE_PORT_B_CONN"
    nmcli connection up "$BRIDGE_PORT_B_CONN" >/dev/null

    set_link_mtu "$BRIDGE_NAME" "$MTU"
    set_link_mtu "$BRIDGE_PORT_A" "$MTU"
    set_link_mtu "$BRIDGE_PORT_B" "$MTU"

    if [ "$PROMISC" = "true" ]; then
        log "Enabling promiscuous mode on bridge and bridge ports"
        set_link_promisc "$BRIDGE_PORT_A" on
        set_link_promisc "$BRIDGE_PORT_B" on
        set_link_promisc "$BRIDGE_NAME" on
    else
        debug "Promiscuous mode skipped because PROMISC=false"
    fi

    if [ "$DISABLE_OFFLOADS" = "true" ]; then
        log "Disabling offloading features on bridge ports"
        disable_offloads "$BRIDGE_PORT_A"
        disable_offloads "$BRIDGE_PORT_B"
    else
        debug "Offload disabling skipped because DISABLE_OFFLOADS=false"
    fi

    enable_ipv4_forwarding

    log "Bridge configuration applied successfully"
    status_bridge
}

stop_bridge() {
    log "Stopping bridge configuration"
    print_detected_interfaces
    print_config

    nm_delete_connection_if_exists "$BRIDGE_PORT_A_CONN"
    nm_delete_connection_if_exists "$BRIDGE_PORT_B_CONN"
    nm_delete_connection_if_exists "$BRIDGE_CONN"

    set_link_promisc "$BRIDGE_PORT_A" off
    set_link_promisc "$BRIDGE_PORT_B" off

    if ip link show "$BRIDGE_PORT_A" >/dev/null 2>&1; then
        log "Bringing interface up: $BRIDGE_PORT_A"
        ip link set "$BRIDGE_PORT_A" up 2>/dev/null || warn "Unable to bring $BRIDGE_PORT_A up"
    fi

    if ip link show "$BRIDGE_PORT_B" >/dev/null 2>&1; then
        log "Bringing interface up: $BRIDGE_PORT_B"
        ip link set "$BRIDGE_PORT_B" up 2>/dev/null || warn "Unable to bring $BRIDGE_PORT_B up"
    fi

    log "Bridge configuration removed"
}

status_bridge() {
    echo "----------------------------------------------------"
    log "NetworkManager connections"
    nmcli -f NAME,UUID,TYPE,DEVICE connection show | grep -E "NAME|$BRIDGE_CONN|$BRIDGE_PORT_A_CONN|$BRIDGE_PORT_B_CONN" || true
    echo "----------------------------------------------------"
    log "Link status"
    ip -br link show "$MGMT_IF" "$BRIDGE_NAME" "$BRIDGE_PORT_A" "$BRIDGE_PORT_B" 2>/dev/null || true
    echo "----------------------------------------------------"
    if command -v bridge >/dev/null 2>&1; then
        log "Bridge membership"
        bridge link show 2>/dev/null | grep -E "$BRIDGE_PORT_A|$BRIDGE_PORT_B" || true
        echo "----------------------------------------------------"
    fi
    log "IPv4 forwarding state"
    sysctl net.ipv4.ip_forward 2>/dev/null || true
    echo "----------------------------------------------------"
}

main() {
    log "Starting $SCRIPT_NAME"
    load_config

    require_cmd ip
    require_cmd nmcli
    require_cmd sysctl

    local action="${1:-apply}"
    log "Requested action: $action"

    case "$action" in
        apply)
            apply_bridge
            ;;
        stop)
            stop_bridge
            ;;
        status)
            status_bridge
            ;;
        *)
            die "Usage: $SCRIPT_NAME {apply|stop|status}"
            ;;
    esac

    log "$SCRIPT_NAME finished successfully"
}

main "$@"