# ATS Proxy Enterprise — Guida Log a SIEM

## Forwarding audit log a syslog, ELK e altri collector

**Versione 1.0 — 24 Maggio 2026 — Testato su VM 130 e VM 134**

---

## 1. Architettura

ATS scrive `audit.log` su disco. Per centralizzare i log:

```
/opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
    │
    ├──▶ rsyslog (imfile) ──▶ SIEM via TCP/UDP syslog (qualsiasi)
    ├──▶ Filebeat ──▶ Logstash ──▶ Elasticsearch ──▶ Kibana (ELK)
    ├──▶ Filebeat ──▶ Elasticsearch (direct)
    └──▶ Qualsiasi agente che legga file di testo
```

**Nessuna modifica ad ATS richiesta.** Si aggancia solo al file system.

---

## 2. Formato log ATS

```
192.168.89.27 - [24/May/2026:23:18:37 -0000] "HEAD http://google.com/ HTTP/1.1" 301 0 google.com google.com
192.168.89.27 - [24/May/2026:23:18:37 -0000] "HEAD http://wikipedia.org/ HTTP/1.1" 407 0 wikipedia.org -
```

| Campo | Posizione | Esempio |
|-------|-----------|---------|
| IP client | 1 | `192.168.89.27` |
| Timestamp | 2-5 (tra `[` `]`) | `24/May/2026:23:18:37 -0000` |
| Request line | 6 (tra `"`) | `HEAD http://google.com/ HTTP/1.1` |
| Status code | 7 | `200`, `301`, `403`, `407` |
| Content length | 8 | `0`, `1256` |
| FQDN richiesto | 9 | `google.com`, `wikipedia.org` |
| Backend hostname | 10 | `google.com`, `-` (per 403/407) |

---

## 3. Metodo A — rsyslog (universale)

### 3.1 Permessi

ATS scrive `audit.log` come utente `ats:ats` con permessi `644`. rsyslog gira come `syslog`. Occorre:

```bash
# Rendi il file leggibile da syslog
sudo chmod o+r /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# OPPURE aggiungi syslog al gruppo ats
sudo usermod -a -G ats syslog
sudo chmod g+r /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
```

### 3.2 Configurazione imfile

```bash
sudo tee /etc/rsyslog.d/99-ats-audit.conf > /dev/null << 'EOF'
module(load="imfile")

input(type="imfile"
      File="/opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log"
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

### 3.3 Test

```bash
# Genera traffico
curl -s -o /dev/null -x http://127.0.0.1:8080 http://httpbin.org/ip

# Verifica sul server locale
sudo tail -3 /var/log/ats-remote.log

# Verifica su SIEM remoto (es. tcpdump sul SIEM)
# tcpdump -i any port 514 -A | grep ats-audit
```

---

## 4. Metodo B — Filebeat → Elasticsearch (ELK)

### 4.1 Installa Filebeat

```bash
# Ubuntu 24.04 e 26.04
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/beats/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt update && sudo apt install -y filebeat
```

### 4.2 Configurazione

```yaml
# /etc/filebeat/filebeat.yml
filebeat.inputs:
  - type: filestream
    enabled: true
    paths:
      - /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
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

# Per inviare a Logstash invece:
# output.logstash:
#   hosts: ["logstash.example.com:5044"]
```

### 4.3 Avvio

```bash
sudo systemctl enable --now filebeat
sudo filebeat test output
sudo filebeat setup -e
```

---

## 5. Metodo C — Log JSON da ATS (avanzato)

Se ATS supporta output JSON in logging.yaml, modificare:

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

**Nota**: Da verificare se ATS 9.2.13 supporta virgolette e sintassi JSON nel format string. Se non supportato, usare Logstash per il parsing.

---

## 6. Parsing con Logstash (per formato plain-text ATS)

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

---

## 7. Tabella riepilogativa metodi

| Metodo | Vantaggi | Svantaggi | Ideale per |
|--------|----------|-----------|-----------|
| **rsyslog** | Già installato, zero agent aggiuntivi | Parsing manuale, no retention built-in | SIEM generici, invio a syslog collector |
| **Filebeat + ES** | Installazione semplice, parsing automatico | Richiede ES cluster | ELK stack già esistente |
| **Filebeat + Logstash** | Parsing flessibile con grok, enrichment | Più componenti da gestire | Pipeline ELK complesse |
| **Log JSON nativo** | Zero parsing, ingest immediato | Supporto da verificare in ATS 9.2.13 | Ambienti con ES che accettano JSON diretto |

---

## 8. Checklist verifica

```bash
# 1. Il file audit.log esiste ed è leggibile
sudo ls -la /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# 2. rsyslog/filebeat è attivo
systemctl is-active rsyslog filebeat

# 3. Genera traffico di test
curl -s -o /dev/null -x http://127.0.0.1:8080 http://httpbin.org/ip

# 4. Verifica che il log contenga la richiesta
sudo tail -3 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# 5. Verifica arrivo su SIEM (lato collector)
# tcpdump -i any port 514 -A | grep httpbin.org
```

---

*Guida basata su rsyslog 8.2512 e ATS 9.2.13 testati su VM 134 (Ubuntu 26.04)*
