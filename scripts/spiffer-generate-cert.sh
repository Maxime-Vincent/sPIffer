#!/bin/bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DEBUG="${DEBUG:-false}"

PKG_PATH="/usr/lib/spiffer"
CERT_TEMPLATE_PATH="$PKG_PATH/src/certificate"
OPENSSL_CNF="$CERT_TEMPLATE_PATH/openssl.cnf"

CERT_DIR="/etc/spiffer/certs"
KEY_FILE="$CERT_DIR/server.key"
CRT_FILE="$CERT_DIR/server.crt"

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

# ---------- helpers ----------

require_cmd() {
    local cmd="$1"
    debug "Checking command availability: $cmd"
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

print_config() {
    log "Using configuration:"
    log "  SCRIPT_NAME=$SCRIPT_NAME"
    log "  PKG_PATH=$PKG_PATH"
    log "  CERT_TEMPLATE_PATH=$CERT_TEMPLATE_PATH"
    log "  OPENSSL_CNF=$OPENSSL_CNF"
    log "  CERT_DIR=$CERT_DIR"
    log "  KEY_FILE=$KEY_FILE"
    log "  CRT_FILE=$CRT_FILE"
    log "  FORCE=${FORCE:-0}"
    log "  DEBUG=$DEBUG"
}

ensure_paths() {
    [ -d "$CERT_TEMPLATE_PATH" ] || die "Certificate template directory not found: $CERT_TEMPLATE_PATH"
    [ -f "$OPENSSL_CNF" ] || die "OpenSSL config not found: $OPENSSL_CNF"

    if [ ! -d "$CERT_DIR" ]; then
        log "Creating certificate directory: $CERT_DIR"
        mkdir -p "$CERT_DIR"
    fi
}

certificate_exists() {
    [ -f "$KEY_FILE" ] && [ -f "$CRT_FILE" ]
}

generate_certificate() {
    log "Generating self-signed certificate"
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CRT_FILE" \
        -config "$OPENSSL_CNF"

    log "Applying ownership and permissions"
    chown root:root "$KEY_FILE" "$CRT_FILE"
    chmod 600 "$KEY_FILE"
    chmod 644 "$CRT_FILE"
}

main() {
    log "Starting $SCRIPT_NAME"

    require_cmd openssl
    require_cmd chown
    require_cmd chmod
    require_cmd mkdir

    print_config
    ensure_paths

    if certificate_exists; then
        if [ "${FORCE:-0}" = "1" ]; then
            warn "Existing certificate found, but FORCE=1 so it will be regenerated"
        else
            log "Certificate already exists, skipping generation"
            log "  Existing key: $KEY_FILE"
            log "  Existing certificate: $CRT_FILE"
            exit 0
        fi
    fi

    generate_certificate

    log "Certificate generated successfully"
    log "  Key file: $KEY_FILE"
    log "  Certificate file: $CRT_FILE"

    log "$SCRIPT_NAME finished successfully"
}

main "$@"