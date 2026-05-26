# Test Matrix - ATS Proxy Enterprise

## Regola

Ogni comando pubblicato deve avere uno stato esplicito:
- verificato localmente;
- verificato su VM reale;
- fallisce come previsto;
- da validare su VM reale.

## Test locali eseguiti il 2026-05-25

| Area | Comando | Esito |
|------|---------|-------|
| Sintassi installer | `bash -n scripts/install-ats-proxy.sh` | OK |
| Sintassi preflight | `bash -n scripts/preflight.sh` | OK |
| Sintassi package | `bash -n scripts/package-release.sh` | OK |
| Sintassi wrapper 24.04 | `bash -n scripts/install-24.04.sh` | OK |
| Sintassi wrapper 26.04 | `bash -n scripts/install-26.04.sh` | OK |
| Whitespace diff | `git diff --check` | OK |
| Help installer | `bash scripts/install-ats-proxy.sh --help` | OK |
| Help preflight | `bash scripts/preflight.sh --help` | OK |
| Help package | `bash scripts/package-release.sh --help` | OK |
| Preflight template | `bash scripts/preflight.sh --env env/ats-proxy.env.example` | Fallisce come previsto: `CHANGE_ME` e plugin mancante |
| Installer template | `bash scripts/install-ats-proxy.sh --env env/ats-proxy.env.example --non-interactive` | Fallisce come previsto prima di modifiche sistema |
| Preflight config valida | `bash scripts/preflight.sh --env /tmp/opencode/ats-proxy-valid.env` | OK con plugin dummy |
| Installer validate-only | `bash scripts/install-ats-proxy.sh --env /tmp/opencode/ats-proxy-valid.env --non-interactive --validate-only` | OK, nessuna installazione |
| Wrapper 24.04 validate-only | `bash scripts/install-24.04.sh --env /tmp/opencode/ats-proxy-valid.env --non-interactive --validate-only` | OK su host Ubuntu 24.04 |
| Wrapper 26.04 su host 24.04 | `bash scripts/install-26.04.sh --env /tmp/opencode/ats-proxy-valid.env --non-interactive --validate-only` | Fallisce come previsto: OS errato |
| Package senza plugin | `bash scripts/package-release.sh --output-dir /tmp/opencode/ats-pkg-no-plugin --force` | OK |
| Package con plugin dummy | `bash scripts/package-release.sh --output-dir /tmp/opencode/ats-pkg-with-plugin --include-plugin /tmp/opencode/ats_proxy_filter_v21.so --force` | OK |
| Recupero plugin VM134 | `virt-cat -a /dev/zvol/HDD-10K/vm-134-disk-0 /opt/trafficserver/lib/modules/ats_proxy_filter.so` | OK, estratto read-only |
| Recupero plugin VM130 | `virt-cat -a /dev/zvol/HDD-10K/vm-130-disk-0 /opt/trafficserver/lib/modules/ats_proxy_filter.so` | OK, estratto read-only |
| Confronto plugin VM130/VM134 | `sha256sum` + `cmp` | OK, binari identici |
| Preflight con plugin versionato | `bash scripts/preflight.sh --env /tmp/opencode/ats-proxy-valid-bin.env` | OK |
| Validate-only con plugin versionato | `bash scripts/install-ats-proxy.sh --env /tmp/opencode/ats-proxy-valid-bin.env --non-interactive --validate-only` | OK |
| Consistenza repo | `bash scripts/check-repo-consistency.sh` | OK |
| Package finale | `bash scripts/package-release.sh --output-dir /tmp/opencode/ats-pkg-final --force` | OK, include plugin versionato |
| Package governance files | `tar -tzf ... | grep VERSION/CHANGELOG/ARTIFACTS/TEST_MATRIX/check-repo-consistency` | OK |
| Source ricostruito | `src/ats_proxy_filter_v21.c` scritto da comportamento documentato, 334 righe | OK, brace balance 0, no NULL value_len |
| Source SHA256 | `sha256sum src/ats_proxy_filter_v21.c` | `35c2a1e4c6dec45d52f5e38fd58d640416ba22fcec77cf9087e03cce89f797e4` |

## Test infrastruttura eseguiti il 2026-05-25

| Area | Comando/azione | Esito |
|------|----------------|-------|
| Proxmox VM134 | `qm status 134` via SSH Proxmox | VM running |
| Proxmox VM134 config | `qm config 134` filtrato | `ciuser=ubuntu`, IP `192.168.89.28/24`, agent `1` |
| Guest agent VM134 | `qm agent 134 ping` | Non disponibile |
| SSH VM134 | `ssh -i /tmp/vm-134-key ubuntu@192.168.89.28` | Fallisce: `Permission denied (publickey)` |
| SSH VM130 | `ssh -i /tmp/vm-130-key ubuntu@192.168.89.27` | Fallisce o chiave mancante |

## Da validare su VM reale

| Area | Stato |
|------|-------|
| Installazione completa Ubuntu 24.04 pulita | Da validare |
| Installazione completa Ubuntu 26.04 pulita | Da validare |
| Recupero sorgente C plugin v2.1 | Da validare; non trovato nei filesystem locali/VM ispezionati |
| Compilazione sorgente ricostruito su ATS 9.2.13 | Da validare su VM reale |
| Validazione equivalenza sorgente/binario | Da validare su VM reale |
| Test reason phrase 403 | Da validare dopo recupero plugin |
| Test carico >100 req/s | Da validare |

## Blocco corrente

Il binario plugin `ats_proxy_filter_v21.so` e stato recuperato in sola lettura dai dischi VM130/VM134 tramite Proxmox/libguestfs. I binari sono identici: SHA256 `6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7`, BuildID `f6c18c6d9b27dd58d9e23a8de8685c442d748b19`. Il sorgente C e stato ricostruito il 2026-05-25 e versionato.
