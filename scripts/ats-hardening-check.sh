#!/bin/bash
set -euo pipefail

PROXY_PORT="${1:-8080}"
PROFILE="${ATS_HARDENING_PROFILE:-v2}"
STAGE="${ATS_HARDENING_STAGE:-full}"
OK=0
FAIL=0
WARN=0

ok() { printf '[OK] %s\n' "$1"; OK=$((OK + 1)); }
fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
warn() { printf '[WARN] %s\n' "$1"; WARN=$((WARN + 1)); }

check_cmd() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$desc"
  else
    fail "$desc"
  fi
}

check_file_mode() {
  local file="$1" expected="$2"
  if [ ! -e "$file" ] && [ ! -L "$file" ]; then
    fail "$file missing"
    return
  fi
  local mode
  mode=$(stat -L -c '%a' "$file" 2>/dev/null || echo "000")
  if [ "$mode" = "$expected" ]; then
    ok "$file mode $expected"
  else
    fail "$file mode is $mode expected $expected"
  fi
}

echo "============================================"
echo " ATS Proxy Hardening Check"
echo " Port: ${PROXY_PORT} | $(date -Is)"
echo "============================================"
echo ""

soft_fail() {
  if [ "$STAGE" = "core" ]; then
    warn "$1"
  else
    fail "$1"
  fi
}

check_cmd "trafficserver service active" systemctl is-active --quiet trafficserver

unit=$(systemctl cat trafficserver 2>/dev/null || true)
if [ "$PROFILE" = "v3" ]; then
  expected_user='User=ats'
  expected_group='Group=ats'
  expected_rw='ReadWritePaths=/opt/trafficserver/etc/trafficserver /opt/trafficserver/var/trafficserver /var/log/trafficserver /var/trafficserver'
  records_file='/opt/trafficserver/etc/trafficserver/records.config'
  plugin_file='/opt/trafficserver/etc/trafficserver/plugin.config'
  filter_file='/etc/trafficserver/plugin/filter.conf'
else
  expected_user='User=ats'
  expected_group='Group=ats'
  expected_rw='ReadWritePaths=/etc/trafficserver /opt/trafficserver/var/trafficserver /var/log/trafficserver /var/trafficserver'
  records_file='/etc/trafficserver/records.config'
  plugin_file='/etc/trafficserver/plugin.config'
  filter_file='/etc/trafficserver/ats_proxy_filter.conf'
fi
for setting in \
  "$expected_user" \
  "$expected_group" \
  'ProtectSystem=strict' \
  'ProtectHome=true' \
  'PrivateTmp=true' \
  'PrivateDevices=true' \
  'NoNewPrivileges=true' \
  'ReadOnlyPaths=/opt/trafficserver' \
  "$expected_rw"; do
  if grep -Fq "$setting" <<< "$unit"; then
    ok "systemd $setting"
  else
    fail "systemd missing $setting"
  fi
done

if command -v ufw >/dev/null 2>&1; then
  ufw_status=$(sudo ufw status 2>/dev/null || true)
  grep -q 'Status: active' <<< "$ufw_status" && ok "UFW active" || soft_fail "UFW active"
  grep -q "${PROXY_PORT}/tcp" <<< "$ufw_status" && ok "UFW allows proxy port ${PROXY_PORT}" || soft_fail "UFW allows proxy port ${PROXY_PORT}"
else
  soft_fail "UFW installed"
fi

if systemctl is-active --quiet fail2ban; then ok "fail2ban service active"; else soft_fail "fail2ban service active"; fi
if command -v fail2ban-client >/dev/null 2>&1; then
  sudo fail2ban-client status sshd >/dev/null 2>&1 && ok "fail2ban sshd jail" || warn "fail2ban sshd jail not active"
  sudo fail2ban-client status ats-proxy >/dev/null 2>&1 && ok "fail2ban ats-proxy jail" || warn "fail2ban ats-proxy jail not active"
else
  soft_fail "fail2ban-client installed"
fi

check_cmd "unattended-upgrades service enabled" systemctl is-enabled --quiet unattended-upgrades
check_cmd "unattended-upgrades service active" systemctl is-active --quiet unattended-upgrades

if command -v etckeeper >/dev/null 2>&1 && [ -d /etc/.git ]; then
  ok "etckeeper initialized"
else
  warn "etckeeper not initialized"
fi

check_file_mode "$records_file" 640
check_file_mode "$plugin_file" 640
check_file_mode "$filter_file" 640
check_file_mode /var/log/ats-health.log 640

[ -x /opt/ats_health.sh ] && ok "health check executable" || fail "health check executable"
sudo crontab -l 2>/dev/null | grep -Fq '/opt/ats_health.sh' && ok "health check cron installed" || fail "health check cron installed"

[ -x /opt/cve-check.sh ] && ok "CVE helper installed" || warn "CVE helper not installed"

echo ""
echo "============================================"
printf "Passed: %d  Failed: %d  Warnings: %d\n" "$OK" "$FAIL" "$WARN"
echo "============================================"

exit "$FAIL"
