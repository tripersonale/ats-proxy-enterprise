#!/bin/bash
# Cosa fa:
#   Applica il primo livello di hardening ATS Proxy Enterprise v3 su installazione
#   manuale ATS 10.x in /opt/trafficserver.
#
# Come si usa:
#   sudo bash scripts/apply-ats-hardening-v3.sh
#
# Perche esiste:
#   La validazione ATS10 v3 nasce da build manuale; serve renderla governabile da
#   systemd e verificabile senza riusare il monolite ATS9.
#
# Dipendenze:
#   bash, systemd, id/useradd, install, crontab.
#
# Variabili richieste:
#   ATS_PREFIX default /opt/trafficserver; ATS_USER default ats; ATS_GROUP default ats.
#
# Rischi:
#   Riavvia Traffic Server e cambia owner/permessi di config/log/runtime ATS.
#   Non applica firewall/fail2ban: questi restano fase hardening network.
#
# Rollback/cleanup:
#   sudo systemctl disable --now trafficserver; sudo rm /etc/systemd/system/trafficserver.service;
#   sudo systemctl daemon-reload; avviare con /opt/trafficserver/bin/trafficserver start.
#
# TEST:
#   sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=core bash scripts/ats-hardening-check.sh 8080

set -euo pipefail

ATS_PREFIX="${ATS_PREFIX:-/opt/trafficserver}"
ATS_USER="${ATS_USER:-ats}"
ATS_GROUP="${ATS_GROUP:-ats}"
CONFIG_DIR="${ATS_CONFIG_DIR:-/etc/trafficserver}"
STATE_DIR="${ATS_STATE_DIR:-/var/lib/trafficserver}"
LOG_DIR="${ATS_LOG_DIR:-/var/log/trafficserver}"
PLUGIN_CONFIG_DIR="${ATS_PROXY_CONFIG_DIR:-/etc/ats-proxy}"

log() { printf '[STEP] %s\n' "$1"; }
ok() { printf '[OK] %s\n' "$1"; }

[ -x "${ATS_PREFIX}/bin/trafficserver" ] || { printf '[ERROR] Missing %s/bin/trafficserver\n' "$ATS_PREFIX" >&2; exit 1; }
[ -d "$CONFIG_DIR" ] || { printf '[ERROR] Missing config dir: %s\n' "$CONFIG_DIR" >&2; exit 1; }

log "Creating dedicated ATS user/group"
getent group "$ATS_GROUP" >/dev/null 2>&1 || groupadd --system "$ATS_GROUP"
id "$ATS_USER" >/dev/null 2>&1 || useradd --system --gid "$ATS_GROUP" --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$ATS_USER"

log "Stopping existing ATS launcher if running"
"${ATS_PREFIX}/bin/trafficserver" stop >/dev/null 2>&1 || true

log "Setting ownership and permissions"
install -d -o "$ATS_USER" -g "$ATS_GROUP" -m 0750 "$STATE_DIR" "$LOG_DIR"
chown -R "$ATS_USER:$ATS_GROUP" "$STATE_DIR" "$LOG_DIR"
chgrp -R "$ATS_GROUP" "$CONFIG_DIR" "$PLUGIN_CONFIG_DIR" 2>/dev/null || true
chmod 0750 "$PLUGIN_CONFIG_DIR" 2>/dev/null || true
sh -c "chmod 0640 '$CONFIG_DIR'/* '$PLUGIN_CONFIG_DIR'/*" 2>/dev/null || true

log "Installing health check"
cat > /opt/ats_health.sh <<'EOF'
#!/bin/bash
set -euo pipefail
if ! /opt/trafficserver/bin/trafficserver status | grep -q 'traffic_server is running'; then
  /opt/trafficserver/bin/trafficserver restart
fi
EOF
chmod 0750 /opt/ats_health.sh
touch /var/log/ats-health.log
chown root:"$ATS_GROUP" /var/log/ats-health.log
chmod 0640 /var/log/ats-health.log
(crontab -l 2>/dev/null | grep -v '/opt/ats_health.sh' || true; echo '* * * * * /opt/ats_health.sh >> /var/log/ats-health.log 2>&1') | crontab -

log "Installing minimal CVE helper"
install -m 0750 scripts/cve-check.sh /opt/cve-check.sh 2>/dev/null || true

log "Installing systemd unit"
cat > /etc/systemd/system/trafficserver.service <<EOF
[Unit]
Description=Apache Traffic Server v3 hardened
Documentation=https://trafficserver.apache.org/
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
User=${ATS_USER}
Group=${ATS_GROUP}
RuntimeDirectory=trafficserver
ExecStart=${ATS_PREFIX}/bin/trafficserver start
ExecStop=${ATS_PREFIX}/bin/trafficserver stop
ExecReload=${ATS_PREFIX}/bin/trafficserver restart
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
ReadOnlyPaths=${ATS_PREFIX}
ReadWritePaths=${CONFIG_DIR} ${STATE_DIR} ${LOG_DIR} ${PLUGIN_CONFIG_DIR} /var/log/ats-health.log /run/trafficserver
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true
MemoryHigh=2G
MemoryMax=3G
CPUQuota=400%

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable trafficserver >/dev/null
systemctl restart trafficserver
sleep 3
systemctl is-active --quiet trafficserver
ok "trafficserver hardened systemd service active"
