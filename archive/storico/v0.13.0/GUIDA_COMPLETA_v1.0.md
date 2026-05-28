# ATS Proxy Enterprise - Guida Completa

Versione documento: **1.1 corrente**, mantenuta con nome storico per continuita.  
Copre: installazione, configurazione, plugin, hardening, verifica, manutenzione e troubleshooting della baseline **0.13.0**.

## Stato Validato

- Ubuntu 24.04.4 VM135: installer completo OK, regression 9/9, hardening 25/25.
- Ubuntu 26.04 VM136: installer completo OK, regression 9/9, hardening 25/25.
- ATS 9.2.13 compilato da sorgente.
- Plugin `ats_proxy_filter_v21` sorgente e binario versionati.

## Runbook Rapido Da Zero

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env

bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

## Architettura

```text
Client
  -> UFW
  -> ip_allow.yaml
  -> ATS forward proxy
  -> ats_proxy_filter.so
       -> ADMIN: bypass
       -> DENY: 403 Forbidden
       -> WHITELIST: continue
       -> AUTH missing/wrong: 407 Proxy Authentication Required
       -> AUTH valid: continue
  -> upstream HTTP/HTTPS CONNECT
```

Layer di sicurezza:

| Layer | Funzione |
|-------|----------|
| UFW | espone solo SSH e porta proxy alla subnet autorizzata |
| `ip_allow.yaml` | ACL di ingresso ATS |
| plugin | policy applicativa per host e credenziali |
| systemd sandbox | riduce impatto compromissione processo |
| fail2ban | ban su SSH e auth fail proxy |
| logging/etckeeper | audit e tracciabilita config |

## File E Percorsi

| Percorso | Scopo |
|----------|-------|
| `/opt/trafficserver` | installazione ATS |
| `/etc/trafficserver` | configurazione ATS e plugin |
| `/opt/trafficserver/var/trafficserver/cache` | cache |
| `/opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log` | log audit |
| `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so` | plugin caricato da ATS |
| `/opt/ats_health.sh` | health check automatico |
| `/var/log/ats-health.log` | log health check |

## Configurazione Plugin

File: `/etc/trafficserver/ats_proxy_filter.conf`.

```text
ADMIN 192.168.89.10
DENY httpbin.org
DENY bad.com
DENY malware.net
WHITELIST google.com
WHITELIST github.com
WHITELIST ubuntu.com
USER admin password-forte
USER user1 password-forte-2
```

Semantica:

- `ADMIN`: IP sorgente che bypassa DENY/WHITELIST/AUTH.
- `DENY`: dominio bloccato con `403 Forbidden`.
- `WHITELIST`: dominio ammesso senza auth.
- `USER`: credenziali Basic per domini non whitelist e non denied.

Ordine effettivo: admin bypass, deny, whitelist, auth.

Limite noto: il plugin usa `TS_HTTP_OS_DNS_HOOK`; la cache DNS ATS puo evitare hook successivi su domini gia risolti. Per test policy ripetuti fare restart ATS.

## Configurazione ATS Minima

`records.config` deve contenere:

```text
CONFIG proxy.config.http.server_ports STRING 8080
CONFIG proxy.config.url_remap.remap_required INT 0
CONFIG proxy.config.reverse_proxy.enabled INT 0
CONFIG proxy.config.log.logging_enabled INT 3
CONFIG proxy.config.dns.nameservers STRING NULL
CONFIG proxy.config.dns.resolv_conf STRING /etc/resolv.conf
```

`plugin.config`:

```text
ats_proxy_filter.so
```

`storage.config`:

```text
/opt/trafficserver/var/trafficserver/cache 10G
```

Permessi:

```bash
sudo chown ats:ats /etc/trafficserver/*
sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
sudo chmod 640 /etc/trafficserver/ats_proxy_filter.conf
```

## Verifiche Funzionali

Manuale:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8080 http://httpbin.org/ip
curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8080 http://google.com
curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8080 http://reddit.com
curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8080 --proxy-user admin:'<password>' http://reddit.com
```

Atteso con config standard:

- `httpbin.org`: `403`.
- `google.com`: `301` o `200`.
- `reddit.com` senza credenziali: `407`.
- `reddit.com` con credenziali valide: `301` o `200`.

Automatica:

```bash
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

## Hardening

Applicato dall'installer:

- servizio `trafficserver` con `User=ats`, `Group=ats`;
- `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`, `PrivateDevices=true`, `NoNewPrivileges=true`;
- `ReadOnlyPaths=/opt/trafficserver`;
- `ReadWritePaths=/etc/trafficserver /opt/trafficserver/var/trafficserver /opt/trafficserver/var/log/trafficserver`;
- UFW active, porta proxy aperta solo dalla subnet autorizzata;
- SSH key-only, root login disabilitato;
- fail2ban jails `sshd` e `ats-proxy`;
- unattended upgrades enabled/active;
- etckeeper inizializzato;
- `/opt/ats_health.sh` in cron;
- log health `640`.

Verifica automatica:

```bash
sudo bash scripts/ats-hardening-check.sh 8080
```

## Health Check

Il controllo considera sani `200`, `403`, `407`, perche dipendono dalla policy configurata.

```bash
sudo /opt/ats_health.sh
sudo tail -20 /var/log/ats-health.log
```

## Logging

Log audit: `/opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log`.

Formato validato:

```text
%<chi> %<caun> [%<cqtn>] "%<cqtx>" %<pssc> %<pscl> %<{Host}cqh> %<shn>
```

Comandi utili:

```bash
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
sudo grep ' 403 ' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
sudo grep ' 407 ' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
```

## Troubleshooting Rapido

| Problema | Diagnosi | Azione |
|----------|----------|--------|
| porta 8080 chiusa | `systemctl status trafficserver`, `ss -tlnp` | restart service, controllare journal |
| tutte le richieste 404 | forward proxy non attivo | `url_remap.remap_required=0`, `reverse_proxy.enabled=0` |
| plugin non applica policy | plugin path o config errati | verificare `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so` e `plugin.config` |
| auth valida torna 407 | password/config non corrisponde | controllare `USER` in `ats_proxy_filter.conf` |
| fail2ban senza jail proxy | jail non ricaricata | `sudo systemctl restart fail2ban` |
| install 26.04 fallisce su PCRE | PCRE1 mancante | compilare PCRE1 8.45 o usare installer |

## Documenti Collegati

- `GUIDA_INSTALLAZIONE_ATS_v3.0_UNIFICATA.md`: installazione dettagliata e librerie.
- `GUIDA_OPERATIVA_ATS_v1.0.md`: operazioni quotidiane.
- `GUIDA_PLUGIN_UNIFICATO_v2.1.md`: plugin e policy.
- `GUIDA_UPGRADE_CVE_v1.0.md`: aggiornamenti e CVE.
- `GUIDA_LOG_SIEM_v1.0.md`: log forwarding.
- `TEST_MATRIX.md`: test reali.
