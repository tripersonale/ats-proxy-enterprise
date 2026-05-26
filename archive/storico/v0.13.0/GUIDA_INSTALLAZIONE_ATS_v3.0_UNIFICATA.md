# Apache Traffic Server 9.2.13 - Guida Unificata Di Installazione

Versione documento: **4.0 corrente**, mantenuta con nome storico per continuita.  
Baseline testata: **ATS Proxy Enterprise 0.13.0**, Ubuntu 24.04.4 VM135 e Ubuntu 26.04 VM136, test end-to-end del 2026-05-26.

Questa guida mantiene il dettaglio manuale della precedente v3.0, ma il percorso raccomandato e l'installer `scripts/install-ats-proxy.sh`, perche e l'unico percorso verificato automaticamente su entrambe le VM.

## Esito Di Validazione

| Target | Installer | Regression | Hardening |
|--------|-----------|------------|-----------|
| Ubuntu 24.04.4 Noble, VM135 | OK | 9/9 OK | 25/25 OK |
| Ubuntu 26.04 Resolute, VM136 | OK | 9/9 OK | 25/25 OK |

Comandi di verifica usati:

```bash
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

## Architettura Installata

```text
Client -> UFW:8080 -> ip_allow.yaml -> ats_proxy_filter.so -> upstream
                                      |-> ADMIN bypass
                                      |-> DENY 403 Forbidden
                                      |-> WHITELIST pass
                                      |-> AUTH 407 / pass con credenziali
```

Percorsi installati:

| Componente | Percorso |
|------------|----------|
| ATS | `/opt/trafficserver` |
| Config | `/etc/trafficserver` |
| Stato/cache/log | `/var/lib/trafficserver` |
| Plugin | `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so` |
| Config plugin | `/etc/trafficserver/ats_proxy_filter.conf` |
| Service | `/etc/systemd/system/trafficserver.service` |
| Health check | `/opt/ats_health.sh` |

## Librerie E Dipendenze Da Mantenere

| Libreria | Ubuntu 24.04 | Ubuntu 26.04 | Motivo | Manutenzione |
|----------|--------------|--------------|--------|--------------|
| ATS | 9.2.13 sorgente | 9.2.13 sorgente | Core proxy | monitor Apache Traffic Server announce |
| PCRE1 | `libpcre3-dev` 8.39 da apt | PCRE1 8.45 da sorgente in `/usr/local/pcre` | ATS 9.2.13 non usa PCRE2 come sostituto diretto | CVE NVD, ricompilare ATS se cambia |
| PCRE2 | `libpcre2-dev` | `libpcre2-dev` | dipendenza ambiente/build, non sostituisce PCRE1 | apt security |
| OpenSSL | 3.0.x | 3.5.x | TLS e crypto | Ubuntu Security Notices, OpenSSL advisories |
| zlib | apt | apt | compressione | apt security |
| libcurl | apt | apt | dipendenza build/runtime | curl security, apt security |
| libxml2 | apt | apt | parsing/config dependency | GNOME/libxml2 advisories |
| libjson-c | apt | apt | JSON dependency | json-c releases, apt security |
| libcap | apt | apt | capability runtime | apt security |
| hwloc | apt | apt | CPU/thread affinity | apt security |
| libunwind | apt | apt | diagnostics/backtrace | apt security |
| ncurses | `libncurses5-dev` | `libncurses-dev` | build tools | apt security |
| GCC/G++ | 13.x | 15.x | compilazione ATS/plugin | toolchain Ubuntu |

Nota critica: `--enable-pcre2` non e il percorso validato per ATS 9.2.13. Su Ubuntu 26.04 serve PCRE1 8.45 da sorgente.

## Percorso Raccomandato: Installer

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env

bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

Il file config supporta variabili `ATS_*`. Senza `--non-interactive`, lo script chiede i valori mancanti o ancora `CHANGE_ME`.

## Dipendenze Manuali 24.04

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  build-essential gcc g++ make libtool autoconf automake pkg-config python3-dev \
  libssl-dev libpcre3-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev \
  libncurses5-dev libxml2-dev libjson-c-dev libcurl4-openssl-dev libunwind-dev \
  git wget curl tar gzip bzip2 fail2ban ufw unattended-upgrades etckeeper
```

## Dipendenze Manuali 26.04

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  build-essential gcc g++ make libtool autoconf automake pkg-config python3-dev \
  libssl-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev libncurses-dev \
  libxml2-dev libjson-c-dev libcurl4-openssl-dev libunwind-dev \
  git wget curl tar gzip bzip2 fail2ban ufw unattended-upgrades etckeeper
```

PCRE1 su 26.04:

```bash
cd /tmp
curl -fL -o pcre-8.45.tar.gz https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz
tar xzf pcre-8.45.tar.gz
cd pcre-8.45
./configure --prefix=/usr/local/pcre --enable-utf8 --enable-unicode-properties
make -j$(nproc)
sudo make install
echo '/usr/local/pcre/lib' | sudo tee /etc/ld.so.conf.d/pcre.conf
sudo ldconfig
```

## Build Manuale ATS 9.2.13

Il download validato usa SHA512:

```text
46c291bc08cf3a73d5d2dd70f006c654c8f91ff5f6d7b28fa539ef2f10147fe27d6fac714b4cec06b3930945db6717b8f4714f990a3b77c1699e11fc218e7766
```

```bash
sudo groupadd --system ats 2>/dev/null || true
sudo useradd --system --gid ats --home-dir /opt/trafficserver --shell /usr/sbin/nologin ats 2>/dev/null || true

cd /tmp
curl -fL -o trafficserver-9.2.13.tar.bz2 https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2
printf '%s *trafficserver-9.2.13.tar.bz2\n' \
  '46c291bc08cf3a73d5d2dd70f006c654c8f91ff5f6d7b28fa539ef2f10147fe27d6fac714b4cec06b3930945db6717b8f4714f990a3b77c1699e11fc218e7766' | sha512sum -c -
tar -xjf trafficserver-9.2.13.tar.bz2
cd trafficserver-9.2.13
autoreconf -if
```

Configure 24.04:

```bash
./configure --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --enable-pcre \
  --disable-tests --disable-examples --disable-maintainer-mode
```

Configure 26.04:

```bash
export PKG_CONFIG_PATH=/usr/local/pcre/lib/pkgconfig
./configure --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --with-pcre=/usr/local/pcre \
  --disable-tests --disable-examples --disable-maintainer-mode
```

Installazione:

```bash
make -j$(nproc)
sudo make install
echo /opt/trafficserver/lib | sudo tee /etc/ld.so.conf.d/trafficserver.conf
sudo ldconfig
```

## Configurazione ATS Essenziale

`records.config` deve includere almeno:

```text
CONFIG proxy.config.http.server_ports STRING 8080
CONFIG proxy.config.proxy_name STRING ats-proxy
CONFIG proxy.config.log.logging_enabled INT 3
CONFIG proxy.config.dns.nameservers STRING NULL
CONFIG proxy.config.dns.resolv_conf STRING /etc/resolv.conf
CONFIG proxy.config.http.insert_client_ip INT 1
CONFIG proxy.config.url_remap.remap_required INT 0
CONFIG proxy.config.reverse_proxy.enabled INT 0
CONFIG proxy.config.http.flow_control.enabled INT 1
CONFIG proxy.config.http.per_server.connection.max INT 100
```

`ip_allow.yaml`:

```yaml
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
```

`logging.yaml`:

```yaml
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
```

Permessi dopo ogni modifica:

```bash
sudo chown ats:ats /etc/trafficserver/*
sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
```

## Plugin

```bash
sudo install -o ats -g ats -m 755 bin/ats_proxy_filter_v21.so /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo tee /etc/trafficserver/plugin.config >/dev/null <<'EOF'
ats_proxy_filter.so
EOF
sudo tee /etc/trafficserver/ats_proxy_filter.conf >/dev/null <<'EOF'
ADMIN 192.168.89.10
DENY httpbin.org
DENY bad.com
WHITELIST google.com
WHITELIST github.com
USER admin CAMBIARE_PASSWORD
EOF
sudo chown ats:ats /etc/trafficserver/plugin.config /etc/trafficserver/ats_proxy_filter.conf
sudo chmod 640 /etc/trafficserver/plugin.config /etc/trafficserver/ats_proxy_filter.conf
```

## Systemd Hardened

Il service validato include:

```ini
[Service]
Type=forking
User=ats
Group=ats
RuntimeDirectory=trafficserver
ExecStart=/opt/trafficserver/bin/trafficserver start
ExecStop=/opt/trafficserver/bin/trafficserver stop
Restart=on-failure
LimitNOFILE=65535
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
```

## Hardening Validato

- UFW deny incoming, allow outgoing, allow SSH, allow proxy only from subnet autorizzata.
- SSH root login off, password auth off, max auth tries 3.
- fail2ban `sshd` e `ats-proxy` attivi.
- unattended upgrades enabled/active.
- etckeeper inizializzato su `/etc`.
- sysctl hardening applicato.
- health check ogni minuto in cron.

Verifica:

```bash
sudo bash scripts/ats-hardening-check.sh 8080
```

## Troubleshooting Installazione

| Sintomo | Causa probabile | Fix |
|---------|-----------------|-----|
| `ERR_INVALID_URL` o 404 da forward proxy | `remap_required=1` o reverse proxy attivo | impostare `url_remap.remap_required=0`, `reverse_proxy.enabled=0`, restart |
| Plugin non caricato | path errato | installare in `/opt/trafficserver/libexec/trafficserver/` |
| 26.04 non trova PCRE | PCRE1 assente nei repo | compilare PCRE1 8.45 in `/usr/local/pcre` |
| fail2ban jail `ats-proxy` assente | servizio non riavviato dopo scrittura jail | `sudo systemctl restart fail2ban` |
| DENY incoerente dopo test ripetuti | cache DNS con `TS_HTTP_OS_DNS_HOOK` | restart ATS per test policy, valutare hook diverso in sviluppo futuro |

## Stato Non Validato

- TLS frontend opzionale 8443 non incluso nel test end-to-end 0.13.0.
- ATS 10.x non e baseline supportata.
- Carico oltre 50 concorrenti non testato in questa sessione.
