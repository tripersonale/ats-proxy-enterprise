#!/bin/bash
set -euo pipefail

# ATS Proxy Enterprise preflight check.
# Validates local configuration before running install-ats-proxy.sh.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE=""
CONFIG_FILE=""
PLUGIN_PATH=""

log() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; }
err() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

usage() {
  cat << 'EOF'
Usage:
  bash scripts/preflight.sh --env ats-proxy.env
  bash scripts/preflight.sh --config ats-proxy.conf

Checks config values and plugin presence without printing secrets.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --plugin) PLUGIN_PATH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1" ;;
  esac
done

if [ -z "$ENV_FILE" ] && [ -z "$CONFIG_FILE" ] && [ -f "$REPO_ROOT/ats-proxy.env" ]; then
  ENV_FILE="$REPO_ROOT/ats-proxy.env"
fi

load_file() {
  local file="$1"
  [ -f "$file" ] || err "Config file not found: $file"
  # shellcheck source=/dev/null
  source "$file"
}

if [ -n "$ENV_FILE" ]; then
  load_file "$ENV_FILE"
elif [ -n "$CONFIG_FILE" ]; then
  load_file "$CONFIG_FILE"
else
  err "No config file supplied. Copy env/ats-proxy.env.example to ats-proxy.env first."
fi

HOSTNAME_VALUE="${ATS_HOSTNAME:-${HOSTNAME:-}}"
IP_VALUE="${ATS_IP_CIDR:-${IP:-}}"
GATEWAY_VALUE="${ATS_GATEWAY:-${GATEWAY:-}}"
DNS_VALUE="${ATS_DNS:-${DNS:-}}"
ALLOWED_SUBNET_VALUE="${ATS_ALLOWED_SUBNET:-${ALLOWED_SUBNET:-}}"
ADMIN_IPS_VALUE="${ATS_ADMIN_IPS:-${ADMIN_IPS:-}}"
DENY_DOMAINS_VALUE="${ATS_DENY_DOMAINS:-${DENY_DOMAINS:-}}"
WHITELIST_DOMAINS_VALUE="${ATS_WHITELIST_DOMAINS:-${WHITELIST_DOMAINS:-}}"
AUTH_USERS_VALUE="${ATS_AUTH_USERS:-${AUTH_USERS:-}}"
PROXY_PORT_VALUE="${ATS_PROXY_PORT:-${PROXY_PORT:-}}"
APPLY_NETPLAN_VALUE="${ATS_APPLY_NETPLAN:-${APPLY_NETPLAN:-}}"
TLS_ENABLED_VALUE="${ATS_TLS_ENABLED:-${TLS_ENABLED:-}}"
PLUGIN_PATH_VALUE="${ATS_PLUGIN_PATH:-${PLUGIN_PATH:-${PLUGIN_PATH_VALUE:-}}}"

missing=0
for name in HOSTNAME_VALUE IP_VALUE GATEWAY_VALUE DNS_VALUE ALLOWED_SUBNET_VALUE ADMIN_IPS_VALUE DENY_DOMAINS_VALUE WHITELIST_DOMAINS_VALUE AUTH_USERS_VALUE PROXY_PORT_VALUE APPLY_NETPLAN_VALUE TLS_ENABLED_VALUE; do
  if [ -z "${!name:-}" ]; then
    warn "Missing required value: $name"
    missing=1
  fi
done

if [[ "$AUTH_USERS_VALUE" == *CHANGE_ME* ]]; then
  warn "Auth users still contain CHANGE_ME placeholders"
  missing=1
fi

if [[ "$IP_VALUE" != */* ]]; then
  warn "ATS_IP_CIDR/IP must include CIDR suffix, example 192.168.89.100/24"
  missing=1
fi

if [ -z "$PLUGIN_PATH_VALUE" ]; then
  if [ -f "$REPO_ROOT/ats_proxy_filter_v21.so" ]; then
    PLUGIN_PATH_VALUE="$REPO_ROOT/ats_proxy_filter_v21.so"
  elif [ -f "$REPO_ROOT/bin/ats_proxy_filter_v21.so" ]; then
    PLUGIN_PATH_VALUE="$REPO_ROOT/bin/ats_proxy_filter_v21.so"
  fi
fi

if [ -z "$PLUGIN_PATH_VALUE" ] || [ ! -f "$PLUGIN_PATH_VALUE" ]; then
  warn "Plugin binary missing. Set ATS_PLUGIN_PATH or pass --plugin /path/to/ats_proxy_filter_v21.so"
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  err "Preflight failed. Fix the warnings above before installing."
fi

log "Config file loaded"
log "Required values present"
log "Auth placeholders replaced"
log "Plugin binary present"
log "Preflight passed"
