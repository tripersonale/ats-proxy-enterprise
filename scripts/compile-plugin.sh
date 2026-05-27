#!/bin/bash
# Cosa fa:
#   Compila il plugin ATS Proxy Enterprise v3.0 contro una tree sorgente/build di
#   Apache Traffic Server 9.x o 10.x.
#
# Come si usa:
#   bash scripts/compile-plugin.sh --ats-src /tmp/trafficserver-10.1.2 --out bin/ats_proxy_filter_v30.so
#
# Perche esiste:
#   Rende ripetibile la build del plugin, evitando comandi manuali diversi tra
#   ATS 9 e ATS 10.
#
# Dipendenze:
#   gcc/g++ oppure cc/c++, header ATS generati, libcrypto/OpenSSL.
#
# Variabili richieste:
#   Nessuna. Parametri obbligatori: --ats-src e --out.
#
# Rischi:
#   La build ATS 10 richiede header generati da CMake, non solo la tarball
#   estratta. Se mancano, lo script fallisce esplicitamente.
#
# Rollback/cleanup:
#   Eliminare il file .so generato e ripristinare il precedente in plugin.config.
#
# TEST:
#   bash -n scripts/compile-plugin.sh; build su VM ATS 9/10; poi ats-mode-test.sh.

set -euo pipefail

ATS_SRC=""
OUT="bin/ats_proxy_filter_v30.so"
SRC="src/ats_proxy_filter_v30.c"
CXX_MODE="auto"

usage() {
  cat <<'EOF'
Usage: compile-plugin.sh --ats-src PATH [--out FILE] [--c|--cxx]

Examples:
  bash scripts/compile-plugin.sh --ats-src /tmp/trafficserver-9.2.13 --out bin/ats_proxy_filter_v30.so --c
  bash scripts/compile-plugin.sh --ats-src /tmp/trafficserver-10.1.2 --out bin/ats_proxy_filter_v30.so --cxx
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ats-src) ATS_SRC="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --c) CXX_MODE="c"; shift ;;
    --cxx) CXX_MODE="cxx"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$ATS_SRC" ] || { printf '[ERROR] --ats-src is required\n' >&2; exit 2; }
[ -f "$SRC" ] || { printf '[ERROR] Missing plugin source: %s\n' "$SRC" >&2; exit 1; }
[ -d "$ATS_SRC" ] || { printf '[ERROR] ATS source/build path not found: %s\n' "$ATS_SRC" >&2; exit 1; }

INCLUDES=("-I$ATS_SRC" "-I$ATS_SRC/include")
if [ -d "$ATS_SRC/build/include" ]; then
  INCLUDES+=("-I$ATS_SRC/build/include")
fi
if [ -d "$ATS_SRC/include/tscore" ]; then
  INCLUDES+=("-I$ATS_SRC/include/tscore")
fi

mkdir -p "$(dirname "$OUT")"

if [ "$CXX_MODE" = "auto" ]; then
  if [ -f "$ATS_SRC/CMakeLists.txt" ]; then
    CXX_MODE="cxx"
  else
    CXX_MODE="c"
  fi
fi

printf '[STEP] Compiling plugin v3.0 (%s)\n' "$CXX_MODE"
if [ "$CXX_MODE" = "cxx" ]; then
  c++ -std=c++17 -fPIC -shared "${INCLUDES[@]}" -o "$OUT" "$SRC" -lcrypto
else
  cc -fPIC -shared "${INCLUDES[@]}" -o "$OUT" "$SRC" -lcrypto
fi

printf '[OK] Built %s\n' "$OUT"
sha256sum "$OUT"
