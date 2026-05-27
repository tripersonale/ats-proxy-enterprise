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
| Sintassi v3 tooling | `bash -n scripts/compile-plugin.sh scripts/ats-ctl scripts/ats-mode-test.sh` | OK, 2026-05-27 |
| Consistenza repo post-v3 | `bash scripts/check-repo-consistency.sh` | OK, 2026-05-27 |

## ATS 10.1.2 + Plugin v3.0 Beta

Target: VM137 `ats-lab-26-ats10`, Ubuntu 26.04 LTS, IP `192.168.89.37`.

| Area | Comando/azione | Esito |
|---|---|---|
| Cloud-init VM | VM137 Proxmox da `resolute-server-cloudimg-amd64.qcow2` | OK |
| OS | `lsb_release -a` | Ubuntu 26.04 LTS, codename `resolute` |
| ATS 10 CMake senza PCRE1 | `cmake -S . -B build ...` | FAIL previsto: `Could NOT find PCRE` |
| PCRE1 | PCRE 8.45 compilato in `/usr/local/pcre` | OK |
| ATS 10 CMake con PCRE1 | `-DPCRE_LIBRARY=/usr/local/pcre/lib/libpcre.so -DPCRE_INCLUDE_DIR=/usr/local/pcre/include` | OK |
| ATS 10 build | `cmake --build /tmp/trafficserver-10.1.2/build -j$(nproc)` | OK |
| ATS 10 install | `sudo cmake --install /tmp/trafficserver-10.1.2/build` | OK |
| Config verify | `sudo /opt/trafficserver/bin/traffic_server -C verify_config` | OK |
| Forward proxy L0 | `curl -x http://127.0.0.1:8080 http://example.com` | `200` dopo `reverse_proxy.enabled=0` e `url_remap.remap_required=0` |
| Plugin v3 build | `bash scripts/compile-plugin.sh --ats-src /tmp/trafficserver-10.1.2 --out bin/ats_proxy_filter_v30.so --cxx` | OK, SHA256 `157b97f...` |
| Plugin v3 load | `plugin.config = ats_proxy_filter_v30.so` | OK, log `plugin loaded` |
| `ats-ctl` installed mode | `ATS_PROXY_TEMPLATE_DIR=/home/ubuntu/ats-proxy/config ats-ctl init` | OK |

### Plugin v3 Mode Tests

Command:

```bash
for mode in off deny whitelist auth_all auth_nd; do
  sudo ATS_PROXY_CONFIG_DIR=/etc/ats-proxy \
    ATS_PROXY_TEMPLATE_DIR=/home/ubuntu/ats-proxy/config \
    ATS_CTL=/usr/local/bin/ats-ctl \
    bash scripts/ats-mode-test.sh "$mode" 8080 admin '<password>'
done
```

| MODE | Test | Esito |
|---|---|---|
| `off` | denied host passes | OK `200` |
| `deny` | denied host -> 403 | OK `403` |
| `deny` | other host passes | OK `200` |
| `whitelist` | listed host passes | OK `200` |
| `whitelist` | non-listed host -> 403 | OK `403` |
| `auth_all` | missing auth -> 407 | OK `407` |
| `auth_all` | valid auth passes whitelist | OK `200` |
| `auth_all` | valid auth overrides deny | OK `200` |
| `auth_nd` | deny before auth -> 403 | OK `403` |
| `auth_nd` | whitelist bypasses auth | OK `200` |
| `auth_nd` | other host needs auth | OK `407` |

### Hardening Core v3

Script:

```bash
sudo bash scripts/apply-ats-hardening-v3.sh
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=core bash scripts/ats-hardening-check.sh 8080
```

Risultato VM137:

```text
Passed: 19  Failed: 0  Warnings: 5
```

Warning attesi in stage `core`:

- UFW non ancora attivo.
- Porta proxy non ancora aperta via UFW.
- fail2ban non ancora attivo.
- `fail2ban-client` non ancora installato.
- etckeeper non ancora inizializzato.

Bug corretto durante test: `ats-ctl` ripiegava a gruppo `nogroup` quando non esisteva il gruppo `trafficserver`; su ATS10 v3 il gruppo corretto e `ats`. Dopo fix, `/etc/ats-proxy` resta `root:ats 0750`, i file restano `0640`, e tutti i mode plugin passano anche post-hardening.

### Hardening Full v3 (Network Stage)

```bash
sudo apt-get install -y ufw fail2ban etckeeper
sudo ufw --force enable && sudo ufw default deny incoming && sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp && sudo ufw allow from 192.168.89.0/24 to any port 22 proto tcp
# fail2ban ats-proxy filter: failregex = AUTH FAIL user=.* from=<HOST>
sudo systemctl restart fail2ban
sudo etckeeper init && sudo etckeeper commit
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full bash scripts/ats-hardening-check.sh 8080
```

Risultato VM137:

```text
Passed: 25  Failed: 0  Warnings: 0
```

Tutti i 25 controlli verificati: systemd sandbox 11/11, UFW 2/2, fail2ban 3/3, unattended-upgrades 2/2, etckeeper 1/1, file permissions 4/4, health check 2/2, CVE helper 1/1.

### Plugin v3 Post-Hardening Mode Tests

| MODE | Esito post-hardening core |
|---|---|
| `off` | OK |
| `deny` | OK |
| `whitelist` | OK |
| `auth_all` | OK |
| `auth_nd` | OK |

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
| ATS 10.1.2 PCRE | Richiede ancora PCRE1: `libpcre2-dev` non basta. VM137 validata con PCRE 8.45 in `/usr/local/pcre` |
| ATS 10.1.2 hardening full | Full hardening 25/25 OK: core + network (UFW, fail2ban ats-proxy, etckeeper) su VM137 |
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
