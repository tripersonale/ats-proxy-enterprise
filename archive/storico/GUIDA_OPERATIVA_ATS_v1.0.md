# Apache Traffic Server — Guida Operativa

## Come si fanno le operazioni quotidiane

**Versione 1.1 — 24 Maggio 2026 — Aggiornata con compliance, debug, incident response**

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
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

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
# NOTA: Testare da IP remoto per risultati affidabili.
# Da localhost, se 127.0.0.1 e in allow il test passa, ma UFW non viene testato.
# Testare da un'altra macchina sulla stessa rete.
```

**IMPORTANTE**: Testare le ACL da IP remoto. Da localhost il test non e rappresentativo: 127.0.0.1 e soggetto ad ACL normalmente, ma il loopback non passa da UFW, quindi il test non copre entrambi i layer di sicurezza.

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
sudo tail -10 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# Cercare un IP specifico
sudo grep "192.168.89.55" /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# Cercare 403 (accessi negati)
sudo grep " 403 " /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# Contare richieste per FQDN
sudo cut -d' ' -f8 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log | sort | uniq -c | sort -rn
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
sudo tail -50 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log
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
sudo rm -f /opt/trafficserver/var/trafficserver/manager.lock
sudo rm -f /opt/trafficserver/var/trafficserver/server.lock
sudo rm -f /opt/trafficserver/var/trafficserver/*.sock
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
- **Usare IP remoto per test** (localhost non testa UFW)
- Fare reload: `traffic_ctl config reload`

### Log vuoti

```bash
# Verificare che la directory esista
sudo mkdir -p /opt/trafficserver/var/trafficserver/log/trafficserver
sudo chown ats:ats /opt/trafficserver/var/trafficserver/log/trafficserver

# Riavviare
sudo systemctl restart trafficserver

# Controllare errori
sudo grep -i "log\|error" /opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log | tail -10
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

## 10. Modalita Debug

### Quando attivare il debug

In produzione `diags.debug.enabled` e impostato a `0`. Attivare il debug solo per diagnostica temporanea:

```bash
# 1. Modificare records.config
sudo sed -i 's/CONFIG proxy.config.diags.debug.enabled INT 0/CONFIG proxy.config.diags.debug.enabled INT 1/' /etc/trafficserver/records.config

# 2. Aumentare verbosita diags (opzionale)
echo 'CONFIG proxy.config.diags.debug.tags STRING http|dns|hostdb' | sudo tee -a /etc/trafficserver/records.config

# 3. Restart (necessario per records.config)
sudo systemctl restart trafficserver

# 4. Monitorare output
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log
sudo journalctl -u trafficserver -f
```

### Tag di debug utili

| Tag | Cosa traccia |
|-----|-------------|
| `http` | Transazioni HTTP (header, status, errori) |
| `dns` | Risoluzione DNS, cache, timeout |
| `hostdb` | Host database, round-robin backend |
| `cache` | Cache hit/miss, write, eviction |
| `acl` | Valutazione ip_allow.yaml |
| `socket` | Connessioni TCP, accept/connect/close |

### Disattivare il debug

```bash
sudo sed -i 's/CONFIG proxy.config.diags.debug.enabled INT 1/CONFIG proxy.config.diags.debug.enabled INT 0/' /etc/trafficserver/records.config
sudo sed -i '/proxy.config.diags.debug.tags/d' /etc/trafficserver/records.config
sudo systemctl restart trafficserver
```

### Catturare traffico HTTP raw (tcpdump)

```bash
# Catturare traffico sulla porta proxy (debug estremo)
sudo tcpdump -i any -A -s 0 port 8080 -w /tmp/ats-debug.pcap

# Analizzare con:
sudo tcpdump -r /tmp/ats-debug.pcap -A | less
```

---

## 11. Compliance — Gestione Dati e GDPR

### ⚠️ Avvertenza legale

L'IP del client e considerato **dato personale** ai sensi del GDPR (Art. 4.1). Il log `audit.log` contiene dati personali. Il titolare del trattamento deve:

1. **Definire la base giuridica** del trattamento (Art. 6 GDPR)
2. **Fornire informativa** agli utenti (Art. 13-14 GDPR)
3. **Registrare il trattamento** nel registro ex Art. 30
4. **Valutare DPIA** se richiesto (Art. 35)

### Retention policy configurata

| Dato | File | Retention |
|------|------|-----------|
| Log accesso proxy | `audit.log` | Rolling 24h, auto-delete a 10000 MB |
| Log di sistema | journald | 30 giorni |
| Log diagnostici | `diags.log` | Rolling automatico |
| Configurazioni | etckeeper git | Illimitato |

### Procedura diritto di accesso (GDPR Art. 15)

```bash
# Estraggo tutte le richieste di un IP specifico
sudo grep "^192.168.89.55 " /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log*

# Con timestamp leggibile e ordinamento
sudo grep "^192.168.89.55 " /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log* | sort -t'[' -k2
```

### Procedura diritto di cancellazione (GDPR Art. 17)

```bash
# 1. Fermare il proxy (per evitare scritture concorrenti)
sudo systemctl stop trafficserver

# 2. Rimuovere le righe dell'IP dai log (IN PLACE)
sudo sed -i '/^192.168.89.55 /d' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# 3. Verificare
sudo grep "192.168.89.55" /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
# Atteso: nessun output

# 4. Riavviare
sudo systemctl start trafficserver

# NOTA: Per log ruotati (.old), applicare sed anche su quelli:
sudo sed -i '/^192.168.89.55 /d' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log.old
```

### Anonimizzazione IP (GDPR by design)

Per ridurre il rischio GDPR, valutare l'anonimizzazione degli IP nei log prima della scrittura:

```yaml
# In logging.yaml, sostituire %<chi> con hash SHA256 dell'IP
# Richiede plugin custom o script di post-processing.

# Alternativa: troncare ultimo ottetto (pseudo-anonimizzazione)
# Da: 192.168.89.55  →  A: 192.168.89.0
# Via script cron:
# sudo sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+ /\1.0 /' audit.log > audit-anon.log
```

### Template informativa (estratto)

> *"L'accesso a Internet tramite il proxy aziendale e soggetto a registrazione. Vengono raccolti: indirizzo IP del dispositivo, nome host dei siti visitati (non gli URL completi), data e ora della richiesta. Il trattamento e effettuato per finalita di sicurezza della rete (legittimo interesse del titolare) e ottemperanza agli obblighi di legge (Art. 132 D.Lgs 196/2003). I dati sono conservati per 6 mesi e accessibili solo al personale autorizzato. Per esercitare i diritti di cui agli Art. 15-22 GDPR, contattare il DPO all'indirizzo [email]."*

---

## 12. Incident Response

### Classificazione incidenti

| Livello | Descrizione | Esempio |
|---------|-------------|---------|
| P1 — Critico | Proxy non disponibile o violazione confermata | Servizio down, data breach |
| P2 — Alto | Degradazione funzionale o tentativo attacco in corso | Abuso proxy, scansione massiva |
| P3 — Medio | Anomalia senza impatto immediato | Errori intermittenti, log warning |
| P4 — Basso | Evento informativo | Tentativo singolo bloccato da ACL |

### Procedura P1/P2 — Incident Response Flow

```bash
# === FASE 1: DETECTION ===
# Identificare l'anomalia
sudo tail -100 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log | grep -c " 403 "
sudo journalctl -u trafficserver -p err --since "1 hour ago"
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# === FASE 2: ANALYSIS ===
# Determinare IP malevolo
sudo grep " 403 " /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log | cut -d' ' -f1 | sort | uniq -c | sort -rn | head -20

# Identificare pattern (es. brute force, scan)
sudo grep "192.168.89.99" /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log | cut -d' ' -f6 | sort | uniq -c | sort -rn

# === FASE 3: CONTAINMENT ===
# Blocco immediato IP malevolo
sudo cp /etc/trafficserver/ip_allow.yaml /etc/trafficserver/ip_allow.yaml.bak.$(date +%s)
# Inserire deny PRIMA degli allow usando sed:
sudo sed -i '3i\  - apply: in\n    ip_addrs: 192.168.89.99/32\n    action: deny\n    method: ALL' /etc/trafficserver/ip_allow.yaml
sudo systemctl restart trafficserver

# Alternativa: blocco via UFW (piu drastico)
sudo ufw deny from 192.168.89.99 to any port 8080 proto tcp

# === FASE 4: EVIDENCE PRESERVATION ===
# Backup immediato log e config
sudo tar czf /root/incident-$(date +%Y%m%d-%H%M).tar.gz \
  /opt/trafficserver/opt/trafficserver/var/log/trafficserver/ \
  /etc/trafficserver/ \
  /var/log/auth.log
```

### Template notifica NIS2 (early warning 24h)

```
A: [ACN - CSIRT Italia / autorita competente NIS2]
Oggetto: Early Warning Incidente NIS2 — ATS Proxy Enterprise

1. SOGGETTO NOTIFICANTE
   - Denominazione: [Nome Organizzazione]
   - Referente: [Nome, telefono, email]
   - Ruolo NIS2: [Essenziale / Importante]
   - Settore: [es. Infrastrutture digitali]

2. INCIDENTE
   - Data/ora rilevamento: [YYYY-MM-DD HH:MM UTC]
   - Data/ora presunto inizio: [YYYY-MM-DD HH:MM UTC]
   - Stato: [In corso / Contenuto / Risolto]
   - Classificazione: [P1 / P2 / P3]
   - Descrizione sintetica: [Cosa e successo, impatto]

3. IMPATTO
   - Servizi impattati: [ATS Proxy Enterprise]
   - Utenti impattati: [Numero]
   - Dati eventualmente compromessi: [SI/NO, descrizione]
   - Impatto transfrontaliero: [SI/NO, specificare paesi]

4. AZIONI INTRAPRESE
   - [Misure di containment]
   - [Soggetti informati]
```

### Template notifica GDPR (Garante Privacy, Art. 33)

```
A: Garante per la Protezione dei Dati Personali
Oggetto: Notifica violazione dati personali — Art. 33 GDPR

1. NATURA DELLA VIOLAZIONE
   - Categorie dati: [es. Indirizzi IP, log di navigazione]
   - Numero interessati: [approssimativo]
   - Volume dati: [approssimativo]
   - Categorie interessati: [es. Dipendenti, utenti]

2. CONSEGUENZE PROBABILI
   - [Valutazione rischio per diritti e liberta]

3. MISURE ADOTTATE
   - [Containment, ripristino, mitigazione]

4. REFERENTE
   - DPO: [Nome, contatti]
```

---

## 13. Gestione Richieste GDPR (Template Operativo)

### Richiesta di accesso (Art. 15) — Procedura

```bash
#!/bin/bash
# Script: gdpr-access.sh
# Uso: sudo bash gdpr-access.sh 192.168.89.55

IP="$1"
OUTPUT="/tmp/gdpr-access-${IP//./-}-$(date +%Y%m%d).txt"

echo "=== RAPPORTO ACCESSO DATI PERSONALI ===" > "$OUTPUT"
echo "IP Richiesto: $IP" >> "$OUTPUT"
echo "Data richiesta: $(date)" >> "$OUTPUT"
echo "Periodo: ultimi 6 mesi" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "=== LOG ACCESSO PROXY ===" >> "$OUTPUT"

sudo grep "^$IP " /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log* >> "$OUTPUT" 2>/dev/null

echo "" >> "$OUTPUT"
echo "=== FINE RAPPORTO ===" >> "$OUTPUT"
echo "Rapporto generato da: $(whoami)" >> "$OUTPUT"

cat "$OUTPUT"
```

### Richiesta di cancellazione (Art. 17) — Procedura

```bash
#!/bin/bash
# Script: gdpr-delete.sh
# Uso: sudo bash gdpr-delete.sh 192.168.89.55

IP="$1"
LOGDIR="/opt/trafficserver/var/trafficserver/log/trafficserver"
BACKUP="/root/gdpr-delete-backup-$(date +%Y%m%d-%H%M).tar.gz"

echo "=== CANCELLAZIONE DATI PERSONALI ==="
echo "IP: $IP"
echo "Backup prima della cancellazione: $BACKUP"

# Backup prima di cancellare
sudo tar czf "$BACKUP" "$LOGDIR"

# Fermare il proxy
sudo systemctl stop trafficserver

# Cancellare dai log attivi e ruotati
for f in "$LOGDIR"/audit.log*; do
    if [ -f "$f" ]; then
        sudo sed -i "/^$IP /d" "$f"
        echo "Pulito: $f"
    fi
done

# Riavviare
sudo systemctl start trafficserver

echo "Cancellazione completata per IP: $IP"
echo "Backup conservato in: $BACKUP (cancellare dopo 30 giorni)"
```

---

*Guida basata su test reali: VM 130, Ubuntu 24.04.4 LTS, ATS 9.2.13*
