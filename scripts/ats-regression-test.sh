#!/bin/bash
set -euo pipefail

PROXY_PORT="${1:-8080}"
PROXY="http://127.0.0.1:${PROXY_PORT}"
PROXY_USER="${2:-admin}"
PROXY_PASS="${3:-test-pass}"
OK=0
FAIL=0

test_case() {
  local desc="$1" expected="$2" extra_args="${3:-}"
  local code url
  if [[ "$desc" == *"AUTH"* ]] && [[ "$extra_args" != *"--proxy-user"* ]] && [[ "$expected" != "407" ]]; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x "$PROXY" --proxy-user "${PROXY_USER}:${PROXY_PASS}" "$expected" 2>/dev/null || echo "000")
    url="$expected"
  else
    url="${4:-}"
    [ -z "$url" ] && url="$expected"
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x "$PROXY" ${extra_args} "$url" 2>/dev/null || echo "000")
  fi
  if [ "$code" = "$expected" ]; then
    printf '[OK] %-40s %s\n' "$desc" "$code"
    OK=$((OK + 1))
  else
    printf '[FAIL] %-40s got %s expected %s\n' "$desc" "$code" "$expected"
    FAIL=$((FAIL + 1))
  fi
}

test_reason_phrase() {
  local phrase
  phrase=$(curl -s -v --connect-timeout 5 -x "$PROXY" "http://httpbin.org/ip" 2>&1 | grep -oE 'HTTP/1.[01] 403 [A-Za-z ]+' || true)
  if echo "$phrase" | grep -q "Forbidden"; then
    printf '[OK] %-40s Forbidden\n' "403 reason phrase"
    OK=$((OK + 1))
  else
    printf '[WARN] %-40s %s\n' "403 reason phrase" "${phrase:-no phrase found}"
  fi
}

test_proxy_auth_header() {
  local has_header
  has_header=$(curl -s -v --connect-timeout 5 -x "$PROXY" "http://reddit.com" 2>&1 | grep -c "Proxy-Authenticate" || true)
  if [ "$has_header" -gt 0 ]; then
    printf '[OK] %-40s present\n' "407 Proxy-Authenticate header"
    OK=$((OK + 1))
  else
    printf '[FAIL] %-40s missing\n' "407 Proxy-Authenticate header"
    FAIL=$((FAIL + 1))
  fi
}

test_concurrent() {
  local desc="$1" expected="$2" url="$3" count="${4:-50}" extra_args="${5:-}"
  local results pass=0 total=0
  results=$(for i in $(seq 1 "$count"); do
    curl -s -o /dev/null -w '%{http_code} ' --connect-timeout 5 -x "$PROXY" ${extra_args} "$url" &
  done; wait; echo '')
  for code in $results; do
    total=$((total + 1))
    [ "$code" = "$expected" ] && pass=$((pass + 1))
  done
  if [ "$pass" -eq "$count" ]; then
    printf '[OK] %-40s %d/%d\n' "$desc" "$pass" "$count"
    OK=$((OK + 1))
  else
    printf '[FAIL] %-40s %d/%d expected %s\n' "$desc" "$pass" "$count" "$expected"
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================"
echo " ATS Proxy Regression Test"
echo " Port: ${PROXY_PORT} | $(date -Is)"
echo "============================================"
echo ""

systemctl is-active trafficserver --quiet 2>/dev/null && printf '[OK] trafficserver service active\n' || { printf '[FAIL] trafficserver not active\n'; FAIL=$((FAIL+1)); }

test_case "DENY httpbin.org -> 403"         "403"  ""                        "http://httpbin.org/ip"
test_case "WHITELIST google.com -> 301/200"  "301"  ""                        "http://google.com"
test_case "AUTH missing -> 407"             "407"  ""                        "http://reddit.com"
test_case "AUTH valid -> 301/200"           "301"  "--proxy-user ${PROXY_USER}:${PROXY_PASS}" "http://reddit.com"
test_case "AUTH bad credentials -> 407"     "407"  "--proxy-user wrong:wrong" "http://reddit.com"
test_reason_phrase
test_proxy_auth_header

echo ""
echo "--- Concurrent 50 requests ---"
test_concurrent "50x DENY httpbin.org"      "403" "http://httpbin.org/ip" 50
test_concurrent "50x AUTH valid google.com" "301" "http://google.com"     50 "--proxy-user ${PROXY_USER}:${PROXY_PASS}"

echo ""
echo "============================================"
printf "Passed: %d  Failed: %d\n" "$OK" "$FAIL"
echo "============================================"

exit "$FAIL"
