# Apache Traffic Server 9.2.13 LTS — Guida Unificata di Installazione

## Ubuntu 24.04 LTS (Noble) e 26.04 LTS (Resolute Raccoon)

**Versione 3.0 — 24 Maggio 2026 — Testata su VM 130 (24.04) e VM 134 (26.04)**

---

## Scelta architetturale

| Componente | 24.04 Noble | 26.04 Resolute | Motivazione |
|-----------|------------|----------------|------------|
| OS | Ubuntu 24.04 LTS | Ubuntu 26.04 LTS | Supporto 10/12 anni, dipendenze stabili |
| ATS | 9.2.13 LTS (compilato) | 9.2.13 LTS (compilato) | 11 CVE chiuse vs 9.2.3 da apt |
| PCRE | `libpcre3-dev` da apt (8.39) | **PCRE1 8.45 da sorgente** | PCRE1 rimosso dai repo 26.04 |
| GCC | 13.x | **15.2.0** | Nessun impatto funzionale |
| OpenSSL | 3.0.x LTS | **3.5.5** | API compatibili |

> **⚠️ `--enable-pcre2` NON funziona con ATS 9.2.13. Su 26.04 serve PCRE1 da sorgente.**

---

## 1. Prerequisiti

- Ubuntu Server 24.04 LTS (Noble) **oppure** 26.04 LTS (Resolute Raccoon)
- RAM: 2 GB min, 4+ GB per produzione
- Disco: 10+ GB per cache
- Accesso: utente con `sudo`, connettivita Internet

---

## 2. Preparazione Sistema

> **🔵 24.04** e **🟢 26.04**: blocchi separati dove diverso. Stesso colore = identico.

### 2.1 Verifica OS

```bash
lsb_release -a
# 24.04 → Codename: noble
# 26.04 → Codename: resolute
```

### 2.2 Aggiornamento e dipendenze

```bash
sudo apt update && sudo apt upgrade -y
```

**🔵 Ubuntu 24.04:**
```bash
sudo apt install -y \
  build-essential gcc g++ make libtool autoconf automake pkg-config python3-dev \
  libssl-dev libpcre3-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev \
  libncurses5-dev libxml2-dev libjson-c-dev libcurl4-openssl-dev libunwind-dev \
  git wget curl tar gzip bzip2
```

**🟢 Ubuntu 26.04:**
```bash
# NOTA: libpcre3-dev ASSENTE nei repo. libncurses-dev invece di libncurses5-dev.
sudo apt install -y \
  build-essential gcc g++ make libtool autoconf automake pkg-config python3-dev \
  libssl-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev \
  libncurses-dev libxml2-dev libjson-c-dev libcurl4-openssl-dev libunwind-dev \
  git wget curl tar gzip bzip2
```

### 2.3 Verifica dipendenze

```bash
dpkg -l | grep -E "(build-essential|libssl-dev|libpcre)" | wc -l
# Atteso: >= 3
```

---

## 3. Creazione Utente Dedicato

```bash
sudo groupadd --system ats
sudo useradd --system --gid ats --home-dir /opt/trafficserver --shell /usr/sbin/nologin ats
id ats
# Atteso: uid=999(ats) gid=XXX(ats) groups=XXX(ats)
```

---

## 4. Download Sorgenti ATS 9.2.13 LTS

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2.sha256

# Verifica integrita
sha256sum -c trafficserver-9.2.13.tar.bz2.sha256
# Atteso: trafficserver-9.2.13.tar.bz2: OK

tar -xjf trafficserver-9.2.13.tar.bz2
cd trafficserver-9.2.13
```

---

## 5. PCRE — Dipendenza Regex

**🔵 Ubuntu 24.04**: Gia installato via `libpcre3-dev`. Passare alla Sezione 6.

**🟢 Ubuntu 26.04**: PCRE1 NON disponibile nei repo. Compilare da sorgente:

```bash
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz
tar xzf pcre-8.45.tar.gz
cd pcre-8.45

./configure --prefix=/usr/local/pcre --enable-utf8 --enable-unicode-properties
make -j$(nproc)
sudo make install

# Verifica
/usr/local/pcre/bin/pcre-config --version
# Atteso: 8.45
```

---

## 6. Compilazione ATS 9.2.13

### 6.1 autotools

```bash
cd /tmp/trafficserver-9.2.13
autoreconf -if
ls -la configure  # Deve esistere
```

### 6.2 Configure

**🔵 Ubuntu 24.04:**
```bash
./configure \
  --prefix=/opt/trafficserver \
  --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver \
  --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats \
  --enable-pcre \
  --disable-tests --disable-examples --disable-maintainer-mode
```

**🟢 Ubuntu 26.04:**
```bash
export PKG_CONFIG_PATH='/usr/local/pcre/lib/pkgconfig'

./configure \
  --prefix=/opt/trafficserver \
  --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver \
  --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats \
  --with-pcre=/usr/local/pcre \
  --disable-tests --disable-examples --disable-maintainer-mode
```

| Flag | Significato |
|------|------------|
| `--prefix=/opt/trafficserver` | Installazione isolata (standard enterprise) |
| `--with-user=ats --with-group=ats` | Compila per utente dedicato |
| `--enable-pcre` / `--with-pcre=DIR` | Supporto regex PCRE |
| `--disable-tests` | Riduce superficie d'attacco |
| `--sysconfdir=/etc/trafficserver` | Config in /etc (FHS) |

### 6.3 Compilazione e installazione

```bash
make -j$(nproc)          # 5-15 minuti
sudo make install

echo "/opt/trafficserver/lib" | sudo tee /etc/ld.so.conf.d/trafficserver.conf
sudo ldconfig

ls -la /opt/trafficserver/bin/traffic_server
# ~86 MB, eseguibile
```

---

## 7. Permessi e Directory

```bash
sudo chown -R ats:ats /opt/trafficserver /etc/trafficserver /var/lib/trafficserver
sudo mkdir -p /run/trafficserver /var/log/trafficserver /var/lib/trafficserver/cache
sudo mkdir -p /var/lib/trafficserver/log/trafficserver
sudo chown ats:ats /run/trafficserver /var/log/trafficserver /var/lib/trafficserver/cache
sudo chown ats:ats /var/lib/trafficserver/log/trafficserver
```

---

## 8. Configurazione ATS

> **⚠️ REGOLA FONDAMENTALE**: Dopo OGNI scrittura di file in `/etc/trafficserver/`, eseguire:
> ```bash
> sudo chown ats:ats /etc/trafficserver/*
> sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
> ```
> Se ownership resta `root:root`, ATS (utente `ats`) non legge il file e le richieste vengono bloccate silenziosamente.

### 8.1 records.config

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

| Config chiave | Valore | Significato |
|---------------|--------|------------|
| `server_ports` | `8080` | Porta proxy |
| `url_remap.remap_required` | `0` | **FONDAMENTALE**: senza = 404 |
| `reverse_proxy.enabled` | `0` | Forward proxy puro |
| `dns.nameservers` | `NULL` | Delega a `/etc/resolv.conf` |
| `ram_cache.size` | `1073741824` | 1 GB RAM cache |

### 8.2 ip_allow.yaml

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

**SOSTITUIRE** `192.168.89.0/24` con la subnet reale. Mettere `allow` PRIMA del deny finale.

**Regola first-match (VERIFICATA su entrambe le VM):**

```yaml
# ✅ CORRETTO: deny /32 PRIMA di allow /24
  - deny:  192.168.89.99/32     # matcha per .99 → bloccato
  - allow: 192.168.89.0/24      # matcha per gli altri IP

# ❌ SBAGLIATO: allow /24 PRIMA di deny /32
  - allow: 192.168.89.0/24      # matcha per .99 → permesso!
  - deny:  192.168.89.99/32     # mai raggiunto
```

**⚠️ `traffic_ctl config reload` NON applica i deny. Serve `systemctl restart`.**

### 8.3 logging.yaml

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

Output: `IP_client - [timestamp] "METHOD URL HTTP/1.x" STATUS BYTES FQDN BACKEND`

### 8.4 storage.config e remap.config

```bash
sudo tee /etc/trafficserver/storage.config > /dev/null << 'EOF'
/var/lib/trafficserver/cache 10G
EOF

sudo touch /etc/trafficserver/remap.config
```

### 8.5 Permessi finali

```bash
sudo chown ats:ats /etc/trafficserver/*
sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
sudo chown -R ats:ats /var/lib/trafficserver /var/log/trafficserver
```

---

## 9. Servizio Systemd

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

# Hardening
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
sudo systemctl enable trafficserver
sudo systemctl start trafficserver
```

> **Nota**: `RuntimeDirectory=trafficserver` crea `/run/trafficserver` automaticamente (necessario con `ProtectSystem=strict`).

---

## 10. Verifiche Post-Installazione

```bash
# 1. Porta in ascolto
sudo ss -tlnp | grep 8080
# Atteso: LISTEN ... traffic_server

# 2. HTTP proxy
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip
# Atteso: 200

# 3. HTTPS CONNECT
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 https://httpbin.org/ip
# Atteso: 200

# 4. Log audit
sudo tail -3 /var/lib/trafficserver/log/trafficserver/audit.log
# Atteso: contiene IP client, FQDN, status

# 5. Sintassi config
sudo /opt/trafficserver/bin/traffic_server -C verify_config

# 6. Concorrenza (10 richieste)
for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' -x http://localhost:8080 http://httpbin.org/ip & done; wait; echo ''
# Atteso: 200 200 200 200 200 200 200 200 200 200

# 7. Versione
/opt/trafficserver/bin/traffic_server -V 2>&1 | head -1
# Atteso: Traffic Server 9.2.13
```

---

## 11. Hardening

### 11.1 Firewall UFW

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp comment 'ATS-proxy'
echo 'y' | sudo ufw enable
```

> **🟢 26.04**: UFW backend e nftables (default). I comandi sono identici.

### 11.2 SSH Hardening

**⚠️ PRIMA di eseguire**: verificare che la chiave SSH funzioni.

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

### 11.3 Sysctl — Kernel Hardening

```bash
sudo tee /etc/sysctl.d/99-ats-hardening.conf > /dev/null << 'EOF'
net.ipv4.ip_forward=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_rfc1337=1
net.ipv4.conf.all.log_martians=1
net.core.somaxconn=4096
net.netfilter.nf_conntrack_max=65536
kernel.core_pattern=|/bin/false
kernel.sysrq=0
EOF
sudo sysctl -p /etc/sysctl.d/99-ats-hardening.conf
```

### 11.4 Fail2ban

```bash
sudo apt install -y fail2ban
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
```

### 11.5 Unattended Upgrades

```bash
sudo apt install -y unattended-upgrades
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
sudo systemctl enable --now unattended-upgrades
```

### 11.6 etckeeper — Versionamento Configurazioni

```bash
sudo apt install -y etckeeper
sudo etckeeper init
sudo etckeeper commit "Configurazione iniziale ATS proxy enterprise"
```

### 11.7 Verifica hardening

```bash
# Stato firewall
sudo ufw status verbose

# Stato fail2ban
sudo fail2ban-client status sshd

# Stato unattended
systemctl is-active unattended-upgrades

# Log etckeeper
sudo git -C /etc log --oneline -3
```

---

## 12. Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| `404 Not Found` | `url_remap.remap_required=1` | Impostare a `0` in records.config |
| `configure: error: Cannot find pcre` | PCRE1 mancante | 24.04: `apt install libpcre3-dev`<br>26.04: compilare PCRE1 da sorgente (Sez. 5) |
| Log non creati | Directory mancante | `mkdir -p /var/lib/trafficserver/log/trafficserver` |
| Servizio non parte | Lock file da crash precedente | `rm -f /var/lib/trafficserver/trafficserver/*.lock` |
| Deny non blocca | Solo reload | **`systemctl restart` obbligatorio** |
| Deny non blocca | Allow /24 prima di deny /32 | Invertire ordine: deny PRIMA |
| `000` / connection timeout | Ownership config sbagliata | `chown ats:ats /etc/trafficserver/*` |
| `traffic_server: error while loading` | ldconfig mancante | `sudo ldconfig` |
| `ulimit: error setting limit` con systemd hardened | `LimitNOFILE` conflitto | Warning innocuo, non blocca |
| `Failed to set up mount namespacing` | Path non esiste con ProtectSystem=strict | Usare `RuntimeDirectory=trafficserver` |
| Connessione SSH persa | UFW attivo senza SSH allow | `ufw allow 22/tcp` PRIMA di `ufw enable` |

---

## 13. Checklist Pre-Produzione

- [ ] OS verificato (`lsb_release -a`)
- [ ] ATS 9.2.13 compilato, SHA256 verificato
- [ ] Utente `ats` con shell `/usr/sbin/nologin`
- [ ] Ownership `ats:ats` su `/opt`, `/etc/trafficserver`, `/var/lib/trafficserver`
- [ ] `url_remap.remap_required=0`, `reverse_proxy.enabled=0`
- [ ] `ip_allow.yaml` con subnet corrette, deny PRIMA di allow
- [ ] `logging.yaml` con FQDN e status
- [ ] Servizio systemd attivo con hardening
- [ ] UFW attivo: SSH (22/tcp) e proxy (8080/tcp) autorizzati
- [ ] SSH hardening: key-only, no root
- [ ] fail2ban attivo (jail SSH)
- [ ] unattended-upgrades attivo
- [ ] etckeeper attivo
- [ ] Test proxy HTTP e HTTPS → 200
- [ ] Test 10 richieste concorrenti → tutte 200
- [ ] Test ACL da IP remoto
- [ ] Log audit contiene FQDN

---

## 14. Batteria Test (risultati verificati su entrambe le VM)

### ACL (ip_allow.yaml)

| Test | VM 130 (24.04) | VM 134 (26.04) | Note |
|------|---------------|---------------|------|
| Deny /32 PRIMA di allow /24 | ✅ 000 (TCP block) | ✅ 000 | First-match |
| Allow /24 PRIMA di deny /32 | ✅ 200 (deny ignorato) | ✅ 200 | First-match |
| Reload senza restart (deny) | ✅ 200 (ignorato) | ✅ 200 | Serve restart |
| Restart con deny | ✅ 000 | ✅ 000 | TCP block |
| Rimozione deny + restart | ✅ 200 | ✅ 200 | Sblocco immediato |
| Allow /32 + deny /24 | ✅ 200 | ✅ 200 | Eccezione funziona |

### Logging

| Test | Entrambe | Note |
|------|----------|------|
| HTTP: FQDN nel log | ✅ | `%<{Host}cqh>` corretto |
| HTTPS CONNECT: FQDN nel log | ✅ | CONNECT + porta loggati |
| `%<{SERVC}pquc>` IP backend | ❌ | Non valido, usare `%<shn>` |

### Resilienza

| Test | VM 130 | VM 134 |
|------|--------|--------|
| Stop/start pulito | ✅ | ✅ |
| 10 richieste concorrenti | ✅ (200×10) | ✅ (200×10) |
| Protezione lock file | ✅ | ✅ |

---

## 15. Comandi di Manutenzione Rapida

```bash
# Stato servizio
sudo systemctl status trafficserver

# Restart / Reload
sudo systemctl restart trafficserver
sudo /opt/trafficserver/bin/traffic_ctl config reload

# Log in tempo reale
sudo journalctl -u trafficserver -f
sudo tail -f /var/lib/trafficserver/log/trafficserver/audit.log

# Monitoraggio
/opt/trafficserver/bin/traffic_top
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# Verifica sintassi
/opt/trafficserver/bin/traffic_server -C verify_config

# Backup configurazioni
sudo tar czf ats-config-backup-$(date +%Y%m%d).tar.gz /etc/trafficserver/
sudo etckeeper commit "Descrizione modifica"
```

---

## 16. Riepilogo Differenze 24.04 vs 26.04

| Aspetto | 24.04 Noble (VM 130) | 26.04 Resolute (VM 134) |
|---------|---------------------|------------------------|
| Kernel | 6.8.x | 6.14.x+ |
| GCC | 13.x | **15.2.0** |
| OpenSSL | 3.0.x LTS | **3.5.5** |
| PCRE1 | `libpcre3-dev` (apt) | **Da sorgente** (`/usr/local/pcre`) |
| PCRE2 | 10.x | 10.46 |
| libncurses | `libncurses5-dev` | **`libncurses-dev`** |
| Configure flag | `--enable-pcre` | **`--with-pcre=/usr/local/pcre`** |
| UFW backend | iptables | nftables (comandi identici) |
| Supporto LTS | 10 anni (2034) | 12 anni (2038) |

---

*Guida unificata basata su test reali: VM 130 (24.04) e VM 134 (26.04), 24 Maggio 2026*
