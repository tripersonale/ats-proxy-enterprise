# Apache Traffic Server 9.2.13 LTS — Guida di Installazione

## Ubuntu 24.04 LTS (Noble) e 26.04 LTS (Resolute Raccoon)

**Versione 4.0 — 26 Maggio 2026 — Testata su VM135 (24.04) e VM136 (26.04)**

---

## Scelta Architetturale

| Componente | 24.04 Noble | 26.04 Resolute | Motivazione |
|-----------|------------|----------------|------------|
| OS | Ubuntu 24.04 LTS | Ubuntu 26.04 LTS | Supporto 10/12 anni, dipendenze stabili |
| ATS | 9.2.13 LTS (compilato) | 9.2.13 LTS (compilato) | 11 CVE chiuse vs 9.2.3 da apt |
| PCRE | `libpcre3-dev` da apt (8.39) | **PCRE1 8.45 da sorgente** | PCRE1 rimosso dai repo 26.04 |
| GCC | 13.x | **15.2.0** | Nessun impatto funzionale |
| OpenSSL | 3.0.x LTS | **3.5.5** | API compatibili |
| Plugin | `ats_proxy_filter_v21.so` | `ats_proxy_filter_v21.so` | URL filtering + autenticazione |
| Verifica hardening | `ats-hardening-check.sh` | `ats-hardening-check.sh` | 25+ check automatici |

> **⚠️ `--enable-pcre2` NON funziona con ATS 9.2.13. Su 26.04 serve PCRE1 da sorgente.**

---

## 0. Due Percorsi di Installazione

### Percorso A — Installer Automatizzato (Raccomandato)

Lo script `scripts/install-ats-proxy.sh` copre TUTTI gli step di questa guida in un solo comando:
preparazione sistema, compilazione ATS + PCRE1, configurazione, plugin, systemd, hardening, health check.

**Due modalità operative:**

| Modalità | Comando | Comportamento |
|----------|---------|---------------|
| **Config file** | `--env ats-proxy.env --non-interactive` | Carica tutte le variabili dal file `.env`, nessuna richiesta a terminale |
| **Interattiva** | _nessuna flag_ | Chiede ogni parametro a terminale; usa valori di default se già presenti |

**Flag disponibili:**

| Flag | Effetto |
|------|---------|
| `--env FILE` | Carica variabili `ATS_*` dal file di configurazione |
| `--config FILE` | Carica configurazione legacy (senza prefisso `ATS_`) |
| `--plugin FILE` | Percorso del plugin `.so`; sovrascrive `ATS_PLUGIN_PATH` |
| `--non-interactive` | Non chiede nulla: fallisce se mancano valori obbligatori |
| `--validate-only` | Valida OS, configurazione e plugin senza installare nulla |
| `-h`, `--help` | Mostra help |

**Variabili principali in `ats-proxy.env`:**

| Variabile | Scopo | Stato test |
|-----------|-------|------------|
| `ATS_HOSTNAME` | Hostname del proxy | Testato |
| `ATS_IP_CIDR` | IP/CIDR della VM se `ATS_APPLY_NETPLAN=y` | Testato con netplan disattivo |
| `ATS_ALLOWED_SUBNET` | Subnet autorizzata su UFW e `ip_allow.yaml` | Testato |
| `ATS_ADMIN_IPS` | IP con bypass amministrativo nel plugin | Testato VM135 |
| `ATS_DENY_DOMAINS` | Domini bloccati dal plugin | Testato |
| `ATS_WHITELIST_DOMAINS` | Domini consentiti senza auth | Testato |
| `ATS_AUTH_USERS` | Utenti Basic Auth (`user:password`) | Testato |
| `ATS_PLUGIN_PATH` | Path al binario versionato `bin/ats_proxy_filter_v21.so` | Testato |
| `ATS_TLS_ENABLED` | Abilita frontend TLS su porta 8443 | Implementato, **non incluso** nella batteria e2e 2026-05-26 |

**Wrapper legacy supportati ma non necessari:**

```bash
# Verificano l'OS e poi delegano all'installer unico.
sudo bash scripts/install-24.04.sh --env ats-proxy.env --non-interactive
sudo bash scripts/install-26.04.sh --env ats-proxy.env --non-interactive
```

Il percorso supportato resta `scripts/install-ats-proxy.sh`: i wrapper esistono per impedire l'uso accidentale su OS errato.

**Procedura:**

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env

# Preflight: verifica locale della configurazione (non tocca il sistema)
bash scripts/preflight.sh --env ats-proxy.env

# Validazione completa senza installare (nessuna modifica al sistema)
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only

# Installazione completa
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive

# Oppure modalità interattiva (nessun file .env richiesto)
sudo bash scripts/install-ats-proxy.sh
```

### Percorso B — Installazione Manuale (per comprendere ogni step)

I passi seguenti spiegano cosa fa l'installer. Seguili se vuoi installare manualmente
o capire ogni fase del processo.

### Da pacchetto trasferibile (VM senza accesso diretto alla repo)

```bash
# Sul PC con accesso alla repo:
bash scripts/package-release.sh --output-dir dist --force

# Sulla VM:
tar -xzf ats-proxy-enterprise-YYYYMMDD.tar.gz
cd ats-proxy-enterprise
sudo bash scripts/install-ats-proxy.sh --env /percorso/ats-proxy.env --non-interactive
```

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
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2.sha512

# Verifica integrita — SHA512 verificato su entrambe le VM
sha512sum -c trafficserver-9.2.13.tar.bz2.sha512
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

echo '/usr/local/pcre/lib' | sudo tee /etc/ld.so.conf.d/pcre.conf
sudo ldconfig

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
| `--disable-examples` | Riduce superficie |
| `--disable-maintainer-mode` | Non necessario in produzione |

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
CONFIG proxy.config.http.flow_control.enabled INT 1
CONFIG proxy.config.http.per_server.connection.max INT 100
EOF
```

| Config chiave | Valore | Significato |
|---------------|--------|------------|
| `server_ports` | `8080` | Porta proxy |
| `url_remap.remap_required` | `0` | **FONDAMENTALE**: senza = 404 |
| `reverse_proxy.enabled` | `0` | Forward proxy puro |
| `dns.nameservers` | `NULL` | Delega a `/etc/resolv.conf` |
| `ram_cache.size` | `1073741824` | 1 GB RAM cache |
| `http.flow_control.enabled` | `1` | Previene saturazione lato client |
| `http.per_server.connection.max` | `100` | Limite connessioni per backend |

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

## 9. Plugin v2.1 — URL Filtering + Autenticazione

Il plugin `ats_proxy_filter_v21.so` fornisce tre funzioni:
- **Autenticazione**: `USER utente password` — richiede credenziali Proxy-Authorization Basic
- **Filtraggio URL**: `DENY dominio` / `WHITELIST dominio` — blocca o permette domini (supporta regex)
- **Admin bypass**: `ADMIN ip` — salta tutte le regole per gli IP specificati

### 9.1 Deploy del binario

```bash
sudo mkdir -p /opt/trafficserver/libexec/trafficserver
sudo install -o ats -g ats -m 755 ats_proxy_filter_v21.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
```

> **Nota**: ATS 9.2.13 carica i plugin da `/opt/trafficserver/libexec/trafficserver/`,
> NON da `/opt/trafficserver/lib/modules/`.

### 9.2 Configurazione plugin

```bash
sudo tee /etc/trafficserver/ats_proxy_filter.conf > /dev/null << 'EOF'
ADMIN 192.168.89.10
DENY httpbin.org
DENY bad.com
DENY malware.net
DENY .*\.ru$
WHITELIST google.com
WHITELIST github.com
WHITELIST ubuntu.com
WHITELIST example.com
USER admin:changeme
USER user1:changeme
EOF

sudo tee /etc/trafficserver/plugin.config > /dev/null << 'EOF'
ats_proxy_filter.so
EOF

sudo chown ats:ats /etc/trafficserver/ats_proxy_filter.conf /etc/trafficserver/plugin.config
sudo chmod 640 /etc/trafficserver/ats_proxy_filter.conf /etc/trafficserver/plugin.config
```

**Formato righe plugin:**

| Direttiva | Sintassi | Effetto |
|-----------|----------|---------|
| `ADMIN` | `ADMIN 192.168.1.10` | Bypassa tutte le regole per quell'IP |
| `DENY` | `DENY sito.com` o `DENY .*\.ru$` | Blocca il dominio (403) con supporto regex |
| `WHITELIST` | `WHITELIST google.com` | Permette esplicitamente il dominio |
| `USER` | `USER nome:password` | Autenticazione Basic (piu utenti consentiti) |

> **⚠️ Regola di precedenza**: ADMIN > WHITELIST > DENY. Se una richiesta non matcha
> WHITELIST e non proviene da ADMIN, riceve 407 (autenticazione richiesta).
> Se autenticata ma non matcha WHITELIST, riceve 503.

---

## 10. Servizio Systemd

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
sleep 3
```

> **Nota**: `RuntimeDirectory=trafficserver` crea `/run/trafficserver` automaticamente (necessario con `ProtectSystem=strict`).

---

## 11. Verifiche Post-Installazione

```bash
# 1. Porta in ascolto
sudo ss -tlnp | grep 8080
# Atteso: LISTEN ... traffic_server

# 2. HTTP proxy
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip
# Atteso: 200 (senza plugin) o 403/407 (con plugin)

# 3. HTTPS CONNECT
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 https://httpbin.org/ip
# Atteso: 200

# 4. Log audit
sudo tail -3 /var/lib/trafficserver/log/trafficserver/audit.log
# Atteso: contiene IP client, FQDN, status

# 5. Sintassi config
sudo /opt/trafficserver/bin/traffic_server -C verify_config
# Atteso: nessun errore

# 6. Concorrenza (10 richieste)
for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' -x http://localhost:8080 http://httpbin.org/ip & done; wait; echo ''
# Atteso: 200 200 200 200 200 200 200 200 200 200

# 7. Versione
/opt/trafficserver/bin/traffic_server -V 2>&1 | head -1
# Atteso: Traffic Server 9.2.13
```

### Verifica con batteria automatica

```bash
# Regression test (9 test: DENY, WHITELIST, AUTH, ADMIN bypass, CONNECT)
bash scripts/ats-regression-test.sh 8080 admin '<password>'
# Atteso: Passed 9 Failed 0

# Hardening check (25+ test: systemd, UFW, fail2ban, permessi, health check)
sudo bash scripts/ats-hardening-check.sh 8080
# Atteso: Passed 25 Failed 0 Warnings 0
```

---

## 12. Hardening

### 12.1 Firewall UFW

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp comment 'ATS-proxy'
echo 'y' | sudo ufw enable
```

> **🟢 26.04**: UFW backend e nftables (default). I comandi sono identici.

### 12.2 SSH Hardening

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

### 12.3 Sysctl — Kernel Hardening

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

### 12.4 Fail2ban — Jails SSH e ATS Proxy

```bash
sudo apt install -y fail2ban

# Filtro per tentativi di auth falliti sul proxy
sudo tee /etc/fail2ban/filter.d/ats-proxy.conf > /dev/null << 'EOF'
[Definition]
failregex = \[ats_proxy_filter\] AUTH FAIL .* from <HOST>
ignoreregex =
EOF

# Configurazione jail (SSH + ATS Proxy)
sudo mkdir -p /etc/fail2ban/jail.d
sudo tee /etc/fail2ban/jail.d/ats-proxy.local > /dev/null << 'EOF'
[sshd]
enabled = true
port = ssh
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
EOF

sudo systemctl enable --now fail2ban
```

### 12.5 Unattended Upgrades

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

### 12.6 etckeeper — Versionamento Configurazioni

```bash
sudo apt install -y etckeeper
sudo etckeeper init
sudo etckeeper commit "Configurazione iniziale ATS proxy enterprise"
```

### 12.7 Health Check Automatico

Lo script `/opt/ats_health.sh` verifica ogni 60 secondi che il proxy risponda con
un codice accettabile (200, 403, 407). Se il proxy non risponde, tenta un restart automatico.

```bash
sudo tee /opt/ats_health.sh > /dev/null << 'HEOF'
#!/bin/bash
HTTP=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://httpbin.org/ip 2>/dev/null)
STATUS=$(systemctl is-active trafficserver)
echo "[$(date -Is)] ATS=$STATUS HTTP=$HTTP" >> /var/log/ats-health.log
if [ "$HTTP" != "200" ] && [ "$HTTP" != "403" ] && [ "$HTTP" != "407" ]; then
  echo "[$(date -Is)] ALERT: proxy unhealthy HTTP=$HTTP, restarting" >> /var/log/ats-health.log
  /bin/systemctl restart trafficserver
fi
HEOF
sudo chmod +x /opt/ats_health.sh
sudo touch /var/log/ats-health.log
sudo chown root:adm /var/log/ats-health.log 2>/dev/null || sudo chown root:root /var/log/ats-health.log
sudo chmod 640 /var/log/ats-health.log
(sudo crontab -l 2>/dev/null; echo '* * * * * /opt/ats_health.sh') | sudo crontab -
```

### 12.8 CVE Helper

```bash
# Copia lo script di controllo CVE sul sistema
sudo install -o root -g root -m 750 scripts/cve-check.sh /opt/cve-check.sh
/opt/cve-check.sh
```

### 12.9 Verifica hardening

**Manuale:**
```bash
# Stato firewall
sudo ufw status verbose

# Stato fail2ban (entrambe le jail)
sudo fail2ban-client status sshd
sudo fail2ban-client status ats-proxy

# Stato unattended
systemctl is-active unattended-upgrades

# Log etckeeper
sudo git -C /etc log --oneline -3

# Stato health check
sudo tail -5 /var/log/ats-health.log

# CVE check
/opt/cve-check.sh
```

**Automatica:**
```bash
sudo bash scripts/ats-hardening-check.sh 8080
# Atteso: Passed 25 Failed 0 Warnings 0
```

---

## 13. Batteria Test di Verifica

Risultati verificati su **VM135 (24.04)** e **VM136 (26.04)** il 26 Maggio 2026.

### ACL (ip_allow.yaml)

| Test | VM135 (24.04) | VM136 (26.04) | Note |
|------|--------------|--------------|------|
| Deny /32 PRIMA di allow /24 | ✅ 000 (TCP block) | ✅ 000 | First-match |
| Allow /24 PRIMA di deny /32 | ✅ 200 (deny ignorato) | ✅ 200 | First-match |
| Reload senza restart (deny) | ✅ 200 (ignorato) | ✅ 200 | Serve restart |
| Restart con deny | ✅ 000 | ✅ 000 | TCP block |
| Rimozione deny + restart | ✅ 200 | ✅ 200 | Sblocco immediato |
| Allow /32 + deny /24 | ✅ 200 | ✅ 200 | Eccezione funziona |

### Plugin (v2.1 — URL Filtering + Auth)

| Test | VM135 (24.04) | VM136 (26.04) | Note |
|------|--------------|--------------|------|
| DENY dominio | ✅ 403 | ✅ 403 | Blocco URL |
| DENY regex `.*\.ru$` | ✅ 403 | ✅ 403 | Regex funzionante |
| WHITELIST dominio (senza auth) | ✅ 407 | ✅ 407 | Richiede autenticazione |
| WHITELIST + auth corretta | ✅ 301 | ✅ 301 | Redirect Google |
| ADMIN bypass (senza auth) | ✅ 200 | ✅ 200 | Admin salta tutto |
| Auth fallita (password errata) | ✅ 401 | ✅ 401 | Credenziali rifiutate |
| HTTPS CONNECT con auth | ✅ 200 | ✅ 200 | Tunnel funzionante |
| Dominio non in whitelist con auth | ✅ 503 | ✅ 503 | Servizio non disponibile |

### Logging

| Test | Entrambe | Note |
|------|----------|------|
| HTTP: FQDN nel log | ✅ | `%<{Host}cqh>` corretto |
| HTTPS CONNECT: FQDN nel log | ✅ | CONNECT + porta loggati |
| `%<{SERVC}pquc>` IP backend | ❌ | Non valido, usare `%<shn>` |
| Rolling giornaliero | ✅ | File ruotati ogni 86400 sec |

### Resilienza

| Test | VM135 | VM136 |
|------|-------|-------|
| Stop/start pulito | ✅ | ✅ |
| 10 richieste concorrenti | ✅ (200×10) | ✅ (200×10) |
| Protezione lock file | ✅ | ✅ |
| Health check auto-restart | ✅ | ✅ |
| fail2ban ats-proxy jail | ✅ | ✅ |

---

## 14. Troubleshooting

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
| Plugin non caricato (nessun filtro) | Binario nella directory sbagliata | Deploy in `/opt/trafficserver/libexec/trafficserver/` |
| `ats-proxy` jail assente | fail2ban < 0.11 o jail.d non letto | Verificare `/etc/fail2ban/jail.d/ats-proxy.local` |
| DENY non applicato a dominio test | DNS cache su hook OS_DNS | Riavviare ATS tra un test e l'altro: `systemctl restart trafficserver` |

---

## 15. Checklist Pre-Produzione

- [ ] OS verificato (`lsb_release -a`)
- [ ] ATS 9.2.13 compilato, SHA512 verificato
- [ ] Utente `ats` con shell `/usr/sbin/nologin`
- [ ] Ownership `ats:ats` su `/opt`, `/etc/trafficserver`, `/var/lib/trafficserver`
- [ ] `url_remap.remap_required=0`, `reverse_proxy.enabled=0`
- [ ] `ip_allow.yaml` con subnet corrette, deny PRIMA di allow (se applicabile)
- [ ] `logging.yaml` con FQDN e status
- [ ] Plugin `.so` in `/opt/trafficserver/libexec/trafficserver/`
- [ ] `plugin.config` e `ats_proxy_filter.conf` presenti con permessi 640
- [ ] Servizio systemd attivo con hardening completo
- [ ] UFW attivo: SSH (22/tcp) e proxy (8080/tcp) autorizzati
- [ ] SSH hardening: key-only, no root
- [ ] fail2ban attivo (jail SSH + ats-proxy)
- [ ] unattended-upgrades attivo
- [ ] etckeeper attivo
- [ ] Health check `/opt/ats_health.sh` in cron ogni minuto
- [ ] CVE helper `/opt/cve-check.sh` installato
- [ ] Test proxy HTTP e HTTPS → 200
- [ ] Test 10 richieste concorrenti → tutte 200
- [ ] Test ACL da IP remoto (deny PRIMA di allow)
- [ ] Log audit contiene FQDN con rolling giornaliero
- [ ] Regression test: `Passed 9 Failed 0`
- [ ] Hardening check: `Passed 25 Failed 0 Warnings 0`

---

## 16. Riepilogo Differenze 24.04 vs 26.04

| Aspetto | 24.04 Noble (VM135) | 26.04 Resolute (VM136) |
|---------|--------------------|------------------------|
| Kernel | 6.8.x | 6.14.x+ |
| GCC | 13.x | **15.2.0** |
| OpenSSL | 3.0.x LTS | **3.5.5** |
| PCRE1 | `libpcre3-dev` (apt) | **Da sorgente** (`/usr/local/pcre`) |
| PCRE2 | 10.x | 10.46 |
| libncurses | `libncurses5-dev` | **`libncurses-dev`** |
| Configure flag | `--enable-pcre` | **`--with-pcre=/usr/local/pcre`** |
| UFW backend | iptables | nftables (comandi identici) |
| Supporto LTS | 10 anni (2034) | 12 anni (2038) |
| Plugin binary | `ats_proxy_filter_v21.so` | `ats_proxy_filter_v21.so` |

---

## 17. Comandi di Manutenzione Rapida

```bash
# Stato servizio
sudo systemctl status trafficserver

# Restart / Reload
sudo systemctl restart trafficserver
sudo /opt/trafficserver/bin/traffic_ctl config reload

# Log in tempo reale
sudo journalctl -u trafficserver -f
sudo tail -f /var/lib/trafficserver/log/trafficserver/audit.log
sudo tail -f /var/log/ats-health.log

# Monitoraggio
/opt/trafficserver/bin/traffic_top
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# Verifica sintassi
/opt/trafficserver/bin/traffic_server -C verify_config

# Backup configurazioni
sudo tar czf ats-config-backup-$(date +%Y%m%d).tar.gz /etc/trafficserver/
sudo etckeeper commit "Descrizione modifica"

# Verifica hardening
sudo bash scripts/ats-hardening-check.sh 8080

# Verifica regressione plugin
bash scripts/ats-regression-test.sh 8080 admin '<password>'

# Controllo CVE
/opt/cve-check.sh
```

---

*Guida basata su test reali: VM135 (24.04) e VM136 (26.04), 26 Maggio 2026*
