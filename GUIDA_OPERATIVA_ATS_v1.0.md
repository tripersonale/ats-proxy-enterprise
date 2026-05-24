# Apache Traffic Server — Guida Operativa

## Come si fanno le operazioni quotidiane

**Versione 1.0 — 24 Maggio 2026**

---

## 1. Comandi base

```bash
# Stato servizio
sudo systemctl status trafficserver

# Avvio / Stop / Restart
sudo systemctl start trafficserver
sudo systemctl stop trafficserver
sudo systemctl restart trafficserver

# Riavvio automatico al boot
sudo systemctl enable trafficserver

# Log in tempo reale (journal)
sudo journalctl -u trafficserver -f

# Log in tempo reale (audit)
sudo tail -f /var/lib/trafficserver/log/trafficserver/audit.log

# Verifica che la porta sia in ascolto
sudo ss -tlnp | grep 8080
```

---

## 2. Gestione ACL — Aggiungere/Rimuovere Subnet

### Aggiungere una subnet

Modificare `/etc/trafficserver/ip_allow.yaml`, aggiungere il blocco PRIMA del deny finale:

```yaml
  - apply: in
    ip_addrs: 10.0.0.0/8
    action: allow
    method: GET|POST|CONNECT|HEAD|PUT|DELETE|OPTIONS
```

Poi **reload senza restart**:

```bash
sudo /opt/trafficserver/bin/traffic_ctl config reload
```

Il reload e immediato e non interrompe le connessioni attive.

### Rimuovere una subnet

Rimuovere il blocco relativo da `ip_allow.yaml` e fare reload. Stessa procedura.

### Bloccare un IP specifico

**ATTENZIONE**: `ip_allow.yaml` usa **first-match** (ordine conta). Il deny deve venire PRIMA dell'allow. **Il reload non basta, serve RESTART.**

```yaml
# Mettere SEMPRE il deny PRIMA dell'allow
ip_allow:
  - apply: in
    ip_addrs: 192.168.89.99/32
    action: deny
    method: ALL
  - apply: in
    ip_addrs: 192.168.89.0/24
    action: allow
    method: GET|POST|CONNECT|HEAD|PUT|DELETE|OPTIONS
  # ... resto delle regole ...
```

Poi **obbligatorio RESTART**:

```bash
sudo systemctl restart trafficserver
```

Il blocco è immediato dopo il restart. L'IP non può più connettersi (connection refused, non HTTP 403).

### Sbloccare un IP

**Il reload non basta, serve RESTART anche per sbloccare.** Rimuovere la riga deny e fare restart:

```bash
sudo systemctl restart trafficserver
```

Il ripristino è immediato dopo il restart.

### Verifica ordine (FONDAMENTALE!)

In `ip_allow.yaml` **l'ordine CONTA** (first-match, come iptables). La prima regola che matcha vince.

```yaml
# SBAGLIATO: allow prima, deny dopo → deny IGNORATO
  - allow: 192.168.89.0/24    # matcha per primo per .99
  - deny: 192.168.89.99/32    # mai raggiunto!

# CORRETTO: deny prima, allow dopo → deny applicato
  - deny: 192.168.89.99/32    # matcha per primo per .99
  - allow: 192.168.89.0/24    # matcha per gli altri IP
```

### Testare le ACL

```bash
# Da IP autorizzato (deve dare 200)
curl -x http://PROXY_IP:8080 http://httpbin.org/ip

# Da IP NON autorizzato (deve dare 403)
# NOTA: NON testare da localhost! Localhost bypassa le ACL.
# Testare da un'altra macchina sulla stessa rete.
```

**IMPORTANTE**: Non testare le ACL da localhost (127.0.0.1) — le richieste locali bypassano `ip_allow.yaml`.

### Verifica ordine (non conta!)

A differenza di iptables, in `ip_allow.yaml` **l'ordine delle regole NON conta**. Le regole piu specifiche vincono su quelle piu ampie a prescindere dalla posizione.

---

## 3. Gestione Log — Cambiare formato, rotazione, retention

### Cambiare il formato di log

Modificare `/etc/trafficserver/logging.yaml`, sezione `formats`:

```yaml
  formats:
    - name: audit
      format: '%<chi> %<caun> [%<cqtn>] "%<cqtx>" %<pssc> %<pscl> %<{Host}cqh> %<shn>'
```

**ATTENZIONE**: `logging.yaml` richiede **restart completo** per applicare le modifiche:

```bash
sudo systemctl restart trafficserver
```

`traffic_ctl config reload` NON ricarica `logging.yaml`.

### Aggiungere campi al log

Aggiungere le variabili alla stringa `format`. Esempio con user-agent:

```yaml
format: '%<chi> [%<cqtn>] "%<cqtx>" %<pssc> %<pscl> %<{Host}cqh> %<{User-Agent}cqh>'
```

### Rotazione log

Configurata in `logging.yaml`:

```yaml
  logs:
    - filename: audit
      rolling_enabled: 1           # Attiva rotazione
      rolling_interval_sec: 86400  # Ogni 24 ore (86400 secondi)
      rolling_size_mb: 1000        # O quando supera 1 GB
```

### Retention (spazio massimo)

In `records.config`:

```
CONFIG proxy.config.log.max_space_mb_for_logs INT 10000
CONFIG proxy.config.log.auto_delete_rolled_files INT 1
```

Con 10000 MB e rotazione attiva, i file piu vecchi vengono cancellati automaticamente.

### Leggere i log

```bash
# Ultime 10 righe
sudo tail -10 /var/lib/trafficserver/log/trafficserver/audit.log

# Cercare un IP specifico
sudo grep "192.168.89.55" /var/lib/trafficserver/log/trafficserver/audit.log

# Cercare 403 (accessi negati)
sudo grep " 403 " /var/lib/trafficserver/log/trafficserver/audit.log

# Contare richieste per FQDN
sudo cut -d' ' -f8 /var/lib/trafficserver/log/trafficserver/audit.log | sort | uniq -c | sort -rn
```

---

## 4. Riavvio senza downtime

### Reload parziale (remap.config, ip_allow.yaml)

```bash
sudo /opt/trafficserver/bin/traffic_ctl config reload
```

Non interrompe le connessioni attive. Funziona per:
- `ip_allow.yaml`
- `remap.config`
- `parent.config`
- `hosting.config`

**NON funziona** per `records.config` e `logging.yaml` — quelli richiedono restart.

### Restart completo

```bash
sudo systemctl restart trafficserver
```

Breve downtime (1-2 secondi). Le connessioni attive vengono droppate.

### Verificare se il reload ha funzionato

```bash
sudo /opt/trafficserver/bin/traffic_server -C verify_config
```

Controlla la sintassi senza applicare. Se ci sono errori, il file non viene caricato.

---

## 5. Monitoraggio

### Stato live con traffic_top

```bash
/opt/trafficserver/bin/traffic_top
```

Mostra in tempo reale: richieste/sec, cache hit rate, connessioni attive, memoria.

### Metriche via traffic_ctl

```bash
# Richieste totali processate
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# Cache hit count
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.cache.total_hits

# Connessioni client attive
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.current_client_connections

# Tutte le metriche disponibili
sudo /opt/trafficserver/bin/traffic_ctl metric match proxy.process
```

### Log di sistema

```bash
# Tutti i log di ATS (journal)
sudo journalctl -u trafficserver --since "1 hour ago"

# Errori e warning
sudo journalctl -u trafficserver -p warning

# Diags log (interno ATS)
sudo tail -50 /var/lib/trafficserver/log/trafficserver/diags.log
```

---

## 6. Backup e Ripristino

### Backup configurazioni

```bash
sudo tar czf ats-backup-$(date +%Y%m%d-%H%M).tar.gz /etc/trafficserver/
```

### Ripristino

```bash
sudo systemctl stop trafficserver
sudo tar xzf ats-backup-20260524.tar.gz -C /
sudo chown -R ats:ats /etc/trafficserver
sudo systemctl start trafficserver
```

### Cosa backuppare

| File | Importanza |
|------|-----------|
| `records.config` | Critico — configurazione principale |
| `ip_allow.yaml` | Critico — ACL |
| `logging.yaml` | Medio — formato log |
| `storage.config` | Medio — cache disco |
| `remap.config` | Basso (vuoto per forward proxy) |

---

## 7. Aggiornare ATS (nuova versione)

Quando esce una nuova versione LTS di ATS:

```bash
# 1. Scarica nuovi sorgenti
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.NEW.tar.bz2
tar -xjf trafficserver-9.2.NEW.tar.bz2
cd trafficserver-9.2.NEW

# 2. Compila (stesse opzioni)
autoreconf -if
./configure \
  --prefix=/opt/trafficserver \
  --with-user=ats --with-group=ats \
  [stesse opzioni di prima]

make -j$(nproc)
sudo make install

# 3. Ricarica librerie
sudo ldconfig

# 4. Riavvia
sudo systemctl restart trafficserver
```

**Backuppare sempre `/etc/trafficserver/` prima dell'upgrade** — alcuni default potrebbero cambiare.

---

## 8. Risoluzione problemi comuni

### Servizio non parte (lock file)

```bash
sudo systemctl stop trafficserver
sudo rm -f /var/lib/trafficserver/trafficserver/manager.lock
sudo rm -f /var/lib/trafficserver/trafficserver/server.lock
sudo rm -f /var/lib/trafficserver/trafficserver/*.sock
sudo systemctl start trafficserver
```

### 404 Not Found dal proxy

Verificare `records.config`:

```bash
grep url_remap /etc/trafficserver/records.config
# Deve contenere: proxy.config.url_remap.remap_required INT 0
```

### 403 Access Denied

- Controllare `ip_allow.yaml` che il proprio IP/subnet sia in allow
- **NON testare da localhost** (local bypass)
- Fare reload: `traffic_ctl config reload`

### Log vuoti

```bash
# Verificare che la directory esista
sudo mkdir -p /var/lib/trafficserver/log/trafficserver
sudo chown ats:ats /var/lib/trafficserver/log/trafficserver

# Riavviare
sudo systemctl restart trafficserver

# Controllare errori
sudo grep -i "log\|error" /var/lib/trafficserver/log/trafficserver/diags.log | tail -10
```

### Deny non funziona (IP bloccato naviga ancora)

```bash
# 1. Verificare che il deny sia PRIMA dell'allow
sudo cat /etc/trafficserver/ip_allow.yaml

# 2. FARE RESTART, non solo reload!
sudo systemctl restart trafficserver

# 3. Testare da IP remoto, non da localhost
curl -x http://PROXY_IP:8080 http://httpbin.org/ip
```

### Connection refused

```bash
# Verificare che la porta sia in ascolto
sudo ss -tlnp | grep 8080

# Se vuoto, il servizio non e partito
sudo systemctl status trafficserver
sudo journalctl -u trafficserver -n 30
```

---

## 9. Esempi reali dalla VM di test

### Log dopo richiesta HTTP

```
127.0.0.1 - [24/May/2026:14:04:46 -0000] "GET http://httpbin.org/ip HTTP/1.1" 200 41 httpbin.org httpbin.org
```

Campi: IP client `127.0.0.1`, timestamp, request completa, status 200, 41 bytes, FQDN richiesto `httpbin.org`, hostname backend `httpbin.org`.

### Log dopo CONNECT HTTPS

```
127.0.0.1 - [24/May/2026:14:04:48 -0000] "CONNECT httpbin.org:443/ HTTP/1.1" 200 4748 httpbin.org:443 httpbin.org
```

Il CONNECT tunnel e loggato come richiesta separata. I dati dentro al tunnel non sono visibili (cifrati end-to-end).

### Test funzionale da remoto

```bash
# Da un'altra macchina sulla subnet 192.168.89.0/24
$ curl -x http://192.168.89.27:8080 http://httpbin.org/ip
{
  "origin": "93.33.199.6"
}

$ curl -x http://192.168.89.27:8080 https://httpbin.org/ip
{
  "origin": "93.33.199.6"
}
```

### 10 richieste concorrenti

```bash
$ for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -x http://192.168.89.27:8080 http://httpbin.org/ip & done; wait
200 200 200 200 200 200 200 200 200 200
```

Tutte 200 — il proxy gestisce concorrenza senza errori.

---

*Guida basata su test reali: VM 130, Ubuntu 24.04.4 LTS, ATS 9.2.13*
