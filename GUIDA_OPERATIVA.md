# Apache Traffic Server — Guida Operativa

## Operatività quotidiana, Manutenzione, Gestione CVE, Compliance

**Versione 2.0 — 26 Maggio 2026 — Basata su VM135 (24.04) e VM136 (26.04)**

---

## 1. Comandi Base

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
sudo tail -f /var/log/trafficserver/audit.log

# Verifica che la porta sia in ascolto
sudo ss -tlnp | grep 8080
```

---

## 2. Gestione ACL — Aggiungere/Rimuovere Subnet

### 2.1 Aggiungere una subnet

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

Il reload è immediato e non interrompe le connessioni attive.

### 2.2 Rimuovere una subnet

Rimuovere il blocco relativo da `ip_allow.yaml` e fare reload. Stessa procedura.

### 2.3 Bloccare un IP specifico

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

### 2.4 Sbloccare un IP

**Il reload non basta, serve RESTART anche per sbloccare.** Rimuovere la riga deny e fare restart:

```bash
sudo systemctl restart trafficserver
```

Il ripristino è immediato dopo il restart.

### 2.5 Verifica ordine (FONDAMENTALE!)

In `ip_allow.yaml` **l'ordine CONTA** (first-match, come iptables). La prima regola che matcha vince.

```yaml
# SBAGLIATO: allow prima, deny dopo → deny IGNORATO
  - allow: 192.168.89.0/24    # matcha per primo per .99
  - deny: 192.168.89.99/32    # mai raggiunto!

# CORRETTO: deny prima, allow dopo → deny applicato
  - deny: 192.168.89.99/32    # matcha per primo per .99
  - allow: 192.168.89.0/24    # matcha per gli altri IP
```

### 2.6 Testare le ACL

```bash
# Da IP autorizzato (deve dare 200)
curl -x http://PROXY_IP:8080 http://httpbin.org/ip

# Da IP NON autorizzato (deve dare 403)
# NOTA: Testare da IP remoto per risultati affidabili.
# Da localhost, se 127.0.0.1 è in allow il test passa, ma UFW non viene testato.
# Testare da un'altra macchina sulla stessa rete.
```

**IMPORTANTE**: Testare le ACL da IP remoto. Da localhost il test non è rappresentativo: 127.0.0.1 è soggetto ad ACL normalmente, ma il loopback non passa da UFW, quindi il test non copre entrambi i layer di sicurezza.

---

## 3. Gestione Utenti (Basic Auth)

Aggiungere o rimuovere utenze nel file `/etc/trafficserver/ats_proxy_filter.conf`.

```bash
# Aggiungere un'utenza
echo 'utente:hash_password' | sudo tee -a /etc/trafficserver/ats_proxy_filter.conf

# Rimuovere un'utenza
sudo sed -i '/^utente:/d' /etc/trafficserver/ats_proxy_filter.conf

# Applicare le modifiche
sudo systemctl restart trafficserver
```

---

## 4. Gestione Log — Cambiare formato, rotazione, retention

### 4.1 Cambiare il formato di log

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

### 4.2 Aggiungere campi al log

Aggiungere le variabili alla stringa `format`. Esempio con user-agent:

```yaml
format: '%<chi> [%<cqtn>] "%<cqtx>" %<pssc> %<pscl> %<{Host}cqh> %<{User-Agent}cqh>'
```

### 4.3 Rotazione log

Configurata in `logging.yaml`:

```yaml
  logs:
    - filename: audit
      rolling_enabled: 1           # Attiva rotazione
      rolling_interval_sec: 86400  # Ogni 24 ore (86400 secondi)
      rolling_size_mb: 1000        # O quando supera 1 GB
```

### 4.4 Retention (GDPR — spazio massimo)

In `records.config`:

```
CONFIG proxy.config.log.max_space_mb_for_logs INT 10000
CONFIG proxy.config.log.auto_delete_rolled_files INT 1
```

Con 10000 MB e rotazione attiva, i file più vecchi vengono cancellati automaticamente.

### 4.5 Leggere i log

```bash
# Ultime 10 righe
sudo tail -10 /var/log/trafficserver/audit.log

# Cercare un IP specifico
sudo grep "192.168.89.55" /var/log/trafficserver/audit.log

# Cercare 403 (accessi negati)
sudo grep " 403 " /var/log/trafficserver/audit.log

# Contare richieste per FQDN
sudo cut -d' ' -f8 /var/log/trafficserver/audit.log | sort | uniq -c | sort -rn
```

### 4.6 Forwarding a SIEM (rsyslog / Filebeat / JSON)

ATS scrive `audit.log` su disco. Per centralizzare i log:

```
/var/log/trafficserver/audit.log
    │
    ├──▶ rsyslog (imfile) ──▶ SIEM via TCP/UDP syslog (qualsiasi)
    ├──▶ Filebeat ──▶ Logstash ──▶ Elasticsearch ──▶ Kibana (ELK)
    ├──▶ Filebeat ──▶ Elasticsearch (direct)
    └──▶ Qualsiasi agente che legga file di testo
```

**Formato log ATS (campi per parsing)**:

| Campo | Posizione | Esempio |
|-------|-----------|---------|
| IP client | 1 | `192.168.89.27` |
| Timestamp | 2-5 (tra `[` `]`) | `24/May/2026:23:18:37 -0000` |
| Request line | 6 (tra `"`) | `HEAD http://google.com/ HTTP/1.1` |
| Status code | 7 | `200`, `301`, `403`, `407` |
| Content length | 8 | `0`, `1256` |
| FQDN richiesto | 9 | `google.com`, `wikipedia.org` |
| Backend hostname | 10 | `google.com`, `-` (per 403/407) |

**Metodo A — rsyslog (universale)**:

```bash
# Permessi: rendi audit.log leggibile da syslog
sudo chmod o+r /var/log/trafficserver/audit.log

# OPPURE aggiungi syslog al gruppo ats
sudo usermod -a -G ats syslog
sudo chmod g+r /var/log/trafficserver/audit.log

# Configura rsyslog
sudo tee /etc/rsyslog.d/99-ats-audit.conf > /dev/null << 'EOF'
module(load="imfile")

input(type="imfile"
      File="/var/log/trafficserver/audit.log"
      Tag="ats-audit"
      Facility="local0"
      Severity="info"
      PersistStateInterval="10")

# Scrittura su file locale (debug)
local0.*  /var/log/ats-remote.log

# Forward a SIEM remoto via UDP syslog
local0.*  @192.168.89.100:514

# Forward a SIEM remoto via TCP syslog
# local0.*  @@192.168.89.100:514
EOF

sudo rsyslogd -N1 && sudo systemctl restart rsyslog
```

**Metodo B — Filebeat → Elasticsearch (ELK)**:

```yaml
# /etc/filebeat/filebeat.yml
filebeat.inputs:
  - type: filestream
    enabled: true
    paths:
      - /var/log/trafficserver/audit.log
    fields:
      log_type: ats-audit
    fields_under_root: false
    multiline:
      pattern: '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
      negate: true
      match: after

output.elasticsearch:
  hosts: ["https://elastic.example.com:9200"]
  username: "elastic"
  password: "${ES_PASSWORD}"
  index: "ats-audit-%{+yyyy.MM.dd}"
  ssl.verification_mode: certificate
```

**Metodo C — Log JSON da ATS (avanzato, da verificare)**:

```yaml
# /etc/trafficserver/logging.yaml
logging:
  formats:
    - name: audit_json
      format: '{"ip":"%<chi>","ts":"%<cqtn>","method":"%<cqhm>","url":"%<cquup>","status":%<pssc>,"bytes":%<pscl>,"host":"%<{Host}cqh>","backend":"%<shn>"}'
      interval: 1
  logs:
    - filename: audit_json
      format: audit_json
      mode: ascii
      rolling_enabled: 1
      rolling_interval_sec: 86400
```

**Parsing con Logstash (per formato plain-text ATS)**:

```ruby
# /etc/logstash/conf.d/ats-audit.conf
input {
  beats { port => 5044 }
}

filter {
  grok {
    match => { "message" => "%{IP:client_ip} %{DATA} \[%{HTTPDATE:timestamp}\] \"%{WORD:method} %{URI:url} %{DATA}\" %{NUMBER:status} %{NUMBER:bytes} %{NOTSPACE:fqdn} %{NOTSPACE:backend}" }
  }
  date {
    match => [ "timestamp", "dd/MMM/yyyy:HH:mm:ss Z" ]
  }
}

output {
  elasticsearch {
    hosts => ["https://elastic:9200"]
    index => "ats-audit-%{+yyyy.MM.dd}"
    user => "elastic"
    password => "${ES_PASSWORD}"
  }
}
```

**Tabella riepilogativa metodi**:

| Metodo | Vantaggi | Svantaggi | Ideale per |
|--------|----------|-----------|-----------|
| **rsyslog** | Già installato, zero agent aggiuntivi | Parsing manuale, no retention built-in | SIEM generici, invio a syslog collector |
| **Filebeat + ES** | Installazione semplice, parsing automatico | Richiede ES cluster | ELK stack già esistente |
| **Filebeat + Logstash** | Parsing flessibile con grok, enrichment | Più componenti da gestire | Pipeline ELK complesse |
| **Log JSON nativo** | Zero parsing, ingest immediato | Supporto da verificare in ATS 9.2.13 | Ambienti con ES che accettano JSON diretto |

---

## 5. Riavvio Senza Downtime

### 5.1 Reload parziale (remap.config, ip_allow.yaml)

```bash
sudo /opt/trafficserver/bin/traffic_ctl config reload
```

Non interrompe le connessioni attive. Funziona per:
- `ip_allow.yaml`
- `remap.config`
- `parent.config`
- `hosting.config`

**NON funziona** per `records.config` e `logging.yaml` — quelli richiedono restart.

### 5.2 Restart completo

```bash
sudo systemctl restart trafficserver
```

Breve downtime (1-2 secondi). Le connessioni attive vengono droppate.

### 5.3 Verificare se il reload ha funzionato

```bash
sudo /opt/trafficserver/bin/traffic_server -C verify_config
```

Controlla la sintassi senza applicare. Se ci sono errori, il file non viene caricato.

---

## 6. Monitoraggio

### 6.1 Stato live con traffic_top

```bash
/opt/trafficserver/bin/traffic_top
```

Mostra in tempo reale: richieste/sec, cache hit rate, connessioni attive, memoria.

### 6.2 Metriche via traffic_ctl

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

### 6.3 Log di sistema

```bash
# Tutti i log di ATS (journal)
sudo journalctl -u trafficserver --since "1 hour ago"

# Errori e warning
sudo journalctl -u trafficserver -p warning

# Diags log (interno ATS)
sudo tail -50 /var/log/trafficserver/diags.log
```

### 6.4 Health check automatico

Lo script `/opt/ats_health.sh` esegue test di base e logga il risultato. Installato via cron:

```bash
# Verifica presenza
sudo crontab -l | grep ats_health.sh

# Esecuzione manuale
sudo /opt/ats_health.sh

# Log
sudo tail /var/log/ats-health.log
```

---

## 7. Backup e Ripristino

### 7.1 Cosa backuppare

| File | Importanza |
|------|-----------|
| `records.config` | Critico — configurazione principale |
| `ip_allow.yaml` | Critico — ACL |
| `logging.yaml` | Medio — formato log |
| `storage.config` | Medio — cache disco |
| `remap.config` | Basso (vuoto per forward proxy) |
| `plugin.config` | Critico — plugin caricati |
| `ats_proxy_filter.conf` | Critico — utenze auth e URL filter |

### 7.2 Procedura backup

```bash
sudo tar czf ats-backup-$(date +%Y%m%d-%H%M).tar.gz /etc/trafficserver/
```

### 7.3 Procedura ripristino

```bash
sudo systemctl stop trafficserver
sudo tar xzf ats-backup-20260526.tar.gz -C /
sudo chown -R ats:ats /etc/trafficserver
sudo systemctl start trafficserver
```

---

## 8. Hardening Audit

### 8.1 Esecuzione

```bash
sudo bash scripts/ats-hardening-check.sh
```

Lo script verifica: servizio attivo, hardening systemd, UFW, fail2ban, unattended-upgrades, etckeeper, permessi file, health check, CVE helper.

### 8.2 Interpretazione output

Esempio output atteso:

```
============================================
 ATS Proxy Hardening Check
 Port: 8080 | 2026-05-26T...
============================================

[OK] trafficserver service active
[OK] systemd User=ats
[OK] systemd Group=ats
[OK] systemd ProtectSystem=strict
[OK] systemd ProtectHome=true
[OK] systemd PrivateTmp=true
[OK] systemd PrivateDevices=true
[OK] systemd NoNewPrivileges=true
[OK] systemd ReadOnlyPaths=/opt/trafficserver
[OK] systemd ReadWritePaths=...
[OK] UFW active
[OK] UFW allows proxy port 8080
[OK] fail2ban service active
[OK] fail2ban sshd jail
[OK] fail2ban ats-proxy jail
[OK] unattended-upgrades service enabled
[OK] unattended-upgrades service active
[OK] etckeeper initialized
[OK] /etc/trafficserver/records.config mode 640
[OK] /etc/trafficserver/plugin.config mode 640
[OK] /etc/trafficserver/ats_proxy_filter.conf mode 640
[OK] /var/log/ats-health.log mode 640
[OK] health check executable
[OK] health check cron installed
[OK] CVE helper installed

============================================
Passed: 25  Failed: 0  Warnings: 0
============================================
```

### 8.3 Azioni correttive per ogni FAIL

| Check | Azione |
|-------|--------|
| UFW active → FAIL | `sudo ufw enable` |
| fail2ban service → FAIL | `sudo systemctl enable --now fail2ban` |
| fail2ban ats-proxy jail → FAIL | Verificare `/etc/fail2ban/jail.d/ats-proxy.local` e filtro |
| unattended-upgrades → FAIL | `sudo apt install unattended-upgrades && sudo systemctl enable --now unattended-upgrades` |
| etckeeper → FAIL | `sudo apt install etckeeper && sudo etckeeper init` |
| permessi file 640 → FAIL | `sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml /etc/trafficserver/*.conf` |
| health check cron → FAIL | Aggiungere: `*/5 * * * * /opt/ats_health.sh` |
| CVE helper → FAIL | Copiare `scripts/cve-check.sh` in `/opt/cve-check.sh` |

---

## 9. Aggiornamento ATS (nuova versione)

### 9.1 Pre-upgrade

```bash
# 1. Backup completo
sudo tar czf /root/ats-pre-upgrade-$(date +%Y%m%d).tar.gz \
  /etc/trafficserver/ /opt/trafficserver/bin/

# 2. Salvare metriche correnti
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests > /tmp/metrics-pre-upgrade.txt

# 3. Verificare che tutto funzioni prima dell'upgrade
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip
# Deve restituire 200

# 4. Salvare checksum dei binari attuali
sha256sum /opt/trafficserver/bin/traffic_server /opt/trafficserver/bin/traffic_manager > /tmp/ats-binary-checksums.txt
```

### 9.2 Download e compilazione nuova versione

```bash
VERSIONE="9.2.NEW"  # Sostituire con versione reale

cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-${VERSIONE}.tar.bz2
wget https://downloads.apache.org/trafficserver/trafficserver-${VERSIONE}.tar.bz2.sha256
sha256sum -c trafficserver-${VERSIONE}.tar.bz2.sha256

tar -xjf trafficserver-${VERSIONE}.tar.bz2
cd trafficserver-${VERSIONE}

autoreconf -if

# 24.04:
./configure \
  --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --enable-pcre \
  --disable-tests --disable-examples --disable-maintainer-mode

# 26.04:
export PKG_CONFIG_PATH='/usr/local/pcre/lib/pkgconfig'
./configure \
  --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --with-pcre=/usr/local/pcre \
  --disable-tests --disable-examples --disable-maintainer-mode

make -j$(nproc)
```

### 9.3 Installazione

```bash
# Fermare il servizio
sudo systemctl stop trafficserver

# Installare
sudo make install

# Ricaricare librerie
sudo ldconfig

# Verificare permessi
sudo chown -R ats:ats /opt/trafficserver

# Riavviare
sudo systemctl start trafficserver
```

### 9.4 Post-upgrade — Verifica (7 passi)

```bash
# 1. Versione
/opt/trafficserver/bin/traffic_server -V 2>&1 | head -1

# 2. Stato servizio
sudo systemctl status trafficserver --no-pager

# 3. Test proxy
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip && echo ' HTTP OK'
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 https://httpbin.org/ip && echo ' HTTPS OK'

# 4. Test concorrenza
for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' -x http://localhost:8080 http://httpbin.org/ip & done; wait; echo ''

# 5. Verifica log
sudo tail -3 /var/log/trafficserver/audit.log

# 6. Verifica ACL (ripetere batteria test ACL)

# 7. Confrontare metriche con pre-upgrade
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# 8. Verificare eventuali warning nei log
sudo grep -i "warn\|error\|fail" /var/log/trafficserver/diags.log | tail -20
```

**Backuppare sempre `/etc/trafficserver/` prima dell'upgrade** — alcuni default potrebbero cambiare.

---

## 10. Compatibilità ATS 9.x → 10.x

### 10.1 Versioni testate

| ATS | Ubuntu | PCRE1 | OpenSSL | GCC | Build System | Stato |
|-----|--------|-------|---------|-----|-------------|-------|
| 9.2.13 | 24.04 Noble | 8.39 (apt) | 3.0.x | 13.x | autotools | ✅ Testato VM135 |
| 9.2.13 | 26.04 Resolute | 8.45 (sorgente) | 3.5.5 | 15.2.0 | autotools | ✅ Testato VM136 |
| 10.1.2 | 26.04 | 8.45 | 3.5.5 | 15.2.0 | **CMake** | ⚠️ NON validato: API check parziale, build e plugin test da completare |

### 10.2 Differenze ATS 9.x → 10.x (verificato 25/05/2026)

| Aspetto | 9.x | 10.x | Impatto sul plugin |
|---------|-----|------|-------------------|
| Build system | autotools (configure/make) | **CMake** | Nuova procedura, flag diversi |
| TSUserArgSet/Get | ✅ | ✅ | **Compatibile** |
| TSUserArgIndexReserve | ✅ | ✅ | **Compatibile** |
| TSMimeHdrFieldValueStringGet | ✅ | ✅ | **Compatibile** |
| TSHttpTxnClientReqGet | ✅ | ✅ | **Compatibile** |
| TS_EVENT_HTTP_OS_DNS | 60003 | da verificare | Probabilmente invariato |
| TS_HTTP_SEND_RESPONSE_HDR_HOOK | ✅ | ✅ | **Compatibile** |
| Records format | records.config (key-value) | da verificare | Potrebbe essere YAML in 10.x |
| Plugin API | Stabile | Stabile | **Plugin v2.1 dovrebbe funzionare** (da ricompilare contro headers 10.x) |

⚠️ **NON VALIDATO** — solo analisi API. Non usare in produzione.

---

## 11. Aggiornamento Dipendenze Singole

### 11.1 OpenSSL (aggiornato da apt su entrambi)

```bash
# Verificare versione corrente
openssl version

# Aggiornare (coperto da unattended-upgrades)
sudo apt install --only-upgrade openssl libssl-dev libssl3

# Verificare che ATS funzioni ancora
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 https://httpbin.org/ip
# Deve restituire 200

# Se 000 dopo upgrade OpenSSL:
# Ricompilare ATS (link contro nuove .so)
cd /tmp/trafficserver-9.2.13
make clean && make -j$(nproc) && sudo make install && sudo ldconfig
sudo systemctl restart trafficserver
```

### 11.2 PCRE1 (da sorgente, solo 26.04)

```bash
# Verificare se ci sono nuove CVE su PCRE 8.45
# URL: https://nvd.nist.gov/vuln/search/results?query=pcre

# Se serve aggiornare PCRE1:
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/NUOVA_VERSIONE/pcre-NUOVA_VERSIONE.tar.gz
tar xzf pcre-NUOVA_VERSIONE.tar.gz
cd pcre-NUOVA_VERSIONE
./configure --prefix=/usr/local/pcre --enable-utf8 --enable-unicode-properties
make -j$(nproc)
sudo make install

# Poi ricompilare ATS
cd /tmp/trafficserver-9.2.13
make clean
export PKG_CONFIG_PATH='/usr/local/pcre/lib/pkgconfig'
./configure ... (stesse opzioni)
make -j$(nproc) && sudo make install && sudo ldconfig
sudo systemctl restart trafficserver
```

### 11.3 Zlib, Brotli, LZMA (da apt, nessuna ricompilazione)

```bash
# Queste sono linkate dinamicamente. Basta apt upgrade.
sudo apt install --only-upgrade zlib1g libbrotli1 liblzma5

# Verificare:
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip
# Deve restituire 200
```

---

## 12. Gestione CVE — Inventario e Monitoraggio

### 12.1 Inventario librerie (da monitorare manualmente)

| Libreria | 24.04 Noble (VM135) | 26.04 Resolute (VM136) | Ruolo | Fonte CVE |
|----------|----------------------|------------------------|-------|-----------|
| **ATS** | 9.2.13 | 9.2.13 | Core proxy | [Apache announce](https://lists.apache.org/list.html?announce@trafficserver.apache.org) |
| **PCRE1** | 8.39 (apt) | **8.45 (sorgente)** | Regex engine | [NVD](https://nvd.nist.gov/) |
| **OpenSSL** | 3.0.x LTS | **3.5.5** | TLS, crittografia | [openssl.org/news](https://openssl.org/news/) |
| **Zlib** | 1.3.1 | **1.3.1** | Compressione HTTP | [zlib.net](https://zlib.net/) |
| **LZMA** | 5.4.x | **5.8.3** | Compressione alternativa | NVD |
| **Brotli** | 1.1.x | **1.2.0** | Compressione | [github.com/google/brotli](https://github.com/google/brotli) |
| **libcurl** | 8.x | **8.18.0** | HTTP client interno | [curl.se](https://curl.se/) |
| **libxml2** | 2.x | 2.x | Parsing XML/config legacy e dipendenza build | [gitlab.gnome.org/GNOME/libxml2](https://gitlab.gnome.org/GNOME/libxml2) |
| **libjson-c** | 0.17 | **0.18** | Parsing JSON | [github.com/json-c](https://github.com/json-c) |
| **yaml-cpp** | interno ATS | interno ATS | Parsing YAML ACL/log | [github.com/jbeder/yaml-cpp](https://github.com/jbeder/yaml-cpp) |
| **Kernel** | 6.8.x | **7.0.0** | Sistema | [ubuntu.com/security](https://ubuntu.com/security) |
| **GCC** | 13.x | **15.2.0** | Compilatore | - |

> Versioni verificate con `scripts/cve-check.sh` eseguito su VM136.

### 12.2 Librerie di sistema (coperte da unattended-upgrades)

| Libreria | Aggiornata da | Rischio se non aggiornata |
|----------|-------------|--------------------------|
| Kernel | unattended (security) | Privilege escalation, DoS |
| systemd | unattended (security) | Escalation locale |
| OpenSSH | unattended (security) | Accesso non autorizzato |
| glibc | unattended (security) | Code execution |
| GCC runtime | unattended (security) | Basso |

### 12.3 Comandi verifica versioni

```bash
# Su entrambe le VM, eseguire periodicamente:
echo "=== PCRE ===" && pcre-config --version 2>/dev/null || /usr/local/pcre/bin/pcre-config --version
echo "=== OpenSSL ===" && openssl version
echo "=== Zlib ===" && dpkg -l zlib1g | tail -1
echo "=== LZMA ===" && dpkg -l liblzma5 | tail -1
echo "=== Brotli ===" && dpkg -l libbrotli1 | tail -1
echo "=== libcurl ===" && curl --version | head -1
echo "=== libxml2 ===" && dpkg -l libxml2 | tail -1
echo "=== libjson-c ===" && dpkg -l libjson-c5 | tail -1 || dpkg -l libjson-c-dev | tail -1
echo "=== Kernel ===" && uname -r
echo "=== GCC ===" && gcc --version | head -1
```

### 12.4 Fonti CVE e Canali di Notifica

| Fonte | URL | Cosa notifica |
|-------|-----|---------------|
| **Apache Traffic Server announce** | [lists.apache.org](https://lists.apache.org/list.html?announce@trafficserver.apache.org) | Nuove release, CVE fix |
| **Apache Traffic Server download** | [downloads.apache.org/trafficserver](https://downloads.apache.org/trafficserver/) | Nuove versioni |
| **NVD (National Vulnerability Database)** | [nvd.nist.gov](https://nvd.nist.gov/) | CVE per tutte le librerie |
| **Ubuntu Security Notices** | [ubuntu.com/security/notices](https://ubuntu.com/security/notices) | CVE pacchetti di sistema |
| **OpenSSL Vulnerabilities** | [openssl.org/news/vulnerabilities](https://www.openssl.org/news/vulnerabilities.html) | CVE OpenSSL |
| **curl Security** | [curl.se/docs/security](https://curl.se/docs/security.html) | CVE libcurl |
| **OSS-Security mailing list** | [oss-security](https://oss-security.openwall.org/wiki/mailing-lists/oss-security) | Pre-disclosure CVE |

### 12.5 Esecuzione cve-check.sh

Lo script `scripts/cve-check.sh` (testato su VM136) esegue la verifica automatica di tutte le librerie. Produce un report in `/var/log/ats-cve.log`.

```bash
# Esecuzione manuale
sudo bash scripts/cve-check.sh

# Attivare via cron settimanale (ogni lunedì alle 8:00)
(sudo crontab -l 2>/dev/null; echo '0 8 * * 1 /opt/cve-check.sh') | sudo crontab -

# Verificare l'ultimo report
sudo tail -30 /var/log/ats-cve.log

# Esempio output (VM136, 26/05/2026):
# ATS version: 9.2.13
# openssl: 3.5.5-1ubuntu3
# PCRE1 (source): 8.45
# zlib1g: 1:1.3.dfsg+really1.3.1-1ubuntu3
# liblzma5: 5.8.3-1
# libbrotli1: 1.2.0-3build1
# libcurl4t64: 8.18.0-1ubuntu2.1
# libjson-c5: 0.18+ds-3
# Kernel: 7.0.0-15-generic
# All checks passed ✅
```

### 12.6 Matrice Severità CVE — Prioritizzazione

| CVE Severity (CVSS) | Libreria | Azione | Tempistica |
|---------------------|----------|--------|-----------|
| ≥ 9.0 | ATS stesso | Upgrade immediato | Entro 24h |
| ≥ 9.0 | OpenSSL | Ricompilare ATS | Entro 48h |
| ≥ 9.0 | PCRE1 | Ricompilare PCRE1 + ATS | Entro 72h |
| 7.0-8.9 | Qualsiasi | Pianificare upgrade | Entro 1 settimana |
| 4.0-6.9 | ATS / OpenSSL | Alla prossima release LTS | Entro 1 mese |
| 4.0-6.9 | Zlib/Brotli/LZMA | apt upgrade (attended) | Automatico |
| < 4.0 | Qualsiasi | Valutare | Prossimo ciclo |

---

## 13. Rollback

```bash
# 1. Fermare il servizio
sudo systemctl stop trafficserver

# 2. Ripristinare binari dal backup pre-upgrade
sudo tar xzf /root/ats-pre-upgrade-YYYYMMDD.tar.gz -C /

# 3. Ripristinare permessi
sudo chown -R ats:ats /opt/trafficserver /etc/trafficserver

# 4. Ricaricare ldconfig
sudo ldconfig

# 5. Riavviare
sudo systemctl start trafficserver

# 6. Verificare
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip

# 7. Bloccare versioni finché non si risolve il problema
# (non applicabile a compilato, ma non aggiornare ulteriormente)
```

---

## 14. Test di Regressione

### 14.1 Esecuzione

```bash
sudo bash scripts/ats-regression-test.sh
```

Lo script esegue: test HTTP, HTTPS CONNECT, concorrenza (50 richieste), log FQDN, porta in ascolto, servizio attivo, DENY whitelist, AUTH valid/bad, Proxy-Authenticate header.

### 14.2 Output atteso

```
============================================
 ATS Proxy Regression Test
 Port: 8080 | ...
============================================

[OK] trafficserver service active
[OK] DENY httpbin.org -> 403                      403
[OK] WHITELIST google.com -> 301/200             301
[OK] AUTH missing -> 407                         407
[OK] AUTH valid -> 301/200                       301
[OK] AUTH bad credentials -> 407                 407
[OK] 403 reason phrase                           Forbidden

--- Concurrent 50 requests ---
[OK] 50x DENY httpbin.org                        50/50
[OK] 50x AUTH valid google.com                   50/50

============================================
Passed: 9  Failed: 0
============================================
```

### 14.3 Come interpretare i fallimenti

| Test | Code atteso | Se fallisce... |
|------|------------|----------------|
| DENY httpbin.org | 403 | Plugin URL filter non attivo o dominio non in deny list |
| WHITELIST google.com | 301/200 | DNS non risolve, connettività Internet assente |
| AUTH missing | 407 | Plugin auth non attivo o handler non configurato |
| AUTH valid | 301/200 | Credenziali errate o plugin auth non funzionante |
| AUTH bad | 407 | Plugin accetta credenziali che dovrebbe rifiutare |
| Concurrent 50x | 50/50 all 403 o 301 | Concorrenza degradata, verificare limiti sistema |
| 403 reason phrase | "Forbidden" | Plugin non configura reason phrase personalizzata |

---

## 15. Troubleshooting

### 15.1 Servizio non parte (lock file)

```bash
sudo systemctl stop trafficserver
sudo rm -f /var/trafficserver/manager.lock
sudo rm -f /var/trafficserver/server.lock
sudo rm -f /var/trafficserver/*.sock
sudo systemctl start trafficserver
```

### 15.2 404 Not Found dal proxy

Verificare `records.config`:

```bash
grep url_remap /etc/trafficserver/records.config
# Deve contenere: proxy.config.url_remap.remap_required INT 0
```

### 15.3 403 Access Denied

- Controllare `ip_allow.yaml` che il proprio IP/subnet sia in allow
- **Usare IP remoto per test** (localhost non testa UFW)
- Fare reload: `traffic_ctl config reload`

### 15.4 Log vuoti

```bash
# Verificare che la directory esista
sudo mkdir -p /var/log/trafficserver && sudo chown -R ats:ats /var/log/trafficserver /var/trafficserver

# Riavviare
sudo systemctl restart trafficserver

# Controllare errori
sudo grep -i "log\|error" /var/log/trafficserver/diags.log | tail -10
```

### 15.5 Deny non funziona (IP bloccato naviga ancora)

```bash
# 1. Verificare che il deny sia PRIMA dell'allow
sudo cat /etc/trafficserver/ip_allow.yaml

# 2. FARE RESTART, non solo reload!
sudo systemctl restart trafficserver

# 3. Testare da IP remoto, non da localhost
curl -x http://PROXY_IP:8080 http://httpbin.org/ip
```

### 15.6 Connection refused

```bash
# Verificare che la porta sia in ascolto
sudo ss -tlnp | grep 8080

# Se vuoto, il servizio non è partito
sudo systemctl status trafficserver
sudo journalctl -u trafficserver -n 30
```

### 15.7 traffic_server zombie dopo kill

```bash
sudo pkill -9 traffic_server traffic_manager
sudo rm -f /var/trafficserver/manager.lock
sudo rm -f /var/trafficserver/server.lock
sudo systemctl start trafficserver
```

### 15.8 libpcre.so.1: cannot open shared object file (EACCES) — solo 26.04

**Causa**: AppArmor blocca l'accesso a `/usr/local/pcre/lib/libpcre.so.1`.

```bash
sudo aa-remove-unknown  # rimuovi tutti i profili AppArmor non in /etc/apparmor.d/
sudo aa-status | grep traffic  # verifica che traffic_server non sia più in enforce
sudo systemctl restart trafficserver
```

### 15.9 Failed to set up mount namespacing: /run/trafficserver: No such file

**Causa**: `ReadWritePaths=/run/trafficserver` punta a una directory che non esiste quando si usa `ProtectSystem=strict`.

```bash
sudo mkdir -p /run/trafficserver
# OPPURE modificare il file systemd unit: usare RuntimeDirectory=trafficserver
```

### 15.10 ATS risponde 403 a tutte le richieste (anche valide)

**Causa**: File di config con permessi/ownership sbagliati — ATS (utente `ats`) non può leggerli.

```bash
sudo chown -R ats:ats /etc/trafficserver/
sudo chmod 640 /etc/trafficserver/*.yaml /etc/trafficserver/*.config /etc/trafficserver/*.conf
sudo systemctl restart trafficserver
```

### 15.11 Deny dominio non funziona, restituisce 200 invece di 403

**Cause possibili**:
1. Plugin non caricato → `sudo grep 'ats_proxy_filter' /var/log/trafficserver/diags.log | tail -5`
2. Config file non leggibile da `ats` → `sudo -u ats cat /etc/trafficserver/plugin.config`
3. OS_DNS hook non scatta (DNS cached) → testare con dominio mai visitato
4. Admin IP bypass attivo per l'IP del client

```bash
# Soluzione:
# 1. Verifica plugin caricato
sudo grep 'ats_proxy_filter' /var/log/trafficserver/diags.log | tail -5

# 2. Elimina cache DNS
sudo rm -f /var/trafficserver/host.db
sudo systemctl restart trafficserver

# 3. Test da IP non-admin
curl -x http://PROXY:8080 http://httpbin.org/ip -s -o /dev/null -w '%{http_code}\n'
# Atteso: 403
```

### 15.12 DNS non risolve su Ubuntu 26.04

**Causa**: systemd-resolved su 26.04 (127.0.0.53) potrebbe non essere configurato in ATS.

```bash
# In records.config:
CONFIG proxy.config.dns.search_default_domains INT 0
CONFIG proxy.config.dns.resolv_conf STRING /etc/resolv.conf
CONFIG proxy.config.dns.nameservers STRING 127.0.0.53
```

---

## 16. Esempi Reali dalle VM di Test

### 16.1 Log dopo richiesta HTTP

```
127.0.0.1 - [26/May/2026:14:04:46 -0000] "GET http://httpbin.org/ip HTTP/1.1" 200 41 httpbin.org httpbin.org
```

Campi: IP client `127.0.0.1`, timestamp, request completa, status 200, 41 bytes, FQDN richiesto `httpbin.org`, hostname backend `httpbin.org`.

### 16.2 Log dopo CONNECT HTTPS

```
127.0.0.1 - [26/May/2026:14:04:48 -0000] "CONNECT httpbin.org:443/ HTTP/1.1" 200 4748 httpbin.org:443 httpbin.org
```

Il CONNECT tunnel è loggato come richiesta separata. I dati dentro al tunnel non sono visibili (cifrati end-to-end).

### 16.3 Test funzionale da remoto

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

### 16.4 10 richieste concorrenti

```bash
$ for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " -x http://192.168.89.27:8080 http://httpbin.org/ip & done; wait
200 200 200 200 200 200 200 200 200 200
```

Tutte 200 — il proxy gestisce concorrenza senza errori.

---

## 17. Modalità Debug

### 17.1 Attivazione

```bash
# 1. Modificare records.config
sudo sed -i 's/CONFIG proxy.config.diags.debug.enabled INT 0/CONFIG proxy.config.diags.debug.enabled INT 1/' /etc/trafficserver/records.config

# 2. Aumentare verbosità diags (opzionale)
echo 'CONFIG proxy.config.diags.debug.tags STRING http|dns|hostdb' | sudo tee -a /etc/trafficserver/records.config

# 3. Restart (necessario per records.config)
sudo systemctl restart trafficserver

# 4. Monitorare output
sudo tail -f /var/log/trafficserver/diags.log
sudo journalctl -u trafficserver -f
```

### 17.2 Tag di debug

| Tag | Cosa traccia |
|-----|-------------|
| `http` | Transazioni HTTP (header, status, errori) |
| `dns` | Risoluzione DNS, cache, timeout |
| `hostdb` | Host database, round-robin backend |
| `cache` | Cache hit/miss, write, eviction |
| `acl` | Valutazione ip_allow.yaml |
| `socket` | Connessioni TCP, accept/connect/close |

### 17.3 Disattivazione

```bash
sudo sed -i 's/CONFIG proxy.config.diags.debug.enabled INT 1/CONFIG proxy.config.diags.debug.enabled INT 0/' /etc/trafficserver/records.config
sudo sed -i '/proxy.config.diags.debug.tags/d' /etc/trafficserver/records.config
sudo systemctl restart trafficserver
```

### 17.4 Catturare traffico HTTP raw (tcpdump)

```bash
# Catturare traffico sulla porta proxy (debug estremo)
sudo tcpdump -i any -A -s 0 port 8080 -w /tmp/ats-debug.pcap

# Analizzare con:
sudo tcpdump -r /tmp/ats-debug.pcap -A | less
```

---

## 18. Compliance GDPR — Gestione Dati

### 18.1 ⚠️ Avvertenza legale

L'IP del client è considerato **dato personale** ai sensi del GDPR (Art. 4.1). Il log `audit.log` contiene dati personali. Il titolare del trattamento deve:

1. **Definire la base giuridica** del trattamento (Art. 6 GDPR)
2. **Fornire informativa** agli utenti (Art. 13-14 GDPR)
3. **Registrare il trattamento** nel registro ex Art. 30
4. **Valutare DPIA** se richiesto (Art. 35)

### 18.2 Retention policy configurata

| Dato | File | Retention |
|------|------|-----------|
| Log accesso proxy | `audit.log` | Rolling 24h, auto-delete a 10000 MB |
| Log di sistema | journald | 30 giorni |
| Log diagnostici | `diags.log` | Rolling automatico |
| Configurazioni | etckeeper git | Illimitato |

### 18.3 Diritto di accesso (GDPR Art. 15)

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

sudo grep "^$IP " /var/log/trafficserver/audit.log* >> "$OUTPUT" 2>/dev/null

echo "" >> "$OUTPUT"
echo "=== FINE RAPPORTO ===" >> "$OUTPUT"
echo "Rapporto generato da: $(whoami)" >> "$OUTPUT"

cat "$OUTPUT"
```

### 18.4 Diritto di cancellazione (GDPR Art. 17)

```bash
#!/bin/bash
# Script: gdpr-delete.sh
# Uso: sudo bash gdpr-delete.sh 192.168.89.55

IP="$1"
LOGDIR="/var/log/trafficserver"
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

### 18.5 Anonimizzazione IP (GDPR by design)

Per ridurre il rischio GDPR, valutare l'anonimizzazione degli IP nei log prima della scrittura:

```yaml
# In logging.yaml, sostituire %<chi> con hash SHA256 dell'IP
# Richiede plugin custom o script di post-processing.

# Alternativa: troncare ultimo ottetto (pseudo-anonimizzazione)
# Da: 192.168.89.55  →  A: 192.168.89.0
# Via script cron:
# sudo sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+ /\1.0 /' audit.log > audit-anon.log
```

### 18.6 Template informativa (estratto)

> *"L'accesso a Internet tramite il proxy aziendale è soggetto a registrazione. Vengono raccolti: indirizzo IP del dispositivo, nome host dei siti visitati (non gli URL completi), data e ora della richiesta. Il trattamento è effettuato per finalità di sicurezza della rete (legittimo interesse del titolare) e ottemperanza agli obblighi di legge (Art. 132 D.Lgs 196/2003). I dati sono conservati per 6 mesi e accessibili solo al personale autorizzato. Per esercitare i diritti di cui agli Art. 15-22 GDPR, contattare il DPO all'indirizzo [email]."*

---

## 19. Incident Response

### 19.1 Classificazione incidenti

| Livello | Descrizione | Esempio |
|---------|-------------|---------|
| P1 — Critico | Proxy non disponibile o violazione confermata | Servizio down, data breach |
| P2 — Alto | Degradazione funzionale o tentativo attacco in corso | Abuso proxy, scansione massiva |
| P3 — Medio | Anomalia senza impatto immediato | Errori intermittenti, log warning |
| P4 — Basso | Evento informativo | Tentativo singolo bloccato da ACL |

### 19.2 Procedura P1/P2 — Incident Response Flow

```bash
# === FASE 1: DETECTION ===
# Identificare l'anomalia
sudo tail -100 /var/log/trafficserver/audit.log | grep -c " 403 "
sudo journalctl -u trafficserver -p err --since "1 hour ago"
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# === FASE 2: ANALYSIS ===
# Determinare IP malevolo
sudo grep " 403 " /var/log/trafficserver/audit.log | cut -d' ' -f1 | sort | uniq -c | sort -rn | head -20

# Identificare pattern (es. brute force, scan)
sudo grep "192.168.89.99" /var/log/trafficserver/audit.log | cut -d' ' -f6 | sort | uniq -c | sort -rn

# === FASE 3: CONTAINMENT ===
# Blocco immediato IP malevolo
sudo cp /etc/trafficserver/ip_allow.yaml /etc/trafficserver/ip_allow.yaml.bak.$(date +%s)
# Inserire deny PRIMA degli allow usando sed:
sudo sed -i '3i\  - apply: in\n    ip_addrs: 192.168.89.99/32\n    action: deny\n    method: ALL' /etc/trafficserver/ip_allow.yaml
sudo systemctl restart trafficserver

# Alternativa: blocco via UFW (più drastico)
sudo ufw deny from 192.168.89.99 to any port 8080 proto tcp

# === FASE 4: EVIDENCE PRESERVATION ===
# Backup immediato log e config
sudo tar czf /root/incident-$(date +%Y%m%d-%H%M).tar.gz \
  /var/log/trafficserver/ \
  /etc/trafficserver/ \
  /var/log/auth.log
```

### 19.3 Template notifica NIS2 (early warning 24h)

```
A: [ACN - CSIRT Italia / autorità competente NIS2]
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
   - Descrizione sintetica: [Cosa è successo, impatto]

3. IMPATTO
   - Servizi impattati: [ATS Proxy Enterprise]
   - Utenti impattati: [Numero]
   - Dati eventualmente compromessi: [SI/NO, descrizione]
   - Impatto transfrontaliero: [SI/NO, specificare paesi]

4. AZIONI INTRAPRESE
   - [Misure di containment]
   - [Soggetti informati]
```

### 19.4 Template notifica GDPR (Garante Privacy, Art. 33)

```
A: Garante per la Protezione dei Dati Personali
Oggetto: Notifica violazione dati personali — Art. 33 GDPR

1. NATURA DELLA VIOLAZIONE
   - Categorie dati: [es. Indirizzi IP, log di navigazione]
   - Numero interessati: [approssimativo]
   - Volume dati: [approssimativo]
   - Categorie interessati: [es. Dipendenti, utenti]

2. CONSEGUENZE PROBABILI
   - [Valutazione rischio per diritti e libertà]

3. MISURE ADOTTATE
   - [Containment, ripristino, mitigazione]

4. REFERENTE
   - DPO: [Nome, contatti]
```

---

## 20. Checklist Verifica Mensile

```bash
#!/bin/bash
# Script: ats-monthly-check.sh

echo "=== Monthly ATS Health Check $(date) ==="
echo ""

# 0. Stato servizio
systemctl is-active trafficserver || echo "⚠️  ATS non attivo!"

# 1. Versioni
echo "ATS: $(/opt/trafficserver/bin/traffic_server -V 2>&1 | head -1)"
echo "OpenSSL: $(openssl version)"
echo "Kernel: $(uname -r)"

# 2. Aggiornamenti disponibili
echo "Aggiornamenti security:"
apt list --upgradable 2>/dev/null | grep -i security || echo "  Nessuno"

# 3. Log errori recenti
echo "Errori ultimi 7 giorni:"
sudo journalctl -u trafficserver --since "7 days ago" -p err --no-pager | tail -5

# 4. Spazio disco
echo "Spazio disco:"
df -h / /opt/trafficserver/var/trafficserver/cache

# 5. Fail2ban
echo "fail2ban SSH:"
sudo fail2ban-client status sshd 2>/dev/null | grep -E "Banned|Total"

# 6. Verifica baseline
curl -s -o /dev/null -w "Proxy test: %{http_code}\n" -x http://localhost:8080 http://httpbin.org/ip
```

---

## 21. Comandi Diagnostica Rapida

```bash
# Plugin caricato?
sudo grep 'loaded [0-9]' /var/log/trafficserver/diags.log | tail -3

# Errori recenti
sudo grep -i 'error\|fail\|alert' /var/log/trafficserver/diags.log | tail -10

# Config valida?
sudo /opt/trafficserver/bin/traffic_server -C verify_config

# Librerie mancanti?
ldd /opt/trafficserver/bin/traffic_server | grep 'not found'

# Porta in ascolto?
sudo ss -tlnp | grep traffic

# Processi attivi?
ps aux | grep traffic

# Ultime richieste loggate?
sudo tail -5 /var/log/trafficserver/audit.log

# Metriche in tempo reale?
/opt/trafficserver/bin/traffic_top

# Report diagnostico compatto pre/post upgrade
sudo bash scripts/ats-version-report.sh
```

`scripts/ats-version-report.sh` è read-only: stampa OS, versione ATS, stato servizio, hash plugin, config essenziale, porte e ultimi errori. Usarlo prima e dopo upgrade, incidenti o rollback.

---

## Appendice: Procedura Completa Upgrade ATS 9.2.x a 10.x

### BOZZA NON VALIDATA — solo promemoria tecnico

Questa procedura è un promemoria tecnico, non un runbook operativo. **Non usarla in produzione** finché build ATS 10.x, ricompilazione plugin e batteria test non sono completate su VM reale.

```bash
# 1. Backup
sudo systemctl stop trafficserver
sudo cp -a /opt/trafficserver /opt/trafficserver.bak-9.2.13
sudo cp -a /etc/trafficserver /etc/trafficserver.bak-9.2.13

# 2. Download e build (CMake)
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-10.1.2.tar.bz2
tar -xjf trafficserver-10.1.2.tar.bz2 && cd trafficserver-10.1.2
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/opt/trafficserver \
  -DCMAKE_BUILD_TYPE=Release \
  -DPCRE_LIBRARY=/usr/local/pcre/lib/libpcre.so \
  -DPCRE_INCLUDE_DIR=/usr/local/pcre/include
make -j$(nproc)
sudo make install

# 3. Ricompilare plugin v2.1 contro nuove headers
cd /tmp/trafficserver-10.1.2
cp /opt/ats-proxy-enterprise/src/ats_proxy_filter_v21.c .
gcc -fPIC -shared -I. -I./include -o /tmp/ats_proxy_filter_v21.so \
  ats_proxy_filter_v21.c

# 4. Riavviare e testare
sudo cp /tmp/ats_proxy_filter_v21.so /opt/trafficserver/lib/modules/ats_proxy_filter.so
sudo ldconfig
sudo systemctl start trafficserver
```

⚠️ **ATTENZIONE**: La procedura di upgrade a 10.x NON è stata testata su VM reale.
- API verificate compatibili.
- Build system cambiato (CMake).
- Config format potrebbe essere cambiato (records.config → YAML?).
- Plugin da ricompilare con sorgente `src/ats_proxy_filter_v21.c` (versionato in repo).

**Stato sorgente**: il file `src/ats_proxy_filter_v21.c` è stato ricostruito e versionato il 2026-05-25. Va compilato e validato su ATS 9.2.13 e poi ATS 10.x.

**Raccomandazione**: trattare ATS 10.x come attività separata di laboratorio. L'unica baseline validata per produzione resta ATS 9.2.13.

---

*Guida basata su ATS 9.2.13 testato su VM135 (24.04) e VM136 (26.04)*
*Fonti consolidate: GUIDA_OPERATIVA_ATS_v1.0, GUIDA_UPGRADE_CVE_v1.0, GUIDA_LOG_SIEM_v1.0, ats-troubleshooting skill*
*Script: `scripts/cve-check.sh`, `scripts/ats-hardening-check.sh`, `scripts/ats-regression-test.sh`*
