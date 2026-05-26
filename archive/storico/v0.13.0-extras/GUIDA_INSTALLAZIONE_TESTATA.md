# Guida Installazione Testata

Questa e la guida operativa corrente. Sostituisce le vecchie guide installazione archiviate in `archive/storico/`.

## Baseline Validata

| Componente | Versione/Stato |
|------------|----------------|
| ATS | 9.2.13 compilato da sorgente |
| Ubuntu 24.04 | VM135, test end-to-end OK il 2026-05-26 |
| Ubuntu 26.04 | VM136, test end-to-end OK il 2026-05-26 |
| Plugin | `bin/ats_proxy_filter_v21.so` |
| Porta proxy | 8080 |

## Preparazione Config

```bash
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env
```

Variabili richieste:

- `ATS_HOSTNAME`
- `ATS_IP_CIDR`
- `ATS_GATEWAY`
- `ATS_DNS`
- `ATS_ALLOWED_SUBNET`
- `ATS_ADMIN_IPS`
- `ATS_DENY_DOMAINS`
- `ATS_WHITELIST_DOMAINS`
- `ATS_AUTH_USERS`
- `ATS_PROXY_PORT`
- `ATS_APPLY_NETPLAN`
- `ATS_TLS_ENABLED`
- `ATS_PLUGIN_PATH`

Se si usa lo script senza `--non-interactive`, eventuali valori mancanti o placeholder vengono richiesti a prompt. Con `--non-interactive`, lo script fallisce prima di installare.

## Installazione Da Repo

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env

bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
```

## Installazione Da Pacchetto Trasferibile

Sul PC con accesso alla repo:

```bash
bash scripts/package-release.sh --output-dir dist --force
```

Sulla VM:

```bash
tar -xzf ats-proxy-enterprise-YYYYMMDD.tar.gz
cd ats-proxy-enterprise
sudo bash scripts/install-ats-proxy.sh --env /percorso/ats-proxy.env --non-interactive
```

## Verifica Obbligatoria

```bash
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

Esito validato su VM135 e VM136:

```text
Regression: Passed 9 Failed 0
Hardening: Passed 25 Failed 0 Warnings 0
```

## Cosa Fa L'Installer

- Installa dipendenze OS.
- Su Ubuntu 26.04 compila PCRE1 8.45 da sorgente per compatibilita ATS 9.2.13.
- Scarica ATS 9.2.13 con SHA512 ufficiale verificato.
- Compila e installa ATS in `/opt/trafficserver`.
- Scrive config forward proxy dopo `make install`.
- Installa il plugin in `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so`.
- Configura `plugin.config` e `ats_proxy_filter.conf`.
- Crea servizio systemd hardened.
- Abilita UFW, fail2ban, unattended upgrades, etckeeper, sysctl hardening.
- Installa health check `/opt/ats_health.sh` via cron.
- Esegue verifica base DENY/WHITELIST/AUTH.

## Note Critiche

- Non installare il plugin in `/opt/trafficserver/lib/modules/`: ATS 9.2.13 in questa build lo carica da `/opt/trafficserver/libexec/trafficserver/`.
- `records.config` deve contenere `proxy.config.url_remap.remap_required INT 0` e `proxy.config.reverse_proxy.enabled INT 0`.
- Su Ubuntu 26.04 non usare `--enable-pcre2`: ATS 9.2.13 richiede PCRE1.
- Se `DENY` non sembra applicarsi dopo test ripetuti, considerare il limite noto della DNS cache sul hook `TS_HTTP_OS_DNS_HOOK` e riavviare ATS per test policy.

## Stato Non Incluso Nel Test E2E

- TLS frontend opzionale `ATS_TLS_ENABLED=y` non incluso nella batteria end-to-end del 2026-05-26.
- ATS 10.x non incluso nella baseline.
