#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_PLUGIN_SO_SHA256="6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7"
EXPECTED_PLUGIN_C_SHA256="35c2a1e4c6dec45d52f5e38fd58d640416ba22fcec77cf9087e03cce89f797e4"

err() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }
ok() { printf '[OK] %s\n' "$1"; }

cd "$REPO_ROOT"

[ -f VERSION ] || err "VERSION missing"
[ -f CHANGELOG.md ] || err "CHANGELOG.md missing"
[ -f ARTIFACTS.md ] || err "ARTIFACTS.md missing"
[ -f TEST_MATRIX.md ] || err "TEST_MATRIX.md missing"
[ -f src/ats_proxy_filter_v21.c ] || err "src/ats_proxy_filter_v21.c missing"
[ -f bin/ats_proxy_filter_v21.so ] || err "bin/ats_proxy_filter_v21.so missing"
[ -f env/ats-proxy.env.example ] || err "env/ats-proxy.env.example missing"
[ -f scripts/preflight.sh ] || err "scripts/preflight.sh missing"
[ -f scripts/install-ats-proxy.sh ] || err "scripts/install-ats-proxy.sh missing"

actual_so_sha="$(sha256sum bin/ats_proxy_filter_v21.so | awk '{print $1}')"
actual_c_sha="$(sha256sum src/ats_proxy_filter_v21.c | awk '{print $1}')"
[ "$actual_so_sha" = "$EXPECTED_PLUGIN_SO_SHA256" ] || err "Plugin .so SHA256 mismatch: $actual_so_sha"
[ "$actual_c_sha" = "$EXPECTED_PLUGIN_C_SHA256" ] || err "Plugin .c SHA256 mismatch: $actual_c_sha"

grep -q "$EXPECTED_PLUGIN_SO_SHA256" ARTIFACTS.md || err "ARTIFACTS.md does not contain plugin SHA256"
grep -q 'bin/ats_proxy_filter_v21.so' env/ats-proxy.env.example || err "env template does not point to versioned plugin"

if grep -R "repository .*non contiene ancora.*ats_proxy_filter_v21.*so\|ats_proxy_filter_v21.so.*non sono ancora versionati\|Il sorgente è .*ats_proxy_filter_v21.c" \
  --include='*.md' . >/dev/null; then
  err "Current docs still contain stale plugin/source availability claims"
fi

ok "Required files present"
ok "Plugin .so SHA256 matches manifest"
ok "Plugin .c SHA256 matches manifest"
ok "No stale plugin availability claims found"
ok "Repository consistency passed"
