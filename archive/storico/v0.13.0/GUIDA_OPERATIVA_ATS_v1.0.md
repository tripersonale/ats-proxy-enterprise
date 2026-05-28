# Apache Traffic Server - Manuale Operativo

Documento corrente, ricreato in root per mantenere la qualita operativa precedente con i dati validati 0.13.0.

## Stato Operativo Validato

| Area | Stato |
|------|-------|
| Servizio ATS | `trafficserver` active su VM135/VM136 |
| Regression | 9/9 OK su 24.04 e 26.04 |
| Hardening | 25/25 OK su 24.04 e 26.04 |
| Plugin | v2.1 da file config, sorgente e binario versionati |
| Baseline ATS | 9.2.13 |

## Comandi Base

```bash
sudo systemctl status trafficserver
sudo systemctl start trafficserver
sudo systemctl stop trafficserver
sudo systemctl restart trafficserver
sudo journalctl -u trafficserver -f
sudo ss -tlnp | grep 8080
```

Comandi ATS:

```bash
sudo /opt/trafficserver/bin/traffic_ctl config reload
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.current_client_connections
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.cache.total_hits
```

## Verifica Giornaliera

```bash
systemctl is-active trafficserver
bash /opt/ats_health.sh 2>/dev/null || sudo /opt/ats_health.sh
curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8080 http://httpbin.org/ip
curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8080 http://google.com
```

Con config standard: `403` per `httpbin.org`, `301` o `200` per `google.com`.

## Gestione Dei 4 Livelli Di Policy

### 1. ACL YAML

File:

```text
/etc/trafficserver/ip_allow.yaml
```

Regola importante: e first-match. Per bloccare un IP specifico, mettere il deny prima dell'allow di subnet.

```yaml
ip_allow:
  - apply: in
    ip_addrs: 192.168.89.99/32
    action: deny
    method: ALL
  - apply: in
    ip_addrs: 192.168.89.0/24
    action: allow
    method: GET|POST|CONNECT|HEAD|PUT|DELETE|OPTIONS
```

Per cambi ACL importanti usare restart:

```bash
sudo systemctl restart trafficserver
```

### 2. URL Filter

File:

```text
/etc/trafficserver/ats_proxy_filter.conf
```

```text
DENY httpbin.org
WHITELIST google.com
```

Dopo modifica:

```bash
sudo chown ats:ats /etc/trafficserver/ats_proxy_filter.conf
sudo chmod 640 /etc/trafficserver/ats_proxy_filter.conf
sudo systemctl restart trafficserver
```

### 3. Auth Da File

```text
USER admin nuova-password-forte
USER operatore altra-password-forte
```

Dopo modifica serve restart ATS. Non committare password reali nel repo.

### 4. Admin Bypass IP

```text
ADMIN 192.168.89.10
```

L'admin bypass viene valutato prima di DENY/WHITELIST/AUTH. Va testato da una macchina con quell'IP, non da un client diverso.

## Logging

Audit log:

```bash
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
sudo grep ' 403 ' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
sudo grep ' 407 ' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
```

Diagnostics:

```bash
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log
sudo journalctl -u trafficserver -n 100 --no-pager
```

Health log:

```bash
sudo tail -f /var/log/ats-health.log
```

## Hardening Check

```bash
sudo bash scripts/ats-hardening-check.sh 8080
```

Output atteso:

```text
Passed: 25  Failed: 0  Warnings: 0
```

Se fallisce, non dichiarare la VM conforme. Correggere prima il componente indicato.

## Aggiornare Policy In Sicurezza

Procedura standard:

```bash
sudo cp -a /etc/trafficserver/ats_proxy_filter.conf /etc/trafficserver/ats_proxy_filter.conf.$(date +%Y%m%d-%H%M%S).bak
sudo editor /etc/trafficserver/ats_proxy_filter.conf
sudo chown ats:ats /etc/trafficserver/ats_proxy_filter.conf
sudo chmod 640 /etc/trafficserver/ats_proxy_filter.conf
sudo systemctl restart trafficserver
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

Se etckeeper e attivo:

```bash
cd /etc
sudo git status --short
sudo etckeeper commit 'Update ATS proxy policy'
```

## Incident Response Rapida

1. Salvare stato:

```bash
date -Is
systemctl status trafficserver --no-pager
sudo journalctl -u trafficserver -n 200 --no-pager
sudo tail -200 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log
sudo tail -200 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
```

2. Bloccare IP client se necessario in `ip_allow.yaml` con deny prima dell'allow.

3. Restart ATS.

4. Eseguire regression e hardening check.

## Troubleshooting

| Sintomo | Causa probabile | Azione |
|---------|-----------------|--------|
| `000` da curl | ATS giu, UFW, ACL o timeout upstream | status, journal, UFW, ip_allow |
| `404`/`ERR_INVALID_URL` | forward proxy non configurato | `remap_required=0`, `reverse_proxy.enabled=0` |
| `407` con credenziali corrette | config USER errata o non riavviata | controllare file e restart |
| DENY non applicato dopo visite precedenti | DNS cache gap OS_DNS hook | restart per test, vedere guida plugin |
| jail fail2ban proxy assente | jail non ricaricata | `sudo systemctl restart fail2ban` |
| log non scritti | permessi/logging.yaml | chown/chmod, restart |

## Cose Da Non Fare

- Non aggiornare ad ATS 10.x in produzione senza laboratorio.
- Non mettere il plugin in `lib/modules` per questa build.
- Non dichiarare risolto il DNS cache gap senza test specifico.
- Non usare password reali nei file tracciati da Git.
