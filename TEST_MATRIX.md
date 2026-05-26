# Test Matrix

Regola: ogni comando pubblicato deve essere testato o marcato come non validato.

## Test Locali Repo

| Area | Comando | Esito |
|------|---------|-------|
| Sintassi installer | `bash -n scripts/install-ats-proxy.sh` | OK, 2026-05-26 |
| Sintassi regression | `bash -n scripts/ats-regression-test.sh` | OK, 2026-05-26 |
| Sintassi hardening check | `bash -n scripts/ats-hardening-check.sh` | OK, 2026-05-26 |
| Consistenza repo | `bash scripts/check-repo-consistency.sh` | OK, 2026-05-26 |
| Package release | `bash scripts/package-release.sh --output-dir /tmp/opencode/ats-final-pkg --force` | OK, 2026-05-26 |

## Installer End-To-End

| Target | Config | Esito |
|--------|--------|-------|
| VM135 Ubuntu 24.04.4 | `/tmp/opencode/ats-installer-test.conf` trasferito come `/tmp/ats-installer-test.conf` | OK, installer completo |
| VM136 Ubuntu 26.04 | `/tmp/opencode/ats-installer-test-26.conf` trasferito come `/tmp/ats-installer-test-26.conf` | OK, installer completo |

Installer coperto:

- caricamento config file;
- `--validate-only`;
- download ATS con SHA512;
- build ATS 9.2.13;
- build PCRE1 su Ubuntu 26.04;
- scrittura config post `make install`;
- deploy plugin in `/opt/trafficserver/libexec/trafficserver/`;
- systemd service;
- UFW/fail2ban/unattended upgrades/etckeeper/sysctl;
- health check cron;
- verifica interna DENY/WHITELIST/AUTH `3/3`.

## Regression Post-Install

| Test | VM135 24.04 | VM136 26.04 |
|------|-------------|-------------|
| `trafficserver` active | OK | OK |
| DENY `httpbin.org` -> 403 | OK | OK |
| 403 reason phrase `Forbidden` | OK | OK |
| WHITELIST `google.com` -> 301 | OK | OK |
| AUTH missing -> 407 | OK | OK |
| `Proxy-Authenticate` header | OK | OK |
| AUTH valid -> 301 | OK | OK |
| AUTH wrong -> 407 | OK | OK |
| 50x DENY concurrent | 50/50 OK | 50/50 OK |
| 50x whitelist with auth args | 50/50 OK | 50/50 OK |

Command:

```bash
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

Observed result on both VMs:

```text
Passed: 9  Failed: 0
```

## Hardening Post-Install

| Area | VM135 24.04 | VM136 26.04 |
|------|-------------|-------------|
| systemd user/group `ats` | OK | OK |
| systemd sandbox settings | OK | OK |
| UFW active and port 8080 allowed | OK | OK |
| fail2ban service active | OK | OK |
| fail2ban `sshd` jail | OK | OK |
| fail2ban `ats-proxy` jail | OK | OK |
| unattended upgrades enabled/active | OK | OK |
| etckeeper initialized | OK | OK |
| config modes `640` | OK | OK |
| `/var/log/ats-health.log` mode `640` | OK | OK |
| health check executable + cron | OK | OK |
| CVE helper installed | OK | OK |

Command:

```bash
sudo bash scripts/ats-hardening-check.sh 8080
```

Observed result on both VMs:

```text
Passed: 25  Failed: 0  Warnings: 0
```

## Validated Limits

| Area | Stato |
|------|-------|
| TLS frontend `ATS_TLS_ENABLED=y` | Non incluso nel test end-to-end del 2026-05-26 |
| ATS 9.2.x minor successiva | Nessuna minor successiva a 9.2.13 pubblicata su `downloads.apache.org` al 2026-05-26 |
| ATS 10.1.2 compile check raw headers | Non drop-in: `gcc` fallisce per richiesta C++17; `g++ -std=c++17` richiede header generati dal build system (`ts/apidefs.h`) |
| DNS cache gap del plugin corrente | Test rapido VM135/VM136 non lo riproduce: auth valida a `reddit.com` poi no-auth resta `407`; 5 richieste consecutive whitelist generano 5 log `WHITELIST` |
| DNS cache gap vecchio plugin recuperato | Test rapido VM135 con SHA `6a1a73...`: auth valida `301`, poi no-auth `407`; non dimostra soluzione diversa dal plugin corrente |
| Carico oltre 50 concorrenti | Non validato in questa sessione |

## Test Mirati Aggiunti Il 2026-05-26

| Test | Target | Esito |
|------|--------|-------|
| DNS cache auth-gated corrente | VM135 | `first_auth=301`, `second_noauth=407`, `third_noauth=407` |
| DNS cache auth-gated corrente | VM136 | `first_auth=301`, `second_noauth=407`, `third_noauth=407` |
| Hook whitelist ripetuto corrente | VM135 | 5 richieste `google.com` -> 5 log `WHITELIST google.com -> pass` |
| Hook whitelist ripetuto corrente | VM136 | 5 richieste `google.com` -> 5 log `WHITELIST google.com -> pass` |
| Admin bypass remoto | VM135, client `192.168.89.55` | `httpbin.org` senza auth -> `200`; `reddit.com` senza auth -> `301`; log `ADMIN bypass` presente |
| Vecchio plugin recuperato | VM135, SHA `6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7` | Nessun vantaggio osservato su DNS cache rispetto al plugin corrente |
| Ripristino plugin corrente | VM135 | SHA ripristinato `26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674` |
