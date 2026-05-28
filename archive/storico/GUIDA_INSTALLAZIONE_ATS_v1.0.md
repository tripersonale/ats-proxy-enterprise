# Apache Traffic Server 9.2.13 LTS — Guida di Installazione Testata

## Ubuntu 24.04 LTS (Noble) — Proxy Outbound Enterprise

**Versione 1.2 — 24 Maggio 2026 — Testata su VM reale + hardening avanzato + compliance**

---

## Scelta architetturale

| Componente | Scelta | Motivazione |
|-----------|--------|------------|
| OS | Ubuntu 24.04 LTS | Supporto 10 anni (2034), rodaggio 2 anni, dipendenze stabili |
| ATS | 9.2.13 LTS (compilato) | Chiude 11 CVE, non nei repo 24.04 (fermo a 9.2.3), Debian lo sta rimuovendo |
| Compilazione | Da sorgente (.tar.bz2) | Unica strada: pacchetto apt e fermo a 9.2.3, 10 versioni indietro |

Ubuntu 24.04 ha ATS nei repo (`apt install trafficserver`) ma e la versione 9.2.3 — 11 CVE aperte. La 9.2.13 le chiude tutte (CVE-2024-38311, CVE-2025-65114, CVE-2025-58136, etc.).

---

## 1. Prerequisiti

- Ubuntu Server 24.04 LTS (Noble) — installazione server, architettura amd64
- RAM: minimo 2 GB (consigliati 4+ GB per produzione)
- Disco: 10+ GB dedicati alla cache
- Accesso: utente con `sudo`
- Connettivita: Internet per download sorgenti e dipendenze

---

## 2. Preparazione Sistema

```bash
# Verifica versione OS
lsb_release -a
# Atteso: Description: Ubuntu 24.04 LTS, Codename: noble

# Aggiornamento sistema
sudo apt update && sudo apt upgrade -y

# Installazione dipendenze build
# NOTA: servono SIA libpcre2-dev CHE libpcre3-dev (ATS 9.2.13 usa PCRE1)
sudo apt install -y \
  build-essential gcc g++ make libtool autoconf automake pkg-config python3-dev \
  libssl-dev libpcre2-dev libpcre3-dev zlib1g-dev libcap-dev libhwloc-dev \
  libncurses5-dev libxml2-dev libjson-c-dev libcurl4-openssl-dev libunwind-dev \
  git wget curl tar gzip bzip2
```

### Verifica

```bash
dpkg -l | grep -E "(build-essential|libssl-dev|libpcre3-dev)" | wc -l
# Atteso: >= 3
```

---

## 3. Creazione Utente Dedicato

ATS non deve girare come root. Principio del minimo privilegio:

```bash
sudo groupadd --system ats
sudo useradd --system --gid ats --home-dir /opt/trafficserver --shell /usr/sbin/nologin ats

# Verifica
id ats
# Atteso: uid=XXX(ats) gid=XXX(ats) groups=XXX(ats)
```

---

## 4. Download Sorgenti ATS 9.2.13 LTS

**ATTENZIONE**: L'URL corretto e `downloads.apache.org` con formato `.tar.bz2` (NON `.tar.gz` da `archive.apache.org` che da 404).

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2

# Verifica
ls -lh trafficserver-9.2.13.tar.bz2
# Atteso: ~9.7 MB

tar -xjf trafficserver-9.2.13.tar.bz2
cd trafficserver-9.2.13
```

---

## 5. Compilazione

```bash
# Prepara autotools
autoreconf -if
ls -la configure  # Deve esistere

# Configura build
./configure \
  --prefix=/opt/trafficserver \
  --exec-prefix=/opt/trafficserver \
  --bindir=/opt/trafficserver/bin \
  --sbindir=/opt/trafficserver/bin \
  --libexecdir=/opt/trafficserver/lib/modules \
  --sysconfdir=/etc/trafficserver \
  --sharedstatedir=/opt/trafficserver/var/trafficserver \
  --localstatedir=/opt/trafficserver/var/trafficserver \
  --runstatedir=/run/trafficserver \
  --with-user=ats \
  --with-group=ats \
  --enable-pcre \
  --disable-tests \
  --disable-examples \
  --disable-maintainer-mode
```

### Opzioni spiegate

| Flag | Significato |
|------|------------|
| `--prefix=/opt/trafficserver` | Installazione isolata in /opt (standard enterprise) |
| `--with-user=ats --with-group=ats` | Compila per utente dedicato |
| `--enable-pcre` | Supporto regex PCRE (richiede libpcre3-dev) |
| `--disable-tests` | Esclude test suite (velocizza build) |
| `--sysconfdir=/etc/trafficserver` | Config in /etc (standard FHS) |
| `--runstatedir=/run/trafficserver` | Runtime data in /run |

### Compilazione e installazione

```bash
# Compila (tempo: 5-15 minuti)
make -j$(nproc)

# Installa
sudo make install

# Configura ldconfig per librerie condivise
echo "/opt/trafficserver/lib" | sudo tee /etc/ld.so.conf.d/trafficserver.conf
sudo ldconfig

# Verifica binario
ls -la /opt/trafficserver/bin/traffic_server
# ~86 MB, eseguibile
```

---

## 6. Permessi e Directory

```bash
# Ownership a utente ats
sudo chown -R ats:ats /opt/trafficserver
sudo chown -R ats:ats /etc/trafficserver
sudo chown -R ats:ats /opt/trafficserver/var/trafficserver

# Directory runtime e log
sudo mkdir -p /run/trafficserver /opt/trafficserver/var/log/trafficserver /opt/trafficserver/var/trafficserver/cache
sudo chown ats:ats /run/trafficserver /opt/trafficserver/var/log/trafficserver /opt/trafficserver/var/trafficserver/cache
```

---

## 7. Configurazione ATS

### 7.1 records.config — Configurazione principale

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
EOF
```

**Spiegazione righe chiave:**

| Config | Valore | Significato |
|--------|--------|------------|
| `server_ports` | `8080` | Porta proxy esplicito |
| `dns.nameservers` | `NULL` | Usa /etc/resolv.conf di sistema |
| `url_remap.remap_required` | `0` | **FONDAMENTALE**: senza questo ATS restituisce 404 (cerca regole remap) |
| `reverse_proxy.enabled` | `0` | Forward proxy puro, no reverse |
| `ram_cache.size` | `1073741824` | 1 GB cache RAM |

### 7.2 ip_allow.yaml — Controllo Accessi

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

**SOSTITUIRE** `192.168.89.0/24` con la tua subnet reale. Aggiungere blocchi `allow` per ogni subnet autorizzata PRIMA del deny-all finale.

**⚠️ Dopo ogni modifica ai file di configurazione, ripristinare permessi:**
```bash
sudo chown ats:ats /etc/trafficserver/*.config /etc/trafficserver/*.yaml
sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
```
Se ATS non legge il file (ownership `root:root`), le richieste vengono bloccate silenziosamente.

**REGOLA FONDAMENTALE**: `ip_allow.yaml` valuta le regole in **ordine first-match** (come iptables). La PRIMA regola che matcha determina allow/deny. Per bloccare un IP specifico dentro una subnet autorizzata, mettere il **deny /32 PRIMA dell'allow /24**.

```yaml
# CORRETTO: deny prima, allow dopo
  - apply: in
    ip_addrs: 192.168.89.99/32
    action: deny
    method: ALL
  - apply: in
    ip_addrs: 192.168.89.0/24
    action: allow
    method: GET|POST|CONNECT|HEAD

# SBAGLIATO: allow prima, deny dopo -> il deny viene ignorato!
  - apply: in
    ip_addrs: 192.168.89.0/24
    action: allow
    method: ALL
  - apply: in
    ip_addrs: 192.168.89.99/32
    action: deny        # ← ignorato, l'allow /24 ha già matchato!
    method: ALL
```

**⚠️ CRITICO: `traffic_ctl config reload` NON applica i deny in `ip_allow.yaml`. Per attivare un blocco serve RESTART COMPLETO:**
```bash
sudo systemctl restart trafficserver
```

### 7.3 logging.yaml — Audit Log

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

**Formato output:** `IP_client - [timestamp] "METHOD URL HTTP/1.x" STATUS BYTES FQDN BACKEND_HOSTNAME`

**Esempio reale dalla VM test:**
```
127.0.0.1 - [24/May/2026:14:04:46 -0000] "GET http://httpbin.org/ip HTTP/1.1" 200 41 httpbin.org httpbin.org
127.0.0.1 - [24/May/2026:14:04:48 -0000] "CONNECT httpbin.org:443/ HTTP/1.1" 200 4748 httpbin.org:443 httpbin.org
```

**Variabili logging principali:**

| Variabile | Contenuto | Esempio |
|-----------|-----------|---------|
| `%<chi>` | IP client | `192.168.89.55` |
| `%<cqtx>` | Request line completa (include FQDN) | `GET http://example.com/ HTTP/1.1` |
| `%<pssc>` | Status code | `200` / `403` |
| `%<pscl>` | Content length | `1256` |
| `%<{Host}cqh>` | Header Host (FQDN richiesto) | `example.com` |
| `%<shn>` | Hostname server di origine | `93.184.215.14` |
| `%<caun>` | Username autenticato | `-` (non autenticato) |
| `%<cqtn>` | Timestamp richiesta | `[24/May/2026:14:04:46 -0000]` |

**NOTA**: `%<{SERVC}pquc>` (IP backend grezzo) **non è valido in logging.yaml** (genera `Invalid container specification`). Usare `%<shn>` per l'hostname backend.

### 7.4 storage.config — Cache Disco

```bash
sudo tee /etc/trafficserver/storage.config > /dev/null << 'EOF'
/opt/trafficserver/var/trafficserver/cache 10G
EOF
```

### 7.5 remap.config — Minimo per forward proxy

```bash
sudo tee /etc/trafficserver/remap.config > /dev/null << 'EOF'
EOF
```

File vuoto: forward proxy esplicito non richiede regole remap.

---

## 8. Servizio Systemd

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

[Install]
WantedBy=multi-user.target
EOF
```

### Attivazione

```bash
sudo systemctl daemon-reload
sudo systemctl enable trafficserver
sudo systemctl start trafficserver

# Verifica stato
sudo systemctl status trafficserver
# Atteso: Active: active (running)
```

---

## 9. Verifiche Post-Installazione

```bash
# 1. Porta in ascolto
sudo ss -tlnp | grep 8080
# Atteso: LISTEN 0.0.0.0:8080 ... ("traffic_server",pid=XXX)

# 2. Test proxy da localhost
curl -x http://localhost:8080 -I http://www.example.com
# Atteso: HTTP/1.1 200 OK, Server: ATS/9.2.13

# 3. Test HTTPS CONNECT tunnel
curl -x http://localhost:8080 -I https://www.example.com
# Atteso: HTTP/1.1 200 Connection established (tunnel)

# 4. Verifica log
sudo ls -la /opt/trafficserver/opt/trafficserver/var/log/trafficserver/
# Atteso: audit.log, diags.log, manager.log

# 5. Verifica sintassi config
sudo /opt/trafficserver/bin/traffic_server -C verify_config

# 6. Metriche
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests
```

---

## 10. Hardening

### 10.1 Firewall UFW

```bash
sudo apt install -y ufw

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
# SOSTITUIRE con la tua subnet:
sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp comment 'ATS-proxy'

echo 'y' | sudo ufw enable
sudo ufw status verbose
```

**ATTENZIONE**: Assicurarsi che la porta SSH sia aperta PRIMA di attivare UFW, altrimenti si perde l'accesso.

### 10.2 Sysctl — Ottimizzazioni Kernel

```bash
sudo tee -a /etc/sysctl.conf > /dev/null << 'EOF'

# Hardening rete per Proxy ATS
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_rfc1337=1
net.core.somaxconn=4096
net.netfilter.nf_conntrack_max=65536
EOF

sudo sysctl -p
```

### 10.3 Permessi File

```bash
sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
sudo chown -R ats:ats /etc/trafficserver /opt/trafficserver/var/trafficserver /opt/trafficserver/var/log/trafficserver
```

### 10.4 Hardening SSH

**PRIMA di eseguire**: assicurarsi di avere una chiave SSH funzionante, altrimenti si perde l'accesso.

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'EOF'
# Hardening SSH per server enterprise
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Verifica sintassi e riavvia
sudo sshd -t && sudo systemctl restart sshd
```

### 10.5 Unattended Upgrades — Aggiornamenti Automatici

```bash
sudo apt install -y unattended-upgrades

sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
EOF

sudo systemctl enable --now unattended-upgrades
```

### 10.6 Fail2ban — Protezione Anti-Brute-Force

```bash
sudo apt install -y fail2ban

# Configurazione jail SSH
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
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
EOF

sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

### 10.7 Versionamento Configurazioni con etckeeper

```bash
sudo apt install -y etckeeper

# Inizializza git in /etc
sudo etckeeper init
sudo etckeeper commit "Configurazione iniziale ATS proxy enterprise"

# Dopo ogni modifica:
# sudo etckeeper commit "Aggiornamento ip_allow.yaml: aggiunta subnet 10.0.0.0/8"
```

### 10.8 Systemd Hardening Aggiuntivo

```bash
# Aggiornare la unit systemd con hardening aggiuntivo
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

# Hardening systemd
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/trafficserver /opt/trafficserver/var/trafficserver /opt/trafficserver/var/log/trafficserver /run/trafficserver
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
sudo systemctl restart trafficserver
```

---

## 11. Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| `404 Not Found` dal proxy | `url_remap.remap_required` non impostato a 0 | Aggiungere `CONFIG proxy.config.url_remap.remap_required INT 0` |
| `configure: error: Cannot find pcre` | Manca `libpcre3-dev` | `sudo apt install libpcre3-dev` |
| Log non creati | Directory log mancante | `sudo mkdir -p /opt/trafficserver/var/trafficserver/log/trafficserver && sudo chown ats:ats /opt/trafficserver/var/trafficserver/log/trafficserver` |
| Servizio non parte (status: inactive) | Lock file da processo precedente | `sudo rm -f /opt/trafficserver/var/trafficserver/manager.lock /opt/trafficserver/var/trafficserver/server.lock` |
| Deny /32 NON blocca | **1) reload non basta, serve RESTART**; 2) allow /24 viene PRIMA del deny | `sudo systemctl restart trafficserver` + mettere deny PRIMA di allow |
| `Can't acquire manager lockfile` | traffic_manager zombie | `sudo pkill -9 traffic_manager && sudo rm /opt/trafficserver/var/trafficserver/manager.lock` |
| `traffic_server: error while loading shared libraries` | ldconfig mancante | `sudo ldconfig` |
| Log format vuoto dopo restart | `logging.yaml` ha priorita su `logs_xml.config` | Usare `logging.yaml` per il formato |
| Connessione SSH persa dopo UFW | SSH non in allow list | Aggiungere `sudo ufw allow 22/tcp` PRIMA di `ufw enable` |
| `traffic_server` aborted (core dump) | Lock file o socket sporchi | `sudo rm -f /opt/trafficserver/var/trafficserver/*.lock /opt/trafficserver/var/trafficserver/*.sock` |

---

## 12. Checklist Pre-Produzione

- [ ] Ubuntu 24.04 LTS verificato
- [ ] ATS 9.2.13 compilato senza errori (SHA256 checksum verificato)
- [ ] Utente `ats` esiste con shell `/usr/sbin/nologin`
- [ ] Ownership `ats:ats` su `/opt/trafficserver`, `/etc/trafficserver`, `/opt/trafficserver/var/trafficserver`
- [ ] `records.config` verificato: `url_remap.remap_required=0`, `reverse_proxy.enabled=0`
- [ ] `ip_allow.yaml` contiene le subnet corrette (rimosso deny-all temporaneo)
- [ ] `logging.yaml` con formato audit (FQDN + status)
- [ ] Servizio `trafficserver.service` abilitato e attivo
- [ ] UFW attivo con SSH e porta proxy autorizzate
- [ ] SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no`
- [ ] `unattended-upgrades` attivo per security updates
- [ ] `fail2ban` attivo con jail SSH
- [ ] `etckeeper` attivo per versionamento configurazioni
- [ ] Systemd hardening: `ProtectSystem=strict`, `PrivateTmp=true`, `NoNewPrivileges=true`
- [ ] Log rotation attiva (rolling 86400 secondi)
- [ ] Test proxy da client autorizzato: `curl -x http://PROXY_IP:8080 http://example.com`
- [ ] Test accesso negato da client non autorizzato
- [ ] Verifica `audit.log` contiene FQDN richiesti

---

## 13. Comandi di Manutenzione Rapida

```bash
# Stato servizio
sudo systemctl status trafficserver

# Restart
sudo systemctl restart trafficserver

# Log in tempo reale
sudo journalctl -u trafficserver -f
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log

# Monitoraggio TUI
/opt/trafficserver/bin/traffic_top

# Statistiche richieste
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# Reload configurazione (solo remap e ip_allow)
sudo /opt/trafficserver/bin/traffic_ctl config reload

# Verifica sintassi configurazione
/opt/trafficserver/bin/traffic_server -C verify_config

# Backup configurazioni
sudo tar czf ats-config-backup-$(date +%Y%m%d).tar.gz /etc/trafficserver/
```

---

## 14. Errori Comuni Incontrati e Risolti Durante il Test Reale

1. **URL sorgenti errato** (`.tar.gz` su `archive.apache.org` → 404)
   - Corretto: `https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2`

2. **`libpcre2-dev` insufficiente** — ATS 9.2.13 cerca `pcre-config` che e di PCRE1
   - Corretto: installare anche `libpcre3-dev`

3. **`url_remap.remap_required` default a 1** — forward proxy restituisce 404
   - Corretto: aggiungere `CONFIG proxy.config.url_remap.remap_required INT 0`

4. **`logging.yaml` ha priorita su `logs_xml.config`** in ATS 9.2.x
   - Corretto: configurare il formato in `logging.yaml`, non in `logs_xml.config`

5. **DNS `127.0.0.1` non funziona** (systemd-resolved usa `127.0.0.53`)
   - Corretto: usare `dns.nameservers STRING NULL` per delegare a `/etc/resolv.conf`

6. **UFW blocca SSH** se `allow 22/tcp` non aggiunto prima di `enable`
   - Corretto: sequenza: deny incoming → allow SSH → allow proxy → enable

7. **Lock file sporchi da restart brutali** bloccano l'avvio
   - Corretto: `rm -f /opt/trafficserver/var/trafficserver/*.lock`

---

## 15. Risultati Batteria Test

Test eseguiti il 2026-05-24 su VM 130 (ats-proxy-01, 192.168.89.27).

### ACL (ip_allow.yaml)

| Test | Risultato | Note |
|------|-----------|------|
| Deny /32 PRIMA di allow /24 | ✅ Bloccato | **First-match: ordine CONTA.** Deny prima blocca. |
| Allow /24 PRIMA di deny /32 | ❌ Permesso | Il deny dopo viene IGNORATO. L'allow /24 matcha per primo. |
| Deny /32 isolato (no allow /24) | ✅ Bloccato | Con restart, deny funziona. L'IP non si connette. |
| Rimozione deny → ripristino | ✅ Sbloccato | L'IP torna a funzionare dopo restart. |
| Allow /32 + deny /24 (eccezione) | ✅ Solo .10 passa | Allow /32 PRIMA vince su deny /24. |
| Reload SENZA restart | ❌ Ignorato | **`traffic_ctl config reload` NON applica i deny.** |
| Restart CON deny | ✅ Bloccato | Il deny blocca a livello TCP (connection fail), non HTTP 403. |

**Regola definitiva**: `ip_allow.yaml` è **first-match** (come iptables). Le regole sono valutate in ordine. La prima che matcha vince. Per bloccare un IP in una subnet autorizzata: deny /32 PRIMA, allow /24 DOPO, poi **`systemctl restart`** (mai solo reload).

### Logging

| Test | Risultato | Note |
|------|-----------|------|
| HTTP: FQDN + backend | ✅ | `%<{Host}cqh>` e `%<shn>` entrambi presenti |
| HTTPS CONNECT: FQDN | ✅ | `CONNECT httpbin.org:443/` loggato, con FQDN |
| `%<{SERVC}pquc>` IP backend | ❌ | Non valido in logging.yaml — usare `%<shn>` |
| Richieste diverse: FQDN diversi | ✅ | `example.com` vs `httpbin.org` correttamente distinti |

### Resilienza

| Test | Risultato | Note |
|------|-----------|------|
| Stop/start pulito | ✅ | Nessun lock file bloccante |
| 10 richieste concorrenti | ✅ | Tutte 200 OK |
| Reload records parziale | ✅ | Il proxy resta attivo (anche se records.config richiede restart per applicare) |

### UFW vs ACL

| Test | Risultato | Note |
|------|-----------|------|
| UFW allow + ACL allow | ✅ 200 | Entrambi i layer OK |
| UFW allow + ACL deny | ⚠️ 200 (localhost, 127.0.0.1 in allow) | Test locale non copre UFW; usare IP remoto |
| UFW senza regola proxy + ACL allow | ✅ 200 (localhost) | Loopback non filtrato da UFW |

**Regola d'oro**: testare sempre con IP remoti. I test da localhost non validano le ACL reali.

---

*Guida verificata su VM reale: Ubuntu 24.04.4 LTS + ATS 9.2.13 compilato da sorgente*
*Proxy IP: 192.168.89.27 | Porta: 8080 | VM ID Proxmox: 130*
