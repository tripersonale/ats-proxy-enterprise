# Apache Traffic Server 9.2.13 LTS — Guida di Installazione

## Ubuntu 26.04 LTS (Resolute Raccoon) — Proxy Outbound Enterprise

**Versione 1.1 — 24 Maggio 2026 — TESTATA su VM 134 (ats-proxy-02, 192.168.89.28)**

---

## Scelta architetturale

| Componente | Scelta | Motivazione |
|-----------|--------|------------|
| OS | Ubuntu 26.04 LTS | Supporto 12 anni (2038), kernel 6.14+, toolchain aggiornata, dipendenze stabili |
| ATS | 9.2.13 LTS (compilato) | Chiude 11 CVE, non nei repo (fermo a 9.2.3 o rimosso), Debian lo sta rimuovendo |
| PCRE | PCRE1 8.45 (da sorgente) | libpcre3-dev RIMOSSO dai repo 26.04; `--enable-pcre2` NON supportato da ATS 9.2.13 |
| Compilazione | Da sorgente + PCRE1 separato | Unica strada: pacchetto apt fermo a 9.2.3, PCRE1 non piu nei repo |

**Risultati reali VM 134 (2026-05-24)**: GCC 15.2.0, OpenSSL 3.5.5, PCRE2 10.46 (nativo), PCRE1 assente. Compilazione riuscita con PCRE1 8.45 da sorgente in `/usr/local/pcre`.

---

## 1. Prerequisiti

- Ubuntu Server 26.04 LTS (Resolute Raccoon) — installazione server, architettura amd64
- RAM: minimo 2 GB (consigliati 4+ GB per produzione)
- Disco: 10+ GB dedicati alla cache
- Accesso: utente con `sudo`
- Connettivita: Internet per download sorgenti e dipendenze

---

## 2. Preparazione Sistema

```bash
# Verifica versione OS
lsb_release -a
# Atteso: Description: Ubuntu 26.04 LTS, Codename: resolute

# Aggiornamento sistema
sudo apt update && sudo apt upgrade -y

# Installazione dipendenze build
# NOTA su 26.04: libpcre3-dev potrebbe NON essere disponibile.
# Provare prima con entrambi, se libpcre3-dev manca, vedere Sezione 5bis (PCRE1 da sorgente).
sudo apt install -y \
  build-essential gcc g++ make libtool autoconf automake pkg-config python3-dev \
  libssl-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev \
  libncurses5-dev libxml2-dev libjson-c-dev libcurl4-openssl-dev libunwind-dev \
  git wget curl tar gzip bzip2

# Se libpcre3-dev e disponibile (verificare):
sudo apt install -y libpcre3-dev 2>/dev/null || echo "libpcre3-dev non disponibile, vedi Sezione 5bis"
```

### Verifica

```bash
dpkg -l | grep -E "(build-essential|libssl-dev|libpcre)" | wc -l
# Atteso: >= 3
```

### Differenze dipendenze 24.04 vs 26.04 (VERIFICATE su VM reali)

| Pacchetto | 24.04 Noble | 26.04 Resolute (REALE) | Note |
|-----------|------------|------------------------|------|
| `gcc` | 13.x | **15.2.0** | Nessun impatto su ATS, warning piu severi |
| `libssl-dev` | 3.0.x | **3.5.5** | Retrocompatibile, API stabili |
| `libpcre3-dev` | Disponibile | **ASSENTE** ✅ | PCRE1 deprecato e rimosso da Ubuntu 26.04 |
| `libpcre2-dev` | 10.x | **10.46** | Disponibile in entrambi |
| `libncurses-dev` / `libncurses5-dev` | `libncurses5-dev` | **`libncurses-dev`** | Nome pacchetto cambiato in 26.04 |

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

**ATTENZIONE — VERIFICA INTEGRITA** (miglioramento rispetto a guida 24.04):

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2.sha256

# Verifica checksum SHA256
sha256sum -c trafficserver-9.2.13.tar.bz2.sha256
# Atteso: trafficserver-9.2.13.tar.bz2: OK

# Verifica
ls -lh trafficserver-9.2.13.tar.bz2
# Atteso: ~9.7 MB

tar -xjf trafficserver-9.2.13.tar.bz2
cd trafficserver-9.2.13
```

---

## 5. Compilazione

### 5.1 Preparazione autotools

```bash
autoreconf -if
ls -la configure  # Deve esistere
```

### 5.2 Verifica PCRE

```bash
# Verifica se pcre-config e disponibile (PCRE1)
which pcre-config && pcre-config --version

# Verifica se pcre2-config e disponibile (PCRE2)
which pcre2-config && pcre2-config --version
```

### 5.3 Configura build

**⚠️ RISULTATO REALE VM 134**: `--enable-pcre2` **NON funziona** con ATS 9.2.13. L'unica opzione su Ubuntu 26.04 e compilare PCRE1 da sorgente (Sezione 5bis) e usare `--with-pcre=/usr/local/pcre`:

```bash
export PKG_CONFIG_PATH='/usr/local/pcre/lib/pkgconfig'
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
  --with-pcre=/usr/local/pcre \
  --disable-tests \
  --disable-examples \
  --disable-maintainer-mode

### Opzioni spiegate

| Flag | Significato |
|------|------------|
| `--prefix=/opt/trafficserver` | Installazione isolata in /opt (standard enterprise) |
| `--with-user=ats --with-group=ats` | Compila per utente dedicato |
| `--with-pcre=/usr/local/pcre` | Percorso PCRE1 compilato da sorgente (Sezione 5bis) |
| `--disable-tests` | Esclude test suite (riduce superficie d'attacco) |
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

## 5bis. Compilare PCRE1 da sorgente (OBBLIGATORIO su 26.04)

**VERIFICATO su VM 134**: `libpcre3-dev` NON e disponibile nei repo di Ubuntu 26.04. `--enable-pcre2` NON e supportato da ATS 9.2.13. **Occorre compilare PCRE1 da sorgente** (versione 8.45, ultima stabile):

```bash
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz.sha256
sha256sum -c pcre-8.45.tar.gz.sha256
tar xzf pcre-8.45.tar.gz
cd pcre-8.45

./configure --prefix=/usr/local/pcre --enable-utf8 --enable-unicode-properties
make -j$(nproc)
sudo make install

# Aggiorna variabili per il configure di ATS
export PKG_CONFIG_PATH="/usr/local/pcre/lib/pkgconfig:$PKG_CONFIG_PATH"
export PATH="/usr/local/pcre/bin:$PATH"

# Poi tornare a Sezione 5.3 Scenario A
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
| `url_remap.remap_required` | `0` | **FONDAMENTALE**: senza questo ATS restituisce 404 |
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

**SOSTITUIRE** `192.168.89.0/24` con la tua subnet reale.

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
    action: deny        # ← ignorato, l'allow /24 ha gia matchato!
    method: ALL
```

**⚠️ CRITICO: `traffic_ctl config reload` NON applica i deny in `ip_allow.yaml`. Per attivare un blocco serve RESTART COMPLETO.**

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

# Hardening systemd (miglioramenti per 26.04)
# Protezione filesystem
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/trafficserver /opt/trafficserver/var/trafficserver /opt/trafficserver/var/log/trafficserver /run/trafficserver
ReadOnlyPaths=/opt/trafficserver

# Isolamento rete e utente
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true

# Limiti risorse (adattare alla VM)
MemoryHigh=2G
MemoryMax=3G
CPUQuota=400%

[Install]
WantedBy=multi-user.target
EOF
```

### Miglioramenti systemd rispetto a guida 24.04:

| Direttiva | Effetto |
|-----------|---------|
| `ProtectSystem=strict` | Monta /usr e /etc read-only (tranne i path in ReadWritePaths) |
| `ProtectHome=true` | Rende /home, /root inaccessibili |
| `NoNewPrivileges=true` | Impedisce escalation privilegi via setuid |
| `PrivateTmp=true` | /tmp privato per il servizio (hardening automatico) |
| `PrivateDevices=true` | Device node minimi |
| `MemoryHigh=2G` | Throttling soft a 2 GB |
| `MemoryMax=3G` | OOM kill oltre 3 GB |
| `CPUQuota=400%` | Max 4 core equivalenti |

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

**ATTENZIONE**: Su Ubuntu 26.04, UFW potrebbe usare nftables come backend (default). Il comportamento e identico. Verificare con:
```bash
sudo ufw status verbose | head -1
# Se mostra "nft" o "iptables", funziona correttamente
```

### 10.2 Hardening SSH

**MIGLIORAMENTO rispetto a guida 24.04** — hardening accesso amministrativo:

```bash
sudo tee -a /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'EOF'
# Hardening SSH per server enterprise
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ubuntu
EOF

# Verifica sintassi e riavvia
sudo sshd -t && sudo systemctl restart sshd
```

**PRIMA di eseguire**: assicurarsi di avere una chiave SSH configurata e funzionante, altrimenti si perde l'accesso.

### 10.3 Sysctl — Ottimizzazioni Kernel

```bash
sudo tee -a /etc/sysctl.d/99-ats-hardening.conf > /dev/null << 'EOF'
# Hardening rete per Proxy ATS
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

### 10.4 Permessi File

```bash
sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
sudo chown -R ats:ats /etc/trafficserver /opt/trafficserver/var/trafficserver /opt/trafficserver/var/log/trafficserver
```

### 10.5 Unattended Upgrades (NUOVO per 26.04)

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

### 10.6 Audit delle modifiche di configurazione (NUOVO per 26.04)

```bash
# Installa etckeeper per versionare /etc
sudo apt install -y etckeeper

# Inizializza git in /etc
sudo etckeeper init
sudo etckeeper commit "Configurazione iniziale ATS proxy enterprise"

# Dopo ogni modifica:
sudo etckeeper commit "Aggiornamento ip_allow.yaml: aggiunta subnet 10.0.0.0/8"
```

---

## 11. Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| `404 Not Found` dal proxy | `url_remap.remap_required` non impostato a 0 | Aggiungere `CONFIG proxy.config.url_remap.remap_required INT 0` |
| `configure: error: Cannot find pcre` | Manca PCRE1 (rimosso da 26.04) | Compilare PCRE1 da sorgente (Sez. 5bis) e usare `--with-pcre=/usr/local/pcre` |
| Log non creati | Directory log mancante | `sudo mkdir -p /opt/trafficserver/var/trafficserver/log/trafficserver && sudo chown ats:ats /opt/trafficserver/var/trafficserver/log/trafficserver` |
| Servizio non parte (status: inactive) | Lock file da processo precedente | `sudo rm -f /opt/trafficserver/var/trafficserver/manager.lock /opt/trafficserver/var/trafficserver/server.lock` |
| Deny /32 NON blocca | **reload non basta, serve RESTART**; allow /24 viene PRIMA del deny | `sudo systemctl restart trafficserver` + mettere deny PRIMA di allow |
| `Can't acquire manager lockfile` | traffic_manager zombie | `sudo pkill -9 traffic_manager && sudo rm /opt/trafficserver/var/trafficserver/manager.lock` |
| `traffic_server: error while loading shared libraries` | ldconfig mancante | `sudo ldconfig` |
| Log format vuoto dopo restart | `logging.yaml` ha priorita su `logs_xml.config` | Usare `logging.yaml` per il formato |
| Connessione SSH persa dopo UFW | SSH non in allow list | Aggiungere `sudo ufw allow 22/tcp` PRIMA di `ufw enable` |
| `traffic_server` aborted (core dump) | Lock file o socket sporchi | `sudo rm -f /opt/trafficserver/var/trafficserver/*.lock /opt/trafficserver/var/trafficserver/*.sock` |
| Systemd: `ProtectSystem=strict` blocca scrittura | ReadWritePaths non include la directory | Aggiungere il path a `ReadWritePaths=` nella unit systemd |
| `configure: error: OpenSSL too old` su 26.04 | OpenSSL 3.4 richiede flag aggiuntivo | Verificare: `./configure --help \| grep ssl`; potrebbe servire `--with-openssl=/usr` |

---

## 12. Checklist Pre-Produzione

- [ ] Ubuntu 26.04 LTS verificato (`lsb_release -a` → resolute)
- [ ] ATS 9.2.13 compilato senza errori (con PCRE1 o PCRE2)
- [ ] Utente `ats` esiste con shell `/usr/sbin/nologin`
- [ ] Ownership `ats:ats` su `/opt/trafficserver`, `/etc/trafficserver`, `/opt/trafficserver/var/trafficserver`
- [ ] `records.config` verificato: `url_remap.remap_required=0`, `reverse_proxy.enabled=0`
- [ ] `ip_allow.yaml` contiene le subnet corrette (rimosso deny-all temporaneo)
- [ ] `logging.yaml` con formato audit (FQDN + status)
- [ ] Servizio `trafficserver.service` abilitato e attivo
- [ ] UFW attivo con SSH e porta proxy autorizzate
- [ ] SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no`
- [ ] `unattended-upgrades` attivo per security updates
- [ ] `etckeeper` attivo per versionamento configurazioni
- [ ] Log rotation attiva (rolling 86400 secondi)
- [ ] Systemd hardening: `ProtectSystem=strict`, `PrivateTmp=true`, `NoNewPrivileges=true`
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

# Versionamento configurazioni (etckeeper)
sudo etckeeper commit "Descrizione modifica"
```

---

## 14. Differenze Chiave 24.04 vs 26.04 (VERIFICATE con VM reali)

| Aspetto | Ubuntu 24.04 Noble (VM 130) | Ubuntu 26.04 Resolute (VM 134) | Impatto su ATS |
|---------|----------------------------|-------------------------------|----------------|
| Kernel | 6.8.x | 6.14.x+ | Prestazioni rete migliorate |
| GCC | 13.x | **15.2.0** | Nessun errore, warning piu severi |
| OpenSSL | 3.0.x LTS | **3.5.5** | API compatibili, performance TLS migliorate |
| PCRE1 (libpcre3) | Disponibile (apt) | **ASSENTE** — compilare da sorgente | Richiede sezione 5bis OBBLIGATORIA |
| PCRE2 (libpcre2) | 10.x | **10.46** | Disponibile nativamente |
| --enable-pcre2 | Non testato | **NON FUNZIONA** con ATS 9.2.13 | Non usare |
| libncurses | `libncurses5-dev` | **`libncurses-dev`** | Cambio nome pacchetto |
| Systemd | 255.x | 257.x+ | Nuove direttive di hardening |
| Firewall backend | iptables | nftables | UFW astrae la differenza |
| Python | 3.12 | 3.14 | Nessun impatto |
| Supporto LTS | 10 anni (fino 2034) | 12 anni (fino 2038) | Estensione ciclo vita |

---

## 15. Risultati Batteria Test (24.04 — validi anche per 26.04)

I test ACL e logging sono invarianti rispetto alla versione OS, poiche dipendono solo da ATS 9.2.13. I risultati della guida 24.04 sono applicabili anche a 26.04.

### ACL (ip_allow.yaml)

| Test | Risultato | Note |
|------|-----------|------|
| Deny /32 PRIMA di allow /24 | ✅ Bloccato | **First-match: ordine CONTA.** |
| Allow /24 PRIMA di deny /32 | ❌ Permesso | Il deny dopo viene IGNORATO. |
| Deny /32 isolato (no allow /24) | ✅ Bloccato | Con restart, deny funziona. |
| Rimozione deny → ripristino | ✅ Sbloccato | L'IP torna a funzionare dopo restart. |
| Reload SENZA restart | ❌ Ignorato | **`traffic_ctl config reload` NON applica i deny.** |
| Restart CON deny | ✅ Bloccato | Il deny blocca a livello TCP (connection fail). |

### Logging

| Test | Risultato | Note |
|------|-----------|------|
| HTTP: FQDN + backend | ✅ | `%<{Host}cqh>` e `%<shn>` entrambi presenti |
| HTTPS CONNECT: FQDN | ✅ | `CONNECT ...:443/` loggato con FQDN |
| `%<{SERVC}pquc>` IP backend | ❌ | Non valido in logging.yaml — usare `%<shn>` |

### Resilienza

| Test | Risultato | Note |
|------|-----------|------|
| Stop/start pulito | ✅ | Nessun lock file bloccante |
| 10 richieste concorrenti | ✅ | Tutte 200 OK |
| Reload records parziale | ✅ | Il proxy resta attivo |

**Regola d'oro**: testare sempre con IP remoti. I test da localhost non validano le ACL reali.

---

*Guida testata su VM reale: Ubuntu 26.04 LTS (Resolute Raccoon) + ATS 9.2.13 compilato da sorgente + PCRE1 8.45*
*VM 134 — IP: 192.168.89.28 | Porta: 8080 | Proxmox*
