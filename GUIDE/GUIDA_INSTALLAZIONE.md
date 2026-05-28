# ATS Proxy Enterprise v3.0 — Guida di Installazione

## Ubuntu 26.04 LTS · Apache Traffic Server 9.2.13 LTS

**Testata copia-incolla su VM137 il 2026-05-28: ogni comando verificato.**

---

## 0. Preparazione: clona la repo

```bash
cd ~
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
```

📁 La repo (`~/ats-proxy-enterprise`) contiene script e template. **Non** contiene ATS già compilato.
📁 ATS verrà installato in `/opt/trafficserver` (percorso assoluto).
📁 La configurazione ATS va in `/etc/trafficserver/` (creata automaticamente da `make install`).
📁 La configurazione del plugin va in `/etc/trafficserver/plugin/`.

> **Offline?** Scarica il [ZIP](https://github.com/tripersonale/ats-proxy-enterprise/archive/refs/heads/main.zip)
> su un PC con internet, copialo sulla macchina target via chiavetta, e fai
> `unzip main.zip && cd ats-proxy-enterprise-main`. Poi prosegui da qui.

---

## 1. Dipendenze apt

```bash
sudo apt update
sudo apt install -y build-essential gcc g++ make libtool autoconf automake \
  pkg-config libssl-dev zlib1g-dev libcap-dev libhwloc-dev \
  libunwind-dev libcurl4-openssl-dev tcl-dev git wget curl
```

---

## 2. Compila PCRE 8.45 in `/usr/local/pcre`

ATS 9.2.13 richiede PCRE1. Su Ubuntu 26.04 va compilato.

```bash
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.bz2/download \
  -O pcre-8.45.tar.bz2
tar -xjf pcre-8.45.tar.bz2
cd pcre-8.45
./configure --prefix=/usr/local/pcre --enable-utf --enable-unicode-properties
make -j"$(nproc)"
sudo make install
sudo ldconfig
```

**Verifica**: `ls /usr/local/pcre/lib/libpcre.so` deve esistere.

---

## 3. Scarica e compila ATS 9.2.13

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2
tar -xjf trafficserver-9.2.13.tar.bz2
cd trafficserver-9.2.13
autoreconf -fi
./configure --prefix=/opt/trafficserver --with-pcre=/usr/local/pcre
make -j"$(nproc)"
sudo make install
```

**Verifica**: `/opt/trafficserver/bin/traffic_server -V` stampa la versione.

> **Nota**: `make install` crea la config ATS in `/opt/trafficserver/etc/trafficserver/`.
> I comandi `sed` sotto modificano direttamente quel percorso. Il plugin userà
> `/etc/trafficserver/plugin/` per la sua configurazione (creata da `ats-ctl init`).

---

## 4. Configura come forward proxy

```bash
sudo sed -i 's/CONFIG proxy.config.reverse_proxy.enabled INT 1/CONFIG proxy.config.reverse_proxy.enabled INT 0/' \
  /opt/trafficserver/etc/trafficserver/records.config
sudo sed -i 's/CONFIG proxy.config.url_remap.remap_required INT 1/CONFIG proxy.config.url_remap.remap_required INT 0/' \
  /opt/trafficserver/etc/trafficserver/records.config
```

---

## 5. Avvia ATS e verifica L0

```bash
sudo /opt/trafficserver/bin/traffic_server -C verify_config
sudo /opt/trafficserver/bin/trafficserver start
sleep 4

curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
```

**Risultato atteso**: `200`

---

## 6. Compila il plugin v3.0

📁 Torna in `~/ats-proxy-enterprise`.

```bash
cd ~/ats-proxy-enterprise
bash scripts/compile-plugin.sh \
  --ats-src /tmp/trafficserver-9.2.13 \
  --out bin/ats_proxy_filter_v30.so --c
```

**Verifica**: `sha256sum bin/ats_proxy_filter_v30.so` stampa un hash.

---

## 7. Installa e configura il plugin

```bash
# Copia il plugin compilato
sudo cp bin/ats_proxy_filter_v30.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so

# Inizializza la configurazione del plugin in /etc/trafficserver/plugin/
sudo bash scripts/ats-ctl init

# Scegli la modalità (deny: blocca solo domini proibiti, nessuna auth)
sudo bash scripts/ats-ctl mode deny

# Aggiungi un dominio da bloccare
sudo bash scripts/ats-ctl deny add httpbin.org

# Registra il plugin in ATS con il path della configurazione
echo 'ats_proxy_filter_v30.so /etc/trafficserver/plugin/filter.conf' | \
  sudo tee /opt/trafficserver/etc/trafficserver/plugin.config > /dev/null

# Riavvia ATS
sudo /opt/trafficserver/bin/trafficserver restart
sleep 4
```

**Verifica**:

```bash
# httpbin.org deve essere bloccato (403)
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://httpbin.org/ip
# Atteso: 403

# Altri domini passano (200)
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
# Atteso: 200
```

---

## 8. Hardening

### 8a. Hardening core (systemd + permessi)

```bash
sudo bash scripts/apply-ats-hardening-v3.sh
sudo bash scripts/ats-ctl reload
```

ATS ora gira come utente `ats:ats` dentro systemd con sandbox. Verifica:

```bash
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=core \
  bash scripts/ats-hardening-check.sh 8080
```

**Risultato atteso**: `Passed: 19  Failed: 0  Warnings: 5`
(I 5 warning sono UFW/fail2ban/etckeeper — li configuriamo ora.)

### 8b. Hardening network (UFW + fail2ban + etckeeper)

```bash
sudo apt install -y ufw fail2ban etckeeper

# UFW: solo proxy (8080) e SSH (22) dalla rete interna
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp comment ats-proxy
sudo ufw allow from 192.168.89.0/24 to any port 22 proto tcp comment ssh-admin
# ⚠️ Sostituisci 192.168.89.0/24 con la TUA subnet!

# fail2ban: blocca IP dopo 10 tentativi di auth fallita in 60 secondi
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
logpath = /opt/trafficserver/var/log/trafficserver/diags.log
maxretry = 10
findtime = 60
bantime = 600
EOF

sudo systemctl restart fail2ban

# etckeeper: versiona le modifiche di sistema
sudo etckeeper init
sudo etckeeper commit "initial ats-proxy v3"
```

### 8c. Verifica hardening completo

```bash
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080
```

**Risultato atteso**: `Passed: 25  Failed: 0  Warnings: 0`

---

## 9. Testa tutti i modi del plugin

```bash
for mode in off deny whitelist auth_all auth_nd; do
  echo "=== $mode ==="
  sudo bash scripts/ats-mode-test.sh "$mode" 8080 admin testpass
done
```

Ogni modo deve mostrare `Passed: N  Failed: 0`.

---

## 10. Crea un utente reale e attiva il modo consigliato

```bash
# Rimuovi utente di test, creane uno vero
sudo bash scripts/ats-ctl user remove admin
sudo bash scripts/ats-ctl user add operator
# (inserisci la password quando richiesto)

# Modo consigliato: deny blocca, whitelist passa senza auth, il resto chiede auth
sudo bash scripts/ats-ctl mode auth_nd
sudo bash scripts/ats-ctl reload
```

---

## Riepilogo: cosa hai installato

| Cosa | Dove |
|---|---|
| ATS 9.2.13 | `/opt/trafficserver/` |
| Config ATS | `/opt/trafficserver/etc/trafficserver/` |
| Plugin v3.0 `.so` | `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so` |
| Config plugin | `/etc/trafficserver/plugin/` |
| Log ATS | `/opt/trafficserver/var/log/trafficserver/diags.log` |
| Systemd unit | `/etc/systemd/system/trafficserver.service` |

---

## Appendici

### A — Installazione offline

Scarica [main.zip](https://github.com/tripersonale/ats-proxy-enterprise/archive/refs/heads/main.zip) +
`pcre-8.45.tar.bz2` + `trafficserver-9.2.13.tar.bz2` su PC con internet.
Copia su chiavetta. Sulla macchina target: `unzip main.zip`, copia i tarball in `/tmp/`,
poi esegui i passi 1-10. Il passo 1 (apt) richiede Internet o mirror locale.

### B — Verifica rapida post-installazione

```bash
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com          # Atteso: 200
sudo grep "cfg_dir=" /opt/trafficserver/var/log/trafficserver/diags.log | tail -1
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080               # Atteso: 25/0/0
```
