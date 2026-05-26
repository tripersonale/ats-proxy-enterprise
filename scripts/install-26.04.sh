#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f /etc/os-release ]; then
  echo "[ERROR] /etc/os-release not found" >&2
  exit 1
fi

# shellcheck source=/dev/null
. /etc/os-release

if [ "${VERSION_ID:-}" != "26.04" ] && [ "${UBUNTU_CODENAME:-}" != "resolute" ]; then
  echo "[ERROR] This wrapper is only for Ubuntu 26.04 Resolute. Detected: ${PRETTY_NAME:-unknown}" >&2
  echo "Use scripts/install-ats-proxy.sh directly only if you intentionally accept an unvalidated OS path." >&2
  exit 1
fi

exec bash "$SCRIPT_DIR/install-ats-proxy.sh" "$@"
