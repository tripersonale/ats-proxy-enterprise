#!/bin/bash
# Cosa fa:
#   Verifica il comportamento atteso dei MODE del plugin ATS Proxy Enterprise v3.0.
#
# Come si usa:
#   sudo ATS_PROXY_CONFIG_DIR=/etc/ats-proxy bash scripts/ats-mode-test.sh auth_nd 8080 admin password
#
# Perche esiste:
#   Ogni modo del plugin deve essere testabile da solo prima di comporlo con ATS,
#   auth e hardening.
#
# Dipendenze:
#   bash, curl, scripts/ats-ctl, systemctl.
#
# Variabili richieste:
#   ATS_PROXY_CONFIG_DIR opzionale, default /etc/ats-proxy.
#
# Rischi:
#   Modifica temporaneamente MODE e policy deny/whitelist. Usare su VM lab.
#
# Rollback/cleanup:
#   Ripristinare MODE precedente con ats-ctl mode <mode>.
#
# TEST:
#   bash -n scripts/ats-mode-test.sh; eseguire su VM lab dopo install plugin v3.0.

set -euo pipefail

MODE="${1:-auth_nd}"
PORT="${2:-8080}"
USER="${3:-admin}"
PASS="${4:-test-pass}"
PROXY="http://127.0.0.1:${PORT}"
CTL="${ATS_CTL:-scripts/ats-ctl}"
OK=0
FAIL=0

case "$MODE" in off|deny|whitelist|auth_all|auth_nd) ;; *) printf '[ERROR] Invalid mode: %s\n' "$MODE" >&2; exit 2 ;; esac

check_code() {
  local desc="$1" expected="$2" url="$3" extra="${4:-}" code
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x "$PROXY" $extra "$url" 2>/dev/null || true)
  [ -n "$code" ] || code="000"
  if [ "$code" = "$expected" ]; then
    printf '[OK] %-42s %s\n' "$desc" "$code"
    OK=$((OK + 1))
  else
    printf '[FAIL] %-42s got %s expected %s\n' "$desc" "$code" "$expected"
    FAIL=$((FAIL + 1))
  fi
}

prepare_policy() {
  "$CTL" init >/dev/null
  "$CTL" mode "$MODE" >/dev/null
  "$CTL" deny add httpbin.org >/dev/null
  "$CTL" whitelist add example.com >/dev/null
  "$CTL" user add "$USER" "$PASS" >/dev/null
  "$CTL" reload >/dev/null
}

printf '[STEP] Testing plugin MODE=%s on %s\n' "$MODE" "$PROXY"
prepare_policy

case "$MODE" in
  off)
    check_code "OFF: denied host passes" "200" "http://httpbin.org/status/200"
    ;;
  deny)
    check_code "DENY: denied host -> 403" "403" "http://httpbin.org/status/200"
    check_code "DENY: other host passes" "200" "http://example.com"
    ;;
  whitelist)
    check_code "WHITELIST: listed host passes" "200" "http://example.com"
    check_code "WHITELIST: non-listed host -> 403" "403" "http://iana.org"
    ;;
  auth_all)
    check_code "AUTH_ALL: missing auth -> 407" "407" "http://example.com"
    check_code "AUTH_ALL: valid auth passes whitelist" "200" "http://example.com" "--proxy-user ${USER}:${PASS}"
    check_code "AUTH_ALL: valid auth overrides deny" "200" "http://httpbin.org/status/200" "--proxy-user ${USER}:${PASS}"
    ;;
  auth_nd)
    check_code "AUTH_ND: deny before auth -> 403" "403" "http://httpbin.org/status/200" "--proxy-user ${USER}:${PASS}"
    check_code "AUTH_ND: whitelist bypasses auth" "200" "http://example.com"
    check_code "AUTH_ND: other host needs auth" "407" "http://iana.org"
    ;;
esac

printf '[STEP] Passed=%d Failed=%d\n' "$OK" "$FAIL"
exit "$FAIL"
