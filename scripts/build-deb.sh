#!/bin/bash
# Cosa fa:
#   Compila Apache Traffic Server 9.2.13 + PCRE1 8.45 + plugin v3.0 per
#   Ubuntu 26.04, poi li impacchetta in 4 file .deb (core, plugin, hardening,
#   meta-pacchetto enterprise).
#
# Come si usa:
#   bash scripts/build-deb.sh
#   sudo bash scripts/build-deb.sh --install   # build + installa localmente
#
# Perche esiste:
#   Produce artefatti installabili offline e distribuibili via GitHub Releases.
#   Sostituisce il monolite install-ats-proxy.sh con un modello a pacchetti
#   governabile da apt.
#
# Dipendenze:
#   build-essential, cmake, wget, tar, dpkg-dev, openssl (per GPG opzionale).
#
# Variabili richieste:
#   Nessuna obbligatoria. ATS_BUILD_DIR default /tmp/ats-build.
#   Per firmare GPG: impostare ATS_GPG_KEY (fingerprint o key ID).
#
# Rischi:
#   Richiede ~3 GB di spazio in /tmp e ~5 GB in /opt/trafficserver.
#   La build compila PCRE1 e ATS9 da sorgente (~15-30 min).
#   I .deb sovrascrivono versioni precedenti in pool/.
#
# Rollback/cleanup:
#   rm -rf /tmp/ats-build; rm -f pool/ats-*.deb
#
# TEST:
#   bash -n scripts/build-deb.sh; sudo bash scripts/build-deb.sh --install;
#   sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full bash scripts/ats-hardening-check.sh 8080

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ATS_BUILD_DIR:-/tmp/ats-build}"
PCRE_VERSION="8.45"
ATS_VERSION="9.2.13"
PLUGIN_VERSION="3.0-beta"
DEB_REVISION="1"
INSTALL_PREFIX="/opt/trafficserver"

MK_ARCH="amd64"
ATS_CORE_PKG="ats-core_${ATS_VERSION}-${DEB_REVISION}_${MK_ARCH}"
PLUGIN_PKG="ats-proxy-plugin_${PLUGIN_VERSION}-${DEB_REVISION}_${MK_ARCH}"
HARDEN_PKG="ats-proxy-hardening_${PLUGIN_VERSION}-${DEB_REVISION}_${MK_ARCH}"
META_PKG="ats-proxy-enterprise_${PLUGIN_VERSION}-${DEB_REVISION}_${MK_ARCH}"

INSTALL_MODE=false
[ "${1:-}" = "--install" ] && INSTALL_MODE=true

log()  { printf '[STEP] %s\n' "$1"; }
ok()   { printf '[OK]   %s\n' "$1"; }
fail() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }
require cmake
require wget
require tar
require gcc
require g++

# ----- check disk -----
BUILD_PARENT="$(dirname "$BUILD_DIR")"
sudo mkdir -p "$BUILD_DIR"
AVAIL=$(df -BG --output=avail "$BUILD_PARENT" 2>/dev/null | tail -1 | tr -d ' G' || echo 0)
if [ "$AVAIL" -lt 8 ]; then
  fail "Need at least 8 GB free in ${BUILD_PARENT} (have ${AVAIL} GB)"
fi

cd "$REPO_DIR"
mkdir -p pool

# ----- build PCRE1 -----
log "Building PCRE ${PCRE_VERSION}"
mkdir -p "$BUILD_DIR"
if [ ! -f "${BUILD_DIR}/pcre-${PCRE_VERSION}/.done" ]; then
  cd "$BUILD_DIR"
  if [ ! -f "pcre-${PCRE_VERSION}.tar.bz2" ]; then
    wget -q "https://sourceforge.net/projects/pcre/files/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.bz2/download" \
      -O "pcre-${PCRE_VERSION}.tar.bz2"
  fi
  rm -rf "pcre-${PCRE_VERSION}"
  tar -xjf "pcre-${PCRE_VERSION}.tar.bz2"
  cd "pcre-${PCRE_VERSION}"
  ./configure --prefix=/usr/local/pcre --enable-utf --enable-unicode-properties
  make -j"$(nproc)"
  sudo make install
  sudo ldconfig
  touch .done
  ok "PCRE ${PCRE_VERSION} installed"
else
  ok "PCRE ${PCRE_VERSION} already built"
fi

# ----- build ATS -----
log "Building ATS ${ATS_VERSION}"
if [ ! -f "${BUILD_DIR}/trafficserver-${ATS_VERSION}/.done" ]; then
  cd "$BUILD_DIR"
  if [ ! -f "trafficserver-${ATS_VERSION}.tar.bz2" ]; then
    wget -q "https://downloads.apache.org/trafficserver/trafficserver-${ATS_VERSION}.tar.bz2"
  fi
  rm -rf "trafficserver-${ATS_VERSION}"
  tar -xjf "trafficserver-${ATS_VERSION}.tar.bz2"
  cd "trafficserver-${ATS_VERSION}"
  # ATS 9.2.13 requires autotools on Ubuntu 26.04
  if [ "${ATS_VERSION}" = "9.2.13" ]; then
    autoreconf -fi
    ./configure --prefix="${INSTALL_PREFIX}" --sysconfdir="${INSTALL_PREFIX}/etc/trafficserver" --localstatedir=/var --runstatedir=/run/trafficserver --with-user=ats --with-group=ats --with-pcre=/usr/local/pcre --disable-tests --disable-examples --disable-maintainer-mode
    make -j"$(nproc)"
  else
    cmake -S . -B build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
      -DPCRE_LIBRARY=/usr/local/pcre/lib/libpcre.so \
      -DPCRE_INCLUDE_DIR=/usr/local/pcre/include
    cmake --build build -j"$(nproc)"
  fi
  if [ "${ATS_VERSION}" = "9.2.13" ]; then
    make install
  else
    cmake --install build
  fi
  touch .done
  ok "ATS ${ATS_VERSION} built and installed"
else
  ok "ATS ${ATS_VERSION} already built"
fi

# ----- build plugin v3 -----
log "Building plugin v3.0 against ATS ${ATS_VERSION}"
cd "$REPO_DIR"
ATS_SRC="${BUILD_DIR}/trafficserver-${ATS_VERSION}"
bash "${SCRIPT_DIR}/compile-plugin.sh" \
  --ats-src "$ATS_SRC" \
  --out bin/ats_proxy_filter_v30.so --c
ok "Plugin v3.0 built"

# ----- configure forward proxy -----
log "Configuring forward proxy in records.config"
CONF="${INSTALL_PREFIX}/etc/trafficserver/records.config"
if [ -f "$CONF" ]; then
  sudo sed -i 's/CONFIG proxy.config.reverse_proxy.enabled INT 1/CONFIG proxy.config.reverse_proxy.enabled INT 0/' "$CONF"
  sudo sed -i 's/CONFIG proxy.config.url_remap.remap_required INT 1/CONFIG proxy.config.url_remap.remap_required INT 0/' "$CONF"
  ok "records.config updated for forward proxy"
else
  fail "records.config not found at $CONF"
fi

# ----- systemd unit -----
log "Creating systemd unit"
sudo tee "${INSTALL_PREFIX}/etc/trafficserver/systemd/trafficserver.service" >/dev/null << SYSTEMDEOF
[Unit]
Description=Apache Traffic Server v3 hardened
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
User=ats
Group=ats
RuntimeDirectory=trafficserver
ExecStart=${INSTALL_PREFIX}/bin/trafficserver start
ExecStop=${INSTALL_PREFIX}/bin/trafficserver stop
ExecReload=${INSTALL_PREFIX}/bin/trafficserver restart
KillMode=control-group
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
LimitNPROC=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=trafficserver
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=${INSTALL_PREFIX}
ReadWritePaths=${INSTALL_PREFIX}/etc/trafficserver ${INSTALL_PREFIX}/var/trafficserver /var/log/trafficserver /var/trafficserver /etc/ats-proxy /var/log/ats-health.log /run/trafficserver
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true
MemoryHigh=2G
MemoryMax=3G
CPUQuota=400%

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

# ----- package ats-core -----
log "Packaging ${ATS_CORE_PKG}.deb"
rm -rf "${BUILD_DIR}/deb"
mkdir -p "${BUILD_DIR}/deb/${ATS_CORE_PKG}/DEBIAN"
mkdir -p "${BUILD_DIR}/deb/${ATS_CORE_PKG}${INSTALL_PREFIX}"
mkdir -p "${BUILD_DIR}/deb/${ATS_CORE_PKG}/etc/systemd/system"
mkdir -p "${BUILD_DIR}/deb/${ATS_CORE_PKG}/usr/local/pcre/lib"
mkdir -p "${BUILD_DIR}/deb/${ATS_CORE_PKG}/usr/local/pcre/include"

# control + scripts
cp "${REPO_DIR}/debian/ats-core/control" "${BUILD_DIR}/deb/${ATS_CORE_PKG}/DEBIAN/"
cp "${REPO_DIR}/debian/ats-core/postinst" "${BUILD_DIR}/deb/${ATS_CORE_PKG}/DEBIAN/"
chmod 0755 "${BUILD_DIR}/deb/${ATS_CORE_PKG}/DEBIAN/postinst"

# ATS installed tree
sudo cp -a "${INSTALL_PREFIX}"/* "${BUILD_DIR}/deb/${ATS_CORE_PKG}${INSTALL_PREFIX}/"

# systemd unit
sudo cp "${INSTALL_PREFIX}/etc/trafficserver/systemd/trafficserver.service" \
  "${BUILD_DIR}/deb/${ATS_CORE_PKG}/etc/systemd/system/trafficserver.service"

# PCRE1 libraries
cp -a /usr/local/pcre/lib/libpcre.so* "${BUILD_DIR}/deb/${ATS_CORE_PKG}/usr/local/pcre/lib/"
cp -a /usr/local/pcre/lib/libpcreposix.so* "${BUILD_DIR}/deb/${ATS_CORE_PKG}/usr/local/pcre/lib/" 2>/dev/null || true
cp -a /usr/local/pcre/include/pcre.h "${BUILD_DIR}/deb/${ATS_CORE_PKG}/usr/local/pcre/include/"

# build .deb
dpkg-deb --build "${BUILD_DIR}/deb/${ATS_CORE_PKG}" "pool/${ATS_CORE_PKG}.deb"
ok "${ATS_CORE_PKG}.deb created"

# ----- package ats-proxy-plugin -----
log "Packaging ${PLUGIN_PKG}.deb"
rm -rf "${BUILD_DIR}/deb/${PLUGIN_PKG}"
mkdir -p "${BUILD_DIR}/deb/${PLUGIN_PKG}/DEBIAN"
mkdir -p "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/share/ats-proxy/config"
mkdir -p "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/local/bin"
mkdir -p "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/share/man/man1"
mkdir -p "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/share/man/man7"

cp "${REPO_DIR}/debian/ats-proxy-plugin/control" "${BUILD_DIR}/deb/${PLUGIN_PKG}/DEBIAN/"
cp "${REPO_DIR}/debian/ats-proxy-plugin/postinst" "${BUILD_DIR}/deb/${PLUGIN_PKG}/DEBIAN/"
chmod 0755 "${BUILD_DIR}/deb/${PLUGIN_PKG}/DEBIAN/postinst"

# plugin .so
cp "${REPO_DIR}/bin/ats_proxy_filter_v30.so" \
  "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/share/ats-proxy/ats_proxy_filter_v30.so"

# config templates
for f in filter.conf deny.list whitelist.list admin.list auth.conf; do
  cp "${REPO_DIR}/config/${f}.example" "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/share/ats-proxy/config/${f}.example"
done

# ats-ctl
cp "${REPO_DIR}/scripts/ats-ctl" "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/local/bin/ats-ctl"
chmod 0755 "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/local/bin/ats-ctl"

# man pages
cp "${REPO_DIR}/man/ats-ctl.1" "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/share/man/man1/"
cp "${REPO_DIR}/man/ats-proxy-filter.7" "${BUILD_DIR}/deb/${PLUGIN_PKG}/usr/share/man/man7/"

dpkg-deb --build "${BUILD_DIR}/deb/${PLUGIN_PKG}" "pool/${PLUGIN_PKG}.deb"
ok "${PLUGIN_PKG}.deb created"

# ----- package ats-proxy-hardening -----
log "Packaging ${HARDEN_PKG}.deb"
rm -rf "${BUILD_DIR}/deb/${HARDEN_PKG}"
mkdir -p "${BUILD_DIR}/deb/${HARDEN_PKG}/DEBIAN"

cp "${REPO_DIR}/debian/ats-proxy-hardening/control" "${BUILD_DIR}/deb/${HARDEN_PKG}/DEBIAN/"
cp "${REPO_DIR}/debian/ats-proxy-hardening/postinst" "${BUILD_DIR}/deb/${HARDEN_PKG}/DEBIAN/"
chmod 0755 "${BUILD_DIR}/deb/${HARDEN_PKG}/DEBIAN/postinst"

dpkg-deb --build "${BUILD_DIR}/deb/${HARDEN_PKG}" "pool/${HARDEN_PKG}.deb"
ok "${HARDEN_PKG}.deb created"

# ----- package ats-proxy-enterprise (meta) -----
log "Packaging ${META_PKG}.deb (meta)"
rm -rf "${BUILD_DIR}/deb/${META_PKG}"
mkdir -p "${BUILD_DIR}/deb/${META_PKG}/DEBIAN"

cp "${REPO_DIR}/debian/ats-proxy-enterprise/control" "${BUILD_DIR}/deb/${META_PKG}/DEBIAN/"

dpkg-deb --build "${BUILD_DIR}/deb/${META_PKG}" "pool/${META_PKG}.deb"
ok "${META_PKG}.deb created"

# ----- manifest -----
log "Writing pool/MANIFEST.txt"
cat > pool/MANIFEST.txt << MANIFEST
# ATS Proxy Enterprise v3.0 — Pool Manifest
# Generated: $(date -Is)
# Target OS: Ubuntu 26.04 LTS (amd64)

${ATS_CORE_PKG}.deb       ATS 9.2.13 + PCRE1 8.45, compiled for Ubuntu 26.04
${PLUGIN_PKG}.deb         Plugin v3.0 with 5 modes, salted SHA-256 auth, ats-ctl
${HARDEN_PKG}.deb         Hardening: systemd sandbox, UFW, fail2ban, etckeeper, health check
${META_PKG}.deb           Meta-package: installs all three above

Checksums:
MANIFEST
cd pool
for deb in ats-core_*.deb ats-proxy-plugin_*.deb ats-proxy-hardening_*.deb ats-proxy-enterprise_*.deb; do
  [ -f "$deb" ] && sha256sum "$deb" >> MANIFEST.txt
done
ok "MANIFEST.txt written"

# ----- optional GPG sign -----
if [ -n "${ATS_GPG_KEY:-}" ]; then
  log "Signing packages with GPG key ${ATS_GPG_KEY}"
  for deb in pool/ats-*.deb; do
    gpg --detach-sign --armor --local-user "$ATS_GPG_KEY" "$deb"
    ok "Signed $deb"
  done
else
  log "No ATS_GPG_KEY set — skipping GPG signatures"
fi

# ----- optional local install -----
if $INSTALL_MODE; then
  log "Installing packages locally"
  sudo apt-get update -qq
  sudo apt-get install -y -qq ./pool/ats-core_*.deb
  sudo apt-get install -y -qq ./pool/ats-proxy-plugin_*.deb
  sudo apt-get install -y -qq ./pool/ats-proxy-hardening_*.deb
  ok "All packages installed locally"
fi

echo ""
echo "============================================"
echo " Build complete"
echo " Pool: ${REPO_DIR}/pool/"
ls -la pool/ats-*.deb
echo "============================================"
