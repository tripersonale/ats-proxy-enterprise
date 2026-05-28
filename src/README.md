# Source Directory

Sorgenti plugin ATS Proxy Enterprise.

## v2.1 stabile

Plug-in C v2.1 per ATS 9.2.13.

```text
src/ats_proxy_filter_v21.c
SHA256: 35c2a1e4c6dec45d52f5e38fd58d640416ba22fcec77cf9087e03cce89f797e4
```

Ricostruito il 2026-05-25 da comportamento documentato, `PROJECT_ARCHIVE.md` e struttura reference del plugin `basic_auth.c` di ATS.

Hook: `TS_HTTP_OS_DNS_HOOK`.
Thread-safe: zero malloc nel path caldo.
Funzioni: `load_cfg`, `handle_dns`, `handle_response`, `authorized`, `auth_plugin`, `TSPluginInit`.

Per compilare:

```bash
cd /tmp/trafficserver-9.2.13
gcc -fPIC -shared -I. -I./include -o ats_proxy_filter.so src/ats_proxy_filter_v21.c
```

## v3.0 beta enterprise

```text
src/ats_proxy_filter_v30.c
```

Caratteristiche:

- plugin unico con `MODE off`, `deny`, `whitelist`, `auth_all`, `auth_nd`;
- configurazione separata in `/etc/ats-proxy/`;
- utenti con `salt$sha256(salt+password)`, non password in chiaro;
- supporto IPv4/IPv6 via `inet_ntop`;
- dual-build C/C++17 per ATS 9/10.

Per compilare:

```bash
bash scripts/compile-plugin.sh --ats-src /tmp/trafficserver-10.1.2 --out bin/ats_proxy_filter_v30.so --cxx
```

Stato: sorgente e tooling pronti, runtime ATS 10 da validare su VM pulita.
