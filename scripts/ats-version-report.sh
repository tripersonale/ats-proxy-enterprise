#!/bin/bash
# Cosa: stampa un report diagnostico rapido su OS, ATS, servizio, plugin, config e porte.
# Uso: sudo bash scripts/ats-version-report.sh
# Perché: avere una fotografia ripetibile dello stato runtime prima/dopo upgrade o incidenti.
# Dipendenze: bash, lsb_release, systemctl, sha256sum, ss, grep, tail.
# Rischi: read-only; non stampa password o valori USER dal file plugin.
# Rollback/cleanup: nessuna modifica al filesystem.
set -euo pipefail

echo "============================================"
echo " ATS Proxy Enterprise Version Report"
echo " $(date -Is)"
echo "============================================"
echo ""

echo "--- OS ---"
uname -r 2>/dev/null || echo "unknown"
lsb_release -ds 2>/dev/null || true

echo ""
echo "--- ATS ---"
if [ -x /opt/trafficserver/bin/traffic_server ]; then
  /opt/trafficserver/bin/traffic_server -version 2>&1 | head -1 || echo "ATS version unknown"
else
  echo "ATS not installed or not in /opt/trafficserver"
fi

echo ""
echo "--- Service ---"
systemctl is-active trafficserver 2>/dev/null || echo "inactive"

echo ""
echo "--- Plugin ---"
if [ -f /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so ]; then
  echo "plugin present: /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so"
  sha256sum /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so 2>/dev/null || true
else
  echo "plugin missing"
fi

echo ""
echo "--- Config ---"
echo "ats_proxy_filter.conf lines: $(wc -l < /etc/trafficserver/ats_proxy_filter.conf 2>/dev/null || echo 0)"
echo "plugin.config: $(cat /etc/trafficserver/plugin.config 2>/dev/null || echo missing)"
echo "records.config port: $(grep -E '^CONFIG.*proxy.config.http.server_ports|^CONFIG.*server_ports' /etc/trafficserver/records.config 2>/dev/null | head -1 || echo missing | sed 's/[^0-9]//g' || true)"

echo ""
echo "--- Ports ---"
ss -tlnp 2>/dev/null | grep -E 'traffic|8080|8443' || echo "no ATS ports found"

echo ""
echo "--- Last log errors ---"
tail -5 /var/lib/trafficserver/log/trafficserver/diags.log 2>/dev/null || echo "diags.log not accessible"
