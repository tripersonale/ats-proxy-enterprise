#!/bin/bash
set -euo pipefail

# Creates a clean transfer package for VMs that cannot access the private repo.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="$REPO_ROOT/dist"
PACKAGE_NAME="ats-proxy-enterprise"
PLUGIN_PATH=""
FORCE=false

usage() {
  cat << 'EOF'
Usage:
  bash scripts/package-release.sh [options]

Options:
  --output-dir DIR        Directory for the generated tar.gz (default: ./dist)
  --name NAME             Package base name (default: ats-proxy-enterprise)
  --include-plugin FILE   Include ats_proxy_filter_v21.so in package root
  --force                 Overwrite existing package
  -h, --help              Show help

The package excludes .git, local env files, local configs, secrets and logs.
EOF
}

err() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
log() { printf '[OK] %s\n' "$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --name) PACKAGE_NAME="$2"; shift 2 ;;
    --include-plugin) PLUGIN_PATH="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1" ;;
  esac
done

if [ -n "$PLUGIN_PATH" ] && [ ! -f "$PLUGIN_PATH" ]; then
  err "Plugin file not found: $PLUGIN_PATH"
fi

mkdir -p "$OUTPUT_DIR"

VERSION_DATE="$(date +%Y%m%d)"
TARBALL="$OUTPUT_DIR/${PACKAGE_NAME}-${VERSION_DATE}.tar.gz"

if [ -e "$TARBALL" ] && [ "$FORCE" != true ]; then
  err "Package already exists: $TARBALL (use --force to overwrite)"
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PKG_DIR="$WORKDIR/$PACKAGE_NAME"
mkdir -p "$PKG_DIR"

tar -C "$REPO_ROOT" \
  --exclude='.git' \
  --exclude='dist' \
  --exclude='ats-proxy.env' \
  --exclude='ats-proxy.conf' \
  --exclude='*.local' \
  --exclude='*.log' \
  --exclude='secrets' \
  --exclude='tmp' \
  --exclude='*.key' \
  --exclude='*.pem' \
  --exclude='*.csr' \
  --exclude='*.crt' \
  --exclude='./ats_proxy_filter*.so' \
  -cf - . | tar -C "$PKG_DIR" --strip-components=0 -xf -

if [ -n "$PLUGIN_PATH" ]; then
  install -m 755 "$PLUGIN_PATH" "$PKG_DIR/ats_proxy_filter_v21.so"
  log "Included plugin: ats_proxy_filter_v21.so"
elif [ -f "$PKG_DIR/bin/ats_proxy_filter_v21.so" ]; then
  log "Included versioned plugin: bin/ats_proxy_filter_v21.so"
else
  log "Plugin not included; target VM must provide ATS_PLUGIN_PATH"
fi

tar -C "$WORKDIR" -czf "$TARBALL" "$PACKAGE_NAME"
log "Package created: $TARBALL"
