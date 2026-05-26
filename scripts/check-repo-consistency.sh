#!/bin/bash
# Cosa: verifica coerenza minima del repository ATS Proxy Enterprise.
# Uso: bash scripts/check-repo-consistency.sh
# Perché: impedire regressioni documentali/artifact gap prima di release o push.
# Dipendenze: bash, git, grep, sha256sum, awk.
# Rischi: read-only; fallisce con exit non-zero se trova incoerenze.
# Rollback/cleanup: nessuna modifica al filesystem.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_PLUGIN_SO_SHA256="26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674"
EXPECTED_PLUGIN_C_SHA256="ac742e549c3081af44c320117ce0a8a1e8d9b80dbb76327f154e7d0797a7ffea"

err() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
ok() { printf '[OK] %s\n' "$1"; }

cd "$REPO_ROOT"

[ -f VERSION ] || err "VERSION missing"
[ -f CHANGELOG.md ] || err "CHANGELOG.md missing"
[ -f ARTIFACTS.md ] || err "ARTIFACTS.md missing"
[ -f TEST_MATRIX.md ] || err "TEST_MATRIX.md missing"
[ -f README.md ] || err "README.md missing"
[ -f GUIDA_INSTALLAZIONE.md ] || err "GUIDA_INSTALLAZIONE.md missing"
[ -f GUIDA_OPERATIVA.md ] || err "GUIDA_OPERATIVA.md missing"
[ -f src/ats_proxy_filter_v21.c ] || err "src/ats_proxy_filter_v21.c missing"
[ -f bin/ats_proxy_filter_v21.so ] || err "bin/ats_proxy_filter_v21.so missing"
[ -f env/ats-proxy.env.example ] || err "env/ats-proxy.env.example missing"
[ -f scripts/preflight.sh ] || err "scripts/preflight.sh missing"
[ -f scripts/install-ats-proxy.sh ] || err "scripts/install-ats-proxy.sh missing"
[ -f scripts/ats-regression-test.sh ] || err "scripts/ats-regression-test.sh missing"
[ -f scripts/ats-hardening-check.sh ] || err "scripts/ats-hardening-check.sh missing"

actual_so_sha="$(sha256sum bin/ats_proxy_filter_v21.so | awk '{print $1}')"
actual_c_sha="$(sha256sum src/ats_proxy_filter_v21.c | awk '{print $1}')"
[ "$actual_so_sha" = "$EXPECTED_PLUGIN_SO_SHA256" ] || err "Plugin .so SHA256 mismatch: $actual_so_sha"
[ "$actual_c_sha" = "$EXPECTED_PLUGIN_C_SHA256" ] || err "Plugin .c SHA256 mismatch: $actual_c_sha"

grep -q "$EXPECTED_PLUGIN_SO_SHA256" ARTIFACTS.md || err "ARTIFACTS.md does not contain plugin SHA256"
grep -q 'bin/ats_proxy_filter_v21.so' env/ats-proxy.env.example || err "env template does not point to versioned plugin"
grep -q 'Passed: 9  Failed: 0' TEST_MATRIX.md || err "TEST_MATRIX.md does not contain regression result"
grep -q 'Passed: 25  Failed: 0  Warnings: 0' TEST_MATRIX.md || err "TEST_MATRIX.md does not contain hardening result"
grep -q 'ATS 10.x non e validato\|ATS 10.x remains not validated\|ATS 10.x non validato' README.md GUIDA_OPERATIVA.md TEST_MATRIX.md || err "ATS 10.x validation status missing"

version_file="$(tr -d '[:space:]' < VERSION)"
grep -q "Versione ${version_file}" README.md || err "README.md version does not match VERSION (${version_file})"
grep -q "## ${version_file}" CHANGELOG.md || err "CHANGELOG.md does not contain VERSION (${version_file})"

if grep -R "repository .*non contiene ancora.*ats_proxy_filter_v21.*so\|ats_proxy_filter_v21.so.*non sono ancora versionati\|Il sorgente è .*ats_proxy_filter_v21.c" \
  --include='*.md' . >/dev/null; then
  err "Current docs still contain stale plugin/source availability claims"
fi

ok "Required files present"
ok "Plugin .so SHA256 matches manifest"
ok "Plugin .c SHA256 matches manifest"
ok "Current tested docs present"
ok "VERSION/README/CHANGELOG aligned"
ok "Regression and hardening results documented"
ok "No stale plugin availability claims found"
ok "Repository consistency passed"
