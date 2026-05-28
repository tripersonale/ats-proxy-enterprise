# ATS Proxy Enterprise v3.0 — Guida di Installazione

## Ubuntu 26.04 LTS · Apache Traffic Server 9.2.13 LTS

**Testata copia-incolla su VM137 il 2026-05-28: ogni comando verificato.**

---

## Prima di iniziare

- VM o server con **Ubuntu 26.04 LTS** appena installato.
- Almeno **4 GB RAM**, **20 GB disco** libero.
- Accesso **sudo**.
- Connessione Internet (o scenario offline — vedi Appendice A).

**Tempo stimato**: 30-45 minuti.

---

## 0. Preparazione: clona la repo

Tutto il lavoro parte da qui. La repo contiene gli script `compile-plugin.sh`,
`ats-ctl`, e i template di configurazione. **Non** contiene ATS già compilato:
ATS e PCRE1 li compileremo da sorgente nei passi successivi.

```bash
# Clona la repo nella tua home (o dove preferisci)
cd ~
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise

# 📁 D'ora in poi, tutti i comandi `scripts/...` e `config/...` partono da qui.
# 📁 ATS verrà installato in /opt/trafficserver (percorso assoluto, non dentro la repo).
# 📁 La configurazione ATS andrà in /etc/trafficserver.
# 📁 La configurazione del plugin andrà in /opt/trafficserver/etc/trafficserver/plugin.
```

> **Offline?** Scarica il [ZIP](https://github.com/tripersonale/ats-proxy-enterprise/archive/refs/heads/main.zip)
> su un PC con internet, copialo sulla macchina target via chiavetta, e fai
> `unzip main.zip && cd ats-proxy-enterprise-main`. Poi prosegui da qui.
> (Vedi anche Appendice A in fondo alla guida.)

---

## 1. Dipendenze apt

📁 *Directory corrente: non importa, apt installa a livello sistema.*

```bash
sudo apt update
sudo apt install -y build-essential gcc g++ make libtool autoconf automake \
  pkg-config libssl-dev zlib1g-dev libcap-dev libhwloc-dev \
  libunwind-dev libcurl4-openssl-dev tcl-dev git wget curl
```

> **Nota**: `libpcre3-dev` NON esiste su Ubuntu 26.04. ATS 9.2.13 richiede
> PCRE1, che compileremo da sorgente al passo 2.

## 2. Compila PCRE 8.45

📁 *Lavoriamo in `/tmp`. I file .tar.bz2 e la compilazione stanno qui.
Il risultato installato andrà in `/usr/local/pcre`.*

ATS 9.2.13 richiede PCRE1. Su Ubuntu 26.04 va compilato in `/usr/local/pcre`:

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

## 3. Scarica e compila ATS 9.2.13

📁 *Sempre in `/tmp`. Il tarball, la compilazione e i file oggetto stanno qui.
ATS installato andrà in `/opt/trafficserver`, la config in `/etc/trafficserver`.*

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

---

## 4. Configura come forward proxy

📁 *Il file da editare è `/opt/trafficserver/etc/trafficserver/records.config` (percorso assoluto,
non dentro la repo).*

```bash
# Backup del file originale
sudo cp /opt/trafficserver/etc/trafficserver/records.config \
  /opt/trafficserver/etc/trafficserver/records.config.original

# Disabilita reverse proxy e rendi forward proxy aperto
sudo sed -i 's/CONFIG proxy.config.reverse_proxy.enabled INT 1/CONFIG proxy.config.reverse_proxy.enabled INT 0/' \
  /opt/trafficserver/etc/trafficserver/records.config
sudo sed -i 's/CONFIG proxy.config.url_remap.remap_required INT 1/CONFIG proxy.config.url_remap.remap_required INT 0/' \
  /opt/trafficserver/etc/trafficserver/records.config
```

## 5. Avvia ATS e verifica L0

📁 *Non serve essere in una directory specifica. I binari ATS sono in
`/opt/trafficserver/bin/` (percorso assoluto).*

```bash
# Verifica che la configurazione sia valida
sudo /opt/trafficserver/bin/traffic_server -C verify_config

# Avvia ATS (NON usare systemctl: il servizio non esiste ancora)
sudo /opt/trafficserver/bin/trafficserver start
sleep 4

# Test: il proxy deve rispondere 200
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
```

**Risultato atteso**: `200`

Se vedi `404`, la config forward proxy non e stata applicata. Torna al passo 4.

---

## 6. Compila il plugin v3.0

📁 *Torna nella directory della repo (`~/ats-proxy-enterprise`). Gli script
`compile-plugin.sh` e `ats-ctl` sono qui. Il `.so` compilato andrà in
`bin/ats_proxy_filter_v30.so` dentro la repo, poi lo copieremo nella
directory ATS.*

```bash
# Compila il plugin v3.0
bash scripts/compile-plugin.sh \
  --ats-src /tmp/trafficserver-9.2.13 \
  --out bin/ats_proxy_filter_v30.so --c
```

**Verifica**: `sha256sum bin/ats_proxy_filter_v30.so` stampa un hash.

---

## 7. Installa e configura il plugin

📁 *Siamo in `~/ats-proxy-enterprise`. I comandi `scripts/ats-ctl` sono relativi
a questa directory. Il plugin .so viene copiato in `/opt/trafficserver/libexec/`,
la config in `/opt/trafficserver/etc/trafficserver/plugin/`.*

```bash
# Copia il plugin compilato nella directory ATS
sudo cp bin/ats_proxy_filter_v30.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so

# Inizializza la configurazione del plugin in /opt/trafficserver/etc/trafficserver/plugin/
sudo scripts/ats-ctl init

# Scegli una modalita. Qui usiamo deny (blocca solo domini proibiti)
sudo scripts/ats-ctl mode deny

# Aggiungi un dominio alla lista nera
sudo scripts/ats-ctl deny add httpbin.org

# Registra il plugin in ATS
echo ats_proxy_filter_v30.so | sudo tee \
  /opt/trafficserver/etc/trafficserver/plugin.config > /dev/null

# Riavvia ATS per caricare il plugin
sudo /opt/trafficserver/bin/trafficserver restart
sleep 4
```

**Verifica plugin**:

```bash
# Il plugin deve apparire nei log
sudo grep "ats_proxy_filter_v30.*plugin loaded" \
  /opt/trafficserver/var/log/trafficserver/diags.log | tail -1

# httpbin.org deve essere bloccato
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://httpbin.org/ip
# Atteso: 403
```

---

## 8. Applica hardening

📁 *Siamo in `~/ats-proxy-enterprise`. Gli script `apply-ats-hardening-v3.sh`
e `ats-hardening-check.sh` sono in `scripts/`. Il resto (UFW, fail2ban, systemd)
agisce a livello sistema.*

L'hardening e diviso in due stage: **core** (systemd, permessi, health check) e
**network** (UFW, fail2ban, etckeeper).

### 8a. Hardening core

```bash
sudo bash scripts/apply-ats-hardening-v3.sh
sudo scripts/ats-ctl reload
```

Dopo questo comando, ATS gira come utente `ats:ats` dentro systemd con sandbox
attivo. Verifica:

```bash
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=core \
  bash scripts/ats-hardening-check.sh 8080
```

**Risultato atteso**:
```
Passed: 19  Failed: 0  Warnings: 5
```

I 5 warning sono attesi: UFW, fail2ban ed etckeeper non sono ancora configurati.
Passiamo allo stage network.

### 8b. Hardening network

```bash
# Installa i pacchetti
sudo apt-get install -y ufw fail2ban etckeeper

# Configura UFW: solo proxy (8080) e SSH (22) dalla rete interna
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.89.0/24 to any port 8080 proto tcp \
  comment ats-proxy
sudo ufw allow from 192.168.89.0/24 to any port 22 proto tcp \
  comment ssh-admin
# ⚠️ Sostituisci 192.168.89.0/24 con la TUA subnet!

# Configura fail2ban per bloccare tentativi di auth falliti sul proxy
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
  logpath = /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log
maxretry = 10
findtime = 60
bantime = 600
EOF

sudo systemctl restart fail2ban

# Inizializza etckeeper per versionare le modifiche di sistema
sudo etckeeper init
sudo etckeeper commit "initial ats-proxy v3"
```

### 8c. Verifica hardening completo

```bash
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080
```

**Risultato atteso**:
```
Passed: 25  Failed: 0  Warnings: 0
```

---

## 9. Testa tutti i modi del plugin

📁 *Siamo in `~/ats-proxy-enterprise`. Lo script `ats-mode-test.sh` e in `scripts/`,
i template di config in `config/`.*

```bash
for mode in off deny whitelist auth_all auth_nd; do
  echo "=== $mode ==="
  sudo ATS_PROXY_CONFIG_DIR=/opt/trafficserver/etc/trafficserver/plugin \
    ATS_PROXY_TEMPLATE_DIR=$(pwd)/config \
    bash scripts/ats-mode-test.sh "$mode" 8080 admin testpass
done
```

Ogni modo deve mostrare `Passed: N  Failed: 0`.

---

## 10. Crea un utente reale

```bash
# Rimuovi l'utente di test
sudo scripts/ats-ctl user remove admin

# Crea un utente con password vera (te la chiede, non salvarla in chiaro)
sudo scripts/ats-ctl user add operator

# Attiva la modalita consigliata: deny blocca, whitelist passa, il resto chiede auth
sudo scripts/ats-ctl mode auth_nd
sudo scripts/ats-ctl reload
```

> **Dove sono le password**: in `/opt/trafficserver/etc/trafficserver/plugin/auth.conf`. Non sono in chiaro:
> vengono salvate come `salt$sha256(salt+password)`.

---

## Riepilogo: cosa hai installato

| Cosa | Dove |
|---|---|
| ATS 9.2.13 | `/opt/trafficserver/` |
| Config ATS | `/opt/trafficserver/etc/trafficserver/` |
| Plugin v3.0 `.so` | `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so` |
| Config plugin | `/opt/trafficserver/etc/trafficserver/plugin/` |
| Log ATS | `/opt/trafficserver/var/trafficserver/log/trafficserver/diags.log` |
| Log audit richieste | `/opt/trafficserver/var/trafficserver/log/trafficserver/audit.log` |
| Health check | `/opt/ats_health.sh` (eseguito ogni minuto via cron) |
| CVE check | `/opt/cve-check.sh` |
| Systemd unit | `/etc/systemd/system/trafficserver.service` |

## Comandi quotidiani

```bash
# Stato proxy
systemctl status trafficserver

# Riavvia
sudo systemctl restart trafficserver

# Leggi i log
sudo tail -f /opt/trafficserver/var/log/trafficserver/diags.log

# Gestisci la policy
sudo ats-ctl status
sudo ats-ctl deny add dominio.com
sudo ats-ctl user add nomeutente
sudo ats-ctl reload

# Verifica hardening
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash ats-proxy/scripts/ats-hardening-check.sh 8080
```

## Upgrade futuro

Ogni volta che esce una nuova ATS o una nuova versione del plugin:

1. **Backup**: `sudo cp -a /opt/trafficserver /opt/trafficserver.bak-$(date +%Y%m%d)`
2. **Compila** la nuova ATS in `/tmp` (stessi comandi del passo 3, con URL aggiornato).
3. **Installa** la nuova ATS e **compila il plugin** contro gli header nuovi (passo 6).
4. **Verifica** L0 (`curl`), poi hardening check, poi test mode.
5. **Aggiorna** i file `ARTIFACTS.md`, `TEST_MATRIX.md`, `CHANGELOG.md` nella repo.

## Cosa non e ancora validato

- TLS frontend su porta 8443 (il plugin lo supporta ma non e incluso nella batteria test).
- Carico oltre 50 richieste concorrenti.
- Penetration test indipendente.

---

## Appendice A — Installazione offline (senza Internet sulla macchina target)

Se la macchina target non ha accesso a Internet, scarica tutto su un PC
connesso e trasferisci via chiavetta USB o share di rete.

### Sul PC con Internet

```bash
# Scarica la repo pubblica come ZIP
wget https://github.com/tripersonale/ats-proxy-enterprise/archive/refs/heads/main.zip

# Scarica i tarball necessari per la compilazione
wget -P /tmp/ats-offline \
  https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.bz2/download \
  -O /tmp/ats-offline/pcre-8.45.tar.bz2

wget -P /tmp/ats-offline \
  https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2

# Copia main.zip e la cartella /tmp/ats-offline/ sulla chiavetta
```

### Sulla macchina target

```bash
# Copia i file dalla chiavetta
cp /media/usb/main.zip ~/
cp /media/usb/ats-offline/* /tmp/

# Estrai la repo
unzip ~/main.zip -d ~/
cd ~/ats-proxy-enterprise-main

# Ora esegui i passi 1-10 della guida principale.
# Al passo 2 (PCRE1): il tarball è già in /tmp/pcre-8.45.tar.bz2
#   cd /tmp && tar -xjf pcre-8.45.tar.bz2 && cd pcre-8.45 && ...
# Al passo 3 (ATS): il tarball è già in /tmp/trafficserver-9.2.13.tar.bz2
#   cd /tmp && tar -xjf trafficserver-9.2.13.tar.bz2 && cd trafficserver-9.2.13 && ...
# Il passo 1 (apt) richiede Internet o un mirror locale.
# Se apt non funziona, assicurati che i pacchetti delle dipendenze siano preinstallati.
# In alternativa, usa il DVD/ISO di Ubuntu come repository locale:
#   sudo mount /dev/cdrom /mnt
#   sudo apt-cdrom -d /mnt add
#   sudo apt update
```

---

## Appendice B — Installazione in 1 comando (solo online)

Se la macchina ha Internet e vuoi il percorso più veloce:

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git /tmp/ats-proxy
cd /tmp/ats-proxy
# Poi esegui i passi 1-10 della guida da qui
```

---

## Appendice C — Verifica Rapida Post-Installazione

```bash
# 1. Proxy risponde?
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
# Atteso: 200

# 2. Plugin caricato?
sudo grep "ats_proxy_filter_v30.*plugin loaded" \
  /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -1
# Atteso: riga con "plugin loaded"

# 3. Hardening OK?
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080
# Atteso: Passed: 25  Failed: 0  Warnings: 0
```

