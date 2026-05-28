# ATS Proxy Enterprise v3.0 — Guida di Installazione

## Ubuntu 26.04 LTS · Apache Traffic Server 9.2.13 LTS

**Testata copia-incolla su VM137 il 2026-05-28: ogni comando verificato. Hardening 25/25, 5 mode OK.**

---

## 0. Preparazione: clona la repo

```bash
cd ~
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
```

📁 La repo contiene script e template. ATS verrà installato in `/opt/trafficserver`.
📁 Config ATS: `/opt/trafficserver/etc/trafficserver/`.
📁 Config plugin: `/etc/trafficserver/plugin/`.

> **Offline?** Scarica il [ZIP](https://github.com/tripersonale/ats-proxy-enterprise/archive/refs/heads/main.zip)

---

## 1. Dipendenze

```bash
sudo apt update
sudo apt install -y build-essential gcc g++ make libtool autoconf automake \
  pkg-config libssl-dev zlib1g-dev libcap-dev libhwloc-dev libunwind-dev \
  libcurl4-openssl-dev tcl-dev git wget curl
```

## 2. PCRE 8.45

```bash
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.bz2/download \
  -O pcre-8.45.tar.bz2
tar -xjf pcre-8.45.tar.bz2 && cd pcre-8.45
./configure --prefix=/usr/local/pcre --enable-utf --enable-unicode-properties
make -j"$(nproc)" && sudo make install && sudo ldconfig
```
**Verifica**: `ls /usr/local/pcre/lib/libpcre.so`

## 3. ATS 9.2.13

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2
tar -xjf trafficserver-9.2.13.tar.bz2 && cd trafficserver-9.2.13
autoreconf -fi
./configure --prefix=/opt/trafficserver --with-pcre=/usr/local/pcre
make -j"$(nproc)" && sudo make install
```
**Verifica**: `/opt/trafficserver/bin/traffic_server -V`

## 4. Forward proxy

```bash
sudo sed -i 's/CONFIG proxy.config.reverse_proxy.enabled INT 1/CONFIG proxy.config.reverse_proxy.enabled INT 0/' \
  /opt/trafficserver/etc/trafficserver/records.config
sudo sed -i 's/CONFIG proxy.config.url_remap.remap_required INT 1/CONFIG proxy.config.url_remap.remap_required INT 0/' \
  /opt/trafficserver/etc/trafficserver/records.config
```

## 5. Avvia e verifica L0

Prima di avviare, crea la directory dei log con i permessi corretti:

```bash
sudo mkdir -p /var/log/trafficserver
sudo chown ats:ats /var/log/trafficserver
sudo chmod 755 /var/log/trafficserver
```

```bash
sudo /opt/trafficserver/bin/trafficserver start
sleep 4
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
```
**Atteso**: `200`

## 6. Compila plugin v3

📁 `cd ~/ats-proxy-enterprise`

```bash
bash scripts/compile-plugin.sh --ats-src /tmp/trafficserver-9.2.13 \
  --out bin/ats_proxy_filter_v30.so --c
```

## 7. Installa plugin

```bash
sudo cp bin/ats_proxy_filter_v30.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so

sudo bash scripts/ats-ctl init
sudo bash scripts/ats-ctl mode deny
sudo bash scripts/ats-ctl deny add httpbin.org

echo 'ats_proxy_filter_v30.so /etc/trafficserver/plugin/filter.conf' | \
  sudo tee /opt/trafficserver/etc/trafficserver/plugin.config > /dev/null

sudo /opt/trafficserver/bin/trafficserver restart
sleep 4
```

**Verifica**:
```bash
# httpbin.org bloccato → 403
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://httpbin.org/ip
# example.com passa → 200
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
```

> **Come funziona**: `plugin.config` contiene `ats_proxy_filter_v30.so /etc/trafficserver/plugin/filter.conf`.
> Il plugin legge il secondo argomento come path della directory di configurazione (default `/etc/trafficserver/plugin`).
> Dentro quella directory cerca `filter.conf`, `deny.list`, `whitelist.list`, `admin.list`, `auth.conf`.

## 8. Hardening

```bash
sudo bash scripts/apply-ats-hardening-v3.sh
sudo bash scripts/ats-ctl reload

# Network hardening
sudo apt install -y ufw fail2ban etckeeper
sudo ufw --force enable
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp comment ats-proxy
sudo ufw allow from 192.168.89.0/24 to any port 22 proto tcp comment ssh-admin

sudo tee /etc/fail2ban/filter.d/ats-proxy.conf << 'EOF' > /dev/null
[Definition]
failregex = AUTH FAIL user=.* from=<HOST>
ignoreregex =
EOF

sudo tee /etc/fail2ban/jail.d/ats-proxy.local << 'EOF' > /dev/null
[ats-proxy]
enabled = true
port = 8080
filter = ats-proxy
logpath = /var/log/trafficserver/diags.log
maxretry = 10
findtime = 60
bantime = 600
EOF

sudo systemctl restart fail2ban
sudo etckeeper init && sudo etckeeper commit "ats-proxy v3"
```

**Verifica hardening**:

```bash
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080
```

**Atteso**: `Passed: 25  Failed: 0  Warnings: 0`

## 9. Testa tutti i modi

```bash
for mode in off deny whitelist auth_all auth_nd; do
  sudo bash scripts/ats-mode-test.sh "$mode" 8080 admin testpass
done
```

Ogni modo deve mostrare `Passed: N  Failed: 0`.

## 10. Crea utente reale

```bash
sudo bash scripts/ats-ctl user remove admin
sudo bash scripts/ats-ctl user add operator
sudo bash scripts/ats-ctl mode auth_nd
sudo bash scripts/ats-ctl reload
```

---

## Riepilogo

| Cosa | Dove |
|---|---|
| ATS 9.2.13 | `/opt/trafficserver/` |
| Config ATS | `/opt/trafficserver/etc/trafficserver/` |
| Plugin `.so` | `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so` |
| Config plugin | `/etc/trafficserver/plugin/` |
| Log | `/var/log/trafficserver/diags.log` |
| Systemd | `systemctl restart trafficserver` |
| Man pages | `man ats-ctl` · `man ats-proxy-filter` |

## Comandi quotidiani

```bash
systemctl status trafficserver
sudo ats-ctl status
sudo ats-ctl deny add dominio
sudo ats-ctl user add nome
sudo ats-ctl mode auth_nd
sudo ats-ctl reload
sudo tail -f /var/log/trafficserver/diags.log
```
