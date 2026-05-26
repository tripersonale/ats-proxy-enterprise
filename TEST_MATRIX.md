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
| ATS 10.x | Non validato; non supportato come baseline |
| DNS cache gap del plugin | Limite noto di `TS_HTTP_OS_DNS_HOOK`, documentato |
| Carico oltre 50 concorrenti | Non validato in questa sessione |
