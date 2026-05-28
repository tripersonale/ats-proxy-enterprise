#!/bin/bash
# Cosa fa:
#   Installa ATS Proxy Enterprise v3.0 in modalita online (scarica .deb da
#   GitHub Releases) o offline (usa pool/ locale). Rileva automaticamente
#   lo scenario e procede all'installazione completa.
#
# Come si usa:
#   ONLINE:  curl -sSL https://raw.githubusercontent.com/tripersonale/ats-proxy-enterprise/main/INSTALL.sh | sudo bash
#   OFFLINE: sudo bash INSTALL.sh          (dalla directory della repo o ZIP)
#
# Perche esiste:
#   Un unico punto d'ingresso per tutti gli scenari di installazione.
#   Nessuna dipendenza da git, token, o connessione internet (se i .deb
#   sono presenti localmente in pool/).
#
# Dipendenze:
#   bash, apt, dpkg, curl (solo online). Sistema Ubuntu 26.04 LTS amd64.
#
# Rischi:
#   Installa pacchetti .deb con privilegi root. Richiede spazio in /opt.
#   Modifica la configurazione di sistema (systemd, UFW, crontab).
#
# Rollback:
#   sudo apt remove ats-proxy-enterprise ats-proxy-hardening ats-proxy-plugin ats-core
#
# TEST:
#   bash -n INSTALL.sh; testato offline su VM137 pulita il 2026-05-28.

set -euo pipefail

RELEASE_TAG="v3.0-beta"
REPO_URL="https://github.com/tripersonale/ats-proxy-enterprise"
RELEASE_URL="${REPO_URL}/releases/download/${RELEASE_TAG}"

CPUS="$(nproc)"
[ "$CPUS" -gt 0 ] || CPUS=4

# Colori per output
BOLD='\033[1m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m' # No Color

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
info() { printf "${BOLD}[INFO]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; exit 1; }

# ---- prerequisiti ----
[ "$(id -u)" -eq 0 ] || err "This script must be run as root (sudo)."

PLATFORM="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
[ "$PLATFORM" = "amd64" ] || err "Only amd64 is supported (detected: ${PLATFORM})"

REQUIRED_SPACE_MB=700
AVAIL=$(df -BM --output=avail /opt 2>/dev/null | tail -1 | tr -d ' M' || echo 0)
if [ "$AVAIL" -lt "$REQUIRED_SPACE_MB" ]; then
  err "Need at least ${REQUIRED_SPACE_MB} MB free in /opt (have ${AVAIL} MB)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POOL_DIR="${SCRIPT_DIR}/pool"

# ---- helper: install .deb ----
deb_candidates() {
  ls "${POOL_DIR}"/ats-core_*.deb 2>/dev/null || true
  ls "${POOL_DIR}"/ats-proxy-plugin_*.deb 2>/dev/null || true
  ls "${POOL_DIR}"/ats-proxy-hardening_*.deb 2>/dev/null || true
  ls "${POOL_DIR}"/ats-proxy-enterprise_*.deb 2>/dev/null || true
}

has_local_debs() {
  local c
  c=$(deb_candidates | wc -l)
  [ "$c" -ge 3 ]
}

# ---- step 1: resolve debs ----
if has_local_debs; then
  info "Offline mode: using .deb files from ${POOL_DIR}"
  DEB_MODE=offline
else
  info "Online mode: downloading .deb from GitHub Releases (${RELEASE_TAG})"
  require_cmd curl
  mkdir -p "${POOL_DIR}"
  for pkg in ats-core ats-proxy-plugin ats-proxy-hardening ats-proxy-enterprise; do
    if [ "$pkg" = "ats-proxy-enterprise" ]; then
      info "Downloading ${pkg}..."
      curl -sSL -o "${POOL_DIR}/${pkg}_3.0-beta-1_amd64.deb" \
        "${RELEASE_URL}/${pkg}_3.0-beta-1_amd64.deb" || \
        warn "Could not download ${pkg} (meta-package; continuing)"
    else
      info "Downloading ${pkg}..."
      curl -sSL -o "${POOL_DIR}/${pkg}_9.2.13-1_amd64.deb" \
        "${RELEASE_URL}/${pkg}_9.2.13-1_amd64.deb" || \
        err "Failed to download ${pkg}.debis the server reachable? URL: ${RELEASE_URL}"
    fi
  done
  DEB_MODE=online
fi

# ---- step 2: install ----
info "Installing packages..."

# Install dependencies from apt first (if online)
if [ "$DEB_MODE" = "online" ]; then
  apt-get update -qq 2>/dev/null || warn "apt update failed (offline? continuing)"
fi

for deb in $(deb_candidates | sort); do
  info "Installing $deb"
  apt-get install -y -qq "$deb" 2>/dev/null || \
    dpkg -i "$deb" || \
    err "Failed to install $deb. Try: dpkg -i $deb"
done

# ---- step 3: check installation ----
info "Verifying installation..."
if [ -x /opt/trafficserver/bin/traffic_server ]; then
  ok "ATS binary present"
else
  err "ATS binary not found at /opt/trafficserver/bin/traffic_server"
fi

if [ -x /usr/local/bin/ats-ctl ]; then
  ok "ats-ctl installed"
else
  warn "ats-ctl not found (plugin package may not be installed yet)"
fi

# ---- step 4: verify service ----
if systemctl is-active --quiet trafficserver 2>/dev/null; then
  ok "trafficserver service is active"
else
  warn "trafficserver service not active. Trying to start..."
  systemctl start trafficserver 2>/dev/null || {
    warn "Could not start via systemd. Trying direct start..."
    /opt/trafficserver/bin/trafficserver start 2>/dev/null || true
  }
  sleep 3
fi

# ---- step 5: quick smoke test ----
info "Smoke test: proxy on port 8080..."
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
  ok "Proxy responding (HTTP ${HTTP_CODE})"
else
  warn "Proxy responded with HTTP ${HTTP_CODE} (expected 200/301). Check logs:"
  warn "  sudo tail -20 /var/log/trafficserver/diags.log"
fi

# ---- step 6: hardening check ----
if [ -f "${SCRIPT_DIR}/scripts/ats-hardening-check.sh" ]; then
  info "Running hardening check..."
  ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
    bash "${SCRIPT_DIR}/scripts/ats-hardening-check.sh" 8080 2>/dev/null || \
    warn "Hardening check had warnings (this is normal for new installations)"
fi

echo ""
echo "============================================"
printf "${GREEN}${BOLD}"
echo " ATS Proxy Enterprise v3.0 installed!"
printf "${NC}"
echo ""
echo " Quick start:"
echo "   ats-ctl status"
echo "   sudo ats-ctl mode auth_nd"
echo "   sudo ats-ctl deny add bad-site.com"
echo "   sudo ats-ctl user add operator"
echo "   sudo ats-ctl reload"
echo ""
echo " Guides:"
echo "   less GUIDE/GUIDA_USO_QUOTIDIANO.md"
echo "   man ats-ctl"
echo "   man ats-proxy-filter"
echo ""
echo " Verify:"
echo "   ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full"
echo "     bash scripts/ats-hardening-check.sh 8080"
echo "============================================"
