# ATS Proxy Enterprise — Guida Completa

## Runbook copia-incolla: da zero a produzione

**Versione 1.0 — 25 Maggio 2026**  
Copre: Ubuntu 24.04 LTS (Noble) e 26.04 LTS (Resolute Raccoon)

---

## Indice

1. [Architettura](#1-architettura)
2. [Preparazione sistema](#2-preparazione-sistema)
3. [Compilazione ATS 9.2.13](#3-compilazione-ats-9213)
4. [Configurazione base](#4-configurazione-base)
5. [Servizio systemd](#5-servizio-systemd)
6. [Verifica funzionamento](#6-verifica-funzionamento)
7. [Plugin URL Filtering + Auth v2.1](#7-plugin-url-filtering--auth-v21)
8. [Hardening sicurezza](#8-hardening-sicurezza)
9. [Health check automatico](#9-health-check-automatico)
10. [Fail2ban proxy](#10-fail2ban-proxy)
11. [Rate limiting](#11-rate-limiting)
12. [TLS frontend (opzionale)](#12-tls-frontend-opzionale)
13. [AppArmor (opzionale — richiede tuning manuale)](#13-apparmor-opzionale--richiede-tuning-manuale)
14. [Troubleshooting](#14-troubleshooting)
15. [Comandi manutenzione](#15-comandi-manutenzione)

---

## 1. Architettura

```
Client → UFW:8080 → ip_allow.yaml → ats_proxy_filter.so
                                        │
                                   ┌────┼────┐
                                   ▼    ▼    ▼
                                 Admin DENY WHITELIST
                                bypass 403   pass
                                            │
                                       ┌────┴────┐
                                       ▼         ▼
                                    No auth   Valid auth
                                      407       CONTINUE
```

**Porte**: 8080 (HTTP), 8443 (TLS opzionale)  
**Plugin**: `ats_proxy_filter.so` v2.1 — hook OS_DNS, config-based  
**Credenziali**: Basic auth via `Proxy-Authorization` header  
**Log**: `/var/lib/trafficserver/log/trafficserver/audit.log` → rsyslog/ELK

---

## 2. Preparazione sistema

### 2.1 Ubuntu 24.04 LTS

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential gcc g++ make libtool autoconf automake \
  pkg-config python3-dev libssl-dev libpcre3-dev libpcre2-dev zlib1g-dev \
  libcap-dev libhwloc-dev libncurses5-dev libxml2-dev libjson-c-dev \
  libcurl4-openssl-dev libunwind-dev git wget curl tar gzip bzip2
```

### 2.2 Ubuntu 26.04 LTS

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential gcc g++ make libtool autoconf automake \
  pkg-config python3-dev libssl-dev libpcre2-dev zlib1g-dev libcap-dev \
  libhwloc-dev libncurses-dev libxml2-dev libjson-c-dev \
  libcurl4-openssl-dev libunwind-dev git wget curl tar gzip bzip2
```

### 2.3 Creazione utente dedicato

```bash
sudo groupadd --system ats
sudo useradd --system --gid ats --home-dir /opt/trafficserver --shell /usr/sbin/nologin ats
```

---

## 3. Compilazione ATS 9.2.13

### 3.1 Download e verifica

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2.sha256
sha256sum -c trafficserver-9.2.13.tar.bz2.sha256
tar -xjf trafficserver-9.2.13.tar.bz2
cd trafficserver-9.2.13
autoreconf -if
```

### 3.2 PCRE1 (solo Ubuntu 26.04)

```bash
# Solo su 26.04: libpcre3-dev non disponibile
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz
tar xzf pcre-8.45.tar.gz && cd pcre-8.45
./configure --prefix=/usr/local/pcre --enable-utf8 --enable-unicode-properties
make -j$(nproc) && sudo make install
# Registrare in ldconfig
echo '/usr/local/pcre/lib' | sudo tee /etc/ld.so.conf.d/pcre.conf
sudo ldconfig
```

### 3.3 Configure

**Ubuntu 24.04**:
```bash
cd /tmp/trafficserver-9.2.13
./configure --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --enable-pcre \
  --disable-tests --disable-examples --disable-maintainer-mode
```

**Ubuntu 26.04**:
```bash
cd /tmp/trafficserver-9.2.13
./configure --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --with-pcre=/usr/local/pcre \
  --disable-tests --disable-examples --disable-maintainer-mode
```

### 3.4 Compilazione e installazione

```bash
make -j$(nproc)
sudo make install
echo "/opt/trafficserver/lib" | sudo tee /etc/ld.so.conf.d/trafficserver.conf
sudo ldconfig
```

---

## 4. Configurazione base

```bash
sudo mkdir -p /run/trafficserver /var/log/trafficserver /var/lib/trafficserver/cache
sudo mkdir -p /var/lib/trafficserver/log/trafficserver
sudo chown -R ats:ats /opt/trafficserver /etc/trafficserver /var/lib/trafficserver /run/trafficserver /var/log/trafficserver
```

### 4.1 records.config

```bash
sudo tee /etc/trafficserver/records.config > /dev/null << 'EOF'
CONFIG proxy.config.http.server_ports STRING 8080
CONFIG proxy.config.proxy_name STRING proxy-enterprise-01
CONFIG proxy.config.task_threads INT -1
CONFIG proxy.config.net.connections_throttle INT 30000
CONFIG proxy.config.net.max_connections_in INT 30000
CONFIG proxy.config.log.logging_enabled INT 3
CONFIG proxy.config.log.max_space_mb_for_logs INT 10000
CONFIG proxy.config.log.rolling_enabled INT 1
CONFIG proxy.config.log.rolling_interval_sec INT 86400
CONFIG proxy.config.log.auto_delete_rolled_files INT 1
CONFIG proxy.config.dns.nameservers STRING NULL
CONFIG proxy.config.dns.resolv_conf STRING /etc/resolv.conf
CONFIG proxy.config.dns.lookup_timeout INT 30
CONFIG proxy.config.http.insert_client_ip INT 1
CONFIG proxy.config.cache.ram_cache.size INT 1073741824
CONFIG proxy.config.http.push_method_enabled INT 0
CONFIG proxy.config.diags.debug.enabled INT 0
CONFIG proxy.config.url_remap.remap_required INT 0
CONFIG proxy.config.reverse_proxy.enabled INT 0
CONFIG proxy.config.http.flow_control.enabled INT 1
CONFIG proxy.config.http.per_server.connection.max INT 100
EOF
```

### 4.2 ip_allow.yaml

```bash
sudo tee /etc/trafficserver/ip_allow.yaml > /dev/null << 'EOF'
---
ip_allow:
  - apply: in
    ip_addrs: 127.0.0.1
    action: allow
    method: ALL
  - apply: in
    ip_addrs: ::1
    action: allow
    method: ALL
  - apply: in
    ip_addrs: 192.168.89.0/24
    action: allow
    method: GET|POST|CONNECT|HEAD|PUT|DELETE|OPTIONS
  - apply: in
    ip_addrs: 0.0.0.0-255.255.255.255
    action: deny
    method: ALL
EOF
```

> **Sostituire** `192.168.89.0/24` con la subnet reale. Mettere `deny /32` PRIMA di `allow /24` per bloccare IP specifici.

### 4.3 logging.yaml

```bash
sudo tee /etc/trafficserver/logging.yaml > /dev/null << 'EOF'
---
logging:
  formats:
    - name: audit
      format: '%<chi> %<caun> [%<cqtn>] "%<cqtx>" %<pssc> %<pscl> %<{Host}cqh> %<shn>'
      interval: 1
  logs:
    - filename: audit
      format: audit
      mode: ascii
      rolling_enabled: 1
      rolling_interval_sec: 86400
EOF
```

### 4.4 Permessi finali

```bash
sudo touch /etc/trafficserver/remap.config /etc/trafficserver/storage.config
echo '/var/lib/trafficserver/cache 10G' | sudo tee /etc/trafficserver/storage.config
sudo chown ats:ats /etc/trafficserver/*
sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
```

---

## 5. Servizio systemd

```bash
sudo tee /etc/systemd/system/trafficserver.service > /dev/null << 'EOF'
[Unit]
Description=Apache Traffic Server
Documentation=https://trafficserver.apache.org/
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
User=ats
Group=ats
RuntimeDirectory=trafficserver
ExecStart=/opt/trafficserver/bin/trafficserver start
ExecStop=/opt/trafficserver/bin/trafficserver stop
ExecReload=/opt/trafficserver/bin/trafficserver restart
KillMode=control-group
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
LimitNPROC=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=trafficserver
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/trafficserver /var/lib/trafficserver /var/log/trafficserver
ReadOnlyPaths=/opt/trafficserver
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true
MemoryHigh=2G
MemoryMax=3G
CPUQuota=400%

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now trafficserver
```

---

## 6. Verifica funzionamento

```bash
# Porta in ascolto
ss -tlnp | grep 8080

# Test proxy
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://localhost:8080 http://httpbin.org/ip
# Atteso: 200

# HTTPS CONNECT
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://localhost:8080 https://httpbin.org/ip
# Atteso: 200

# 10 richieste concorrenti
for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' --connect-timeout 5 -x http://localhost:8080 http://httpbin.org/ip & done; wait; echo ''
# Atteso: 200 200 200 ...

# 50 richieste concorrenti (test avanzato)
for i in $(seq 1 50); do curl -s -o /dev/null -w '%{http_code} ' --connect-timeout 5 -x http://localhost:8080 http://httpbin.org/ip & done; wait; echo ''
# Atteso: 403 403 403 ... (con plugin v2.1 attivo)
# Risultato test VM134: 50×403 con plugin v2.1, nessun crash
# Risultato test VM134: 50×301 con auth valida, nessun crash

# Verifica sintassi config
sudo /opt/trafficserver/bin/traffic_server -C verify_config
```

---

## 7. Plugin URL Filtering + Auth v2.1

### 7.1 Copia il plugin

```bash
# Il plugin è compilato da ats_proxy_filter_v21.c
sudo cp ats_proxy_filter.so /opt/trafficserver/lib/modules/
sudo chown ats:ats /opt/trafficserver/lib/modules/ats_proxy_filter.so
```

### 7.2 Config file (`/etc/trafficserver/ats_proxy_filter.conf`)

```bash
sudo tee /etc/trafficserver/ats_proxy_filter.conf > /dev/null << 'EOF'
# Admin IP — bypassano tutte le regole. Editare e restart per applicare.
ADMIN 192.168.89.10
ADMIN 192.168.89.27

# DENY list — blocco immediato (403). Supporta regex con .*
DENY httpbin.org
DENY bad.com
DENY malware.net
DENY .*\.ru$

# WHITELIST — consentito senza autenticazione
WHITELIST google.com
WHITELIST github.com
WHITELIST ubuntu.com
WHITELIST example.com

# Utenti per autenticazione Basic Proxy
USER admin proxy2026
USER user1 pass123
USER operator op3rat0r
EOF
```

### 7.3 plugin.config

```bash
sudo tee /etc/trafficserver/plugin.config > /dev/null << 'EOF'
ats_proxy_filter.so
EOF

sudo chown ats:ats /etc/trafficserver/plugin.config /etc/trafficserver/ats_proxy_filter.conf
sudo systemctl restart trafficserver
```

### 7.4 Test

```bash
# DENY → 403
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 -x http://localhost:8080 http://httpbin.org/ip

# WHITELIST → 200/301
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 -x http://localhost:8080 http://google.com

# AUTH senza credenziali → 407
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 -x http://localhost:8080 http://reddit.com

# AUTH con credenziali valide → 200/301
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 -x http://localhost:8080 --proxy-user admin:proxy2026 http://reddit.com

# AUTH con credenziali errate → 407
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 -x http://localhost:8080 --proxy-user wrong:wrong http://reddit.com

# Admin IP bypass (da IP in ADMIN list) → 200
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 -x http://localhost:8080 http://httpbin.org/ip
```

### 7.5 Come funziona l'auth dal browser

Quando il proxy risponde 407, il browser mostra automaticamente una finestra di login. L'utente inserisce username e password configurati nel file `ats_proxy_filter.conf`.

### 7.6 Modificare regole a caldo

```bash
# Editare il config file
sudo nano /etc/trafficserver/ats_proxy_filter.conf

# Riavviare per applicare
sudo systemctl restart trafficserver
```

---

## 8. Hardening sicurezza

### 8.1 Firewall UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp comment 'ATS-proxy'
echo 'y' | sudo ufw enable
```

### 8.2 SSH hardening

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
sudo sshd -t && sudo systemctl restart ssh
```

⚠️ **Prima di eseguire**: assicurarsi di avere una chiave SSH funzionante configurata.

### 8.3 Sysctl kernel hardening

```bash
sudo tee /etc/sysctl.d/99-ats-hardening.conf > /dev/null << 'EOF'
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_rfc1337=1
net.core.somaxconn=4096
net.netfilter.nf_conntrack_max=65536
kernel.core_pattern=|/bin/false
kernel.sysrq=0
EOF
sudo sysctl -p /etc/sysctl.d/99-ats-hardening.conf
```

### 8.4 etckeeper

```bash
sudo apt install -y etckeeper
sudo etckeeper init
sudo etckeeper commit "Configurazione iniziale ATS proxy enterprise"
```

### 8.5 unattended-upgrades

```bash
sudo apt install -y unattended-upgrades
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
sudo systemctl enable --now unattended-upgrades
```

---

## 9. Health check automatico

```bash
# Script
sudo tee /opt/ats_health.sh > /dev/null << 'HEOF'
#!/bin/bash
PROXY="http://127.0.0.1:8080"
LOG="/var/log/ats-health.log"
HTTP=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x $PROXY http://httpbin.org/ip 2>/dev/null)
STATUS=$(systemctl is-active trafficserver)
echo "[$(date -Is)] ATS=$STATUS HTTP=$HTTP" >> $LOG
if [ "$HTTP" != "200" ] && [ "$HTTP" != "403" ] && [ "$HTTP" != "407" ]; then
  echo "[$(date -Is)] ALERT: proxy unhealthy, restarting" >> $LOG
  /bin/systemctl restart trafficserver
fi
HEOF

sudo chmod +x /opt/ats_health.sh
sudo touch /var/log/ats-health.log
sudo chmod 666 /var/log/ats-health.log

# Cron ogni 60 secondi
(sudo crontab -l 2>/dev/null; echo '* * * * * /opt/ats_health.sh') | sudo crontab -
```

---

## 10. Fail2ban proxy

```bash
sudo apt install -y fail2ban

# Filtro per il plugin ATS
sudo tee /etc/fail2ban/filter.d/ats-proxy.conf > /dev/null << 'FEOF'
[Definition]
failregex = \[ats_proxy_filter\] AUTH FAIL .* from <HOST>
ignoreregex =
FEOF

# Jail SSH + ATS proxy
sudo tee /etc/fail2ban/jail.local > /dev/null << 'JEOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
findtime = 3600

[ats-proxy]
enabled = true
port = 8080
filter = ats-proxy
logpath = /var/lib/trafficserver/log/trafficserver/diags.log
maxretry = 5
findtime = 300
bantime = 3600
JEOF

sudo systemctl enable --now fail2ban
sudo fail2ban-client status ats-proxy
```

---

## 11. Rate limiting

Già incluso in `records.config` (Sezione 4.1):

```
CONFIG proxy.config.http.flow_control.enabled INT 1
CONFIG proxy.config.http.per_server.connection.max INT 100
```

Per modificare i limiti:

```bash
# Modificare il valore e riavviare
sudo sed -i 's/per_server.connection.max INT 100/per_server.connection.max INT 200/' /etc/trafficserver/records.config
sudo systemctl restart trafficserver
```

---

## 12. TLS frontend (opzionale)

Aggiunge la porta 8443 con TLS 1.3. La porta 8080 HTTP resta attiva.

### 12.1 Generare certificato self-signed

```bash
sudo mkdir -p /etc/trafficserver/certs
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/trafficserver/certs/proxy.key \
  -out /etc/trafficserver/certs/proxy.crt \
  -subj '/CN=proxy-enterprise'
sudo chown -R ats:ats /etc/trafficserver/certs
```

### 12.2 Usare certificato aziendale

```bash
# Sostituire i file generati con quelli aziendali
sudo cp aziendale.crt /etc/trafficserver/certs/proxy.crt
sudo cp aziendale.key /etc/trafficserver/certs/proxy.key
sudo chown ats:ats /etc/trafficserver/certs/*
```

### 12.3 Configurare ATS

```bash
# ssl_multicert.config
sudo tee /etc/trafficserver/ssl_multicert.config > /dev/null << 'EOF'
dest_ip=* ssl_cert_name=/etc/trafficserver/certs/proxy.crt ssl_key_name=/etc/trafficserver/certs/proxy.key
EOF

# Aggiungere porta 8443
sudo sed -i 's/server_ports STRING 8080/server_ports STRING 8080 8443:ssl/' /etc/trafficserver/records.config

# Cipher suite sicura
sudo tee -a /etc/trafficserver/records.config > /dev/null << 'EOF'
CONFIG proxy.config.ssl.TLSv1_3 INT 1
CONFIG proxy.config.ssl.TLSv1_2 INT 1
CONFIG proxy.config.ssl.TLSv1_1 INT 0
CONFIG proxy.config.ssl.TLSv1 INT 0
CONFIG proxy.config.ssl.server.cipher_suite STRING ECDHE+AESGCM:ECDHE+CHACHA20:DHE+AESGCM:!aNULL:!MD5
EOF

# UFW per 8443
sudo ufw allow from 192.168.89.0/24 to any port 8443 proto tcp comment 'ATS-TLS-proxy'
sudo systemctl restart trafficserver

# Test CONNECT (funziona)
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 3 --proxy-insecure -x https://localhost:8443 https://httpbin.org/ip
```

**Nota**: TLS forward proxy funziona per CONNECT (HTTPS destinations). GET/POST a destinazioni HTTP su porta 8443 non è supportato — usare porta 8080 per HTTP.

---

## 13. AppArmor (opzionale — richiede tuning manuale)

AppArmor è attivo su entrambi gli OS. Un profilo per `traffic_server` è stato creato e testato ma **rimosso** perché bloccava l'accesso a `/usr/local/pcre/lib/libpcre.so.1` (su 26.04).

### 13.1 Come attivarlo in produzione

```bash
# 1. Copiare il profilo base
sudo tee /etc/apparmor.d/opt.trafficserver.bin.traffic_server > /dev/null << 'EOF'
#include <tunables/global>
profile ats_traffic_server /opt/trafficserver/bin/traffic_server {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  /opt/trafficserver/** mr,
  /etc/trafficserver/** rw,
  /var/lib/trafficserver/** rw,
  /var/log/trafficserver/** rw,
  /run/trafficserver/** rw,
  /usr/local/pcre/lib/** mr,
  /dev/urandom r,
  network inet stream, network inet6 stream,
  network inet dgram, network inet6 dgram,
  capability net_bind_service, capability setuid, capability setgid, capability sys_resource,
}
EOF

# 2. Mettere in complain mode (logga ma non blocca)
sudo apt install -y apparmor-utils
sudo aa-complain /opt/trafficserver/bin/traffic_server
sudo apparmor_parser -r /etc/apparmor.d/opt.trafficserver.bin.traffic_server

# 3. Generare traffico normale per alcuni giorni

# 4. Analizzare i log e aggiungere regole mancanti
sudo aa-logprof  # Interattivo — richiede risposte umane

# 5. Passare a enforce mode (blocca violazioni)
sudo aa-enforce /opt/trafficserver/bin/traffic_server
```

---

## 14. Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| `404 Not Found` | `url_remap.remap_required=1` | Impostare a `0` in records.config |
| `libpcre.so.1: cannot open` | PCRE1 non in ldconfig (26.04) | `echo '/usr/local/pcre/lib' \| sudo tee /etc/ld.so.conf.d/pcre.conf && sudo ldconfig` |
| `configure: error: Cannot find pcre` | PCRE1 assente | 24.04: `apt install libpcre3-dev`<br>26.04: compilare PCRE1 da sorgente (Sez. 3.2) |
| Servizio non parte | Lock file da crash precedente | `rm -f /var/lib/trafficserver/trafficserver/*.lock` |
| Deny non blocca | Solo reload, o ordine invertito | `systemctl restart` + deny PRIMA di allow |
| `000` / connection timeout | Ownership config sbagliata | `chown ats:ats /etc/trafficserver/*` |
| `Empty reply from server` | AppArmor blocca librerie | Rimuovere profilo: `sudo aa-remove-unknown` |
| Connessione SSH persa | UFW attivo senza SSH allow | `ufw allow 22/tcp` PRIMA di `ufw enable` |
| 403 invece di 200 da admin IP | ADMIN non nel config o config non letto | Verificare `grep 'admin IPs' diags.log` |
| Plugin non caricato | Permessi .so o plugin.config | `chown ats:ats` su entrambi |
| DNS cache gap | OS_DNS hook non scatta per domini cached | Normale. I domini appena visitati bypassano auth per ~minuti |
| Plugin crasha su `TSMimeHdrFieldValueStringGet` | `value_len` passato come NULL | **Sempre passare `&vlen`** (int), mai NULL. Bug scoperto durante sviluppo plugin v2.1 |

---

## 15. Comandi manutenzione

```bash
# Stato servizio
sudo systemctl status trafficserver

# Restart / Reload
sudo systemctl restart trafficserver
sudo /opt/trafficserver/bin/traffic_ctl config reload  # solo remap

# Log in tempo reale
sudo tail -f /var/lib/trafficserver/log/trafficserver/audit.log
sudo journalctl -u trafficserver -f

# Metriche
/opt/trafficserver/bin/traffic_top
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# Verifica sintassi
sudo /opt/trafficserver/bin/traffic_server -C verify_config

# Backup configurazioni
sudo tar czf ats-backup-$(date +%Y%m%d).tar.gz /etc/trafficserver/
sudo etckeeper commit "Descrizione modifica"

# Health check manuale
sudo /opt/ats_health.sh
sudo tail -3 /var/log/ats-health.log

# Fail2ban
sudo fail2ban-client status ats-proxy
sudo fail2ban-client set ats-proxy unbanip <IP>

# Riavvio pulito (se lock file bloccano)
sudo systemctl stop trafficserver
sudo rm -f /var/lib/trafficserver/trafficserver/*.lock /var/lib/trafficserver/trafficserver/host.db
sudo systemctl start trafficserver

# Verifica CVE e versioni librerie
sudo bash /opt/cve-check.sh
sudo tail -20 /var/log/ats-cve.log
```

---

*Guida completa testata su VM 130 (Ubuntu 24.04) e VM 134 (Ubuntu 26.04) con ATS 9.2.13 — 25 Maggio 2026*
