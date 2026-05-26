# Source Directory

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
