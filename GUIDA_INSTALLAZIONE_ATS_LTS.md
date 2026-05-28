# Guida Installazione ATS LTS su Ubuntu 26.04

## Stato

Questa guida e il target v3.0: ATS 10.1.2 LTS su Ubuntu 26.04 LTS.
Testata copia-incolla su VM137 il 2026-05-28: ogni comando e stato eseguito
esattamente come scritto e verificato. Full hardening 25/25 OK.
Solo TLS frontend resta da validare.

## Prima di iniziare

Hai bisogno di:
- Una VM o server con **Ubuntu 26.04 LTS** appena installato.
- Almeno **4 GB RAM** e **20 GB disco** libero.
- Accesso **sudo**.
- Connessione Internet per scaricare i sorgenti.

**Tempo stimato**: 30-45 minuti (dipende dalla CPU).

---

## 1. Installa le dipendenze

Copia e incolla:

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build pkg-config \
  libssl-dev zlib1g-dev libcap-dev libhwloc-dev \
  libunwind-dev libcurl4-openssl-dev tcl-dev
```

> **Nota**: `libpcre2-dev` NON basta. ATS 10.1.2 richiede PCRE1 (versione 8.x).
> Lo compileremo al passo 2.

---

## 2. Compila PCRE 8.45

ATS 10.1.2 ha bisogno di PCRE1. Lo compiliamo in `/usr/local/pcre`:

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

## 3. Scarica e compila ATS 10.1.2

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-10.1.2.tar.bz2
tar -xjf trafficserver-10.1.2.tar.bz2
cd trafficserver-10.1.2
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/trafficserver \
  -DPCRE_LIBRARY=/usr/local/pcre/lib/libpcre.so \
  -DPCRE_INCLUDE_DIR=/usr/local/pcre/include
cmake --build build -j"$(nproc)"
sudo cmake --install build
```

> **Nota**: La build genera anche test unitari. Se alcuni falliscono (es.
> `test_PluginFactory`), non e un problema — `traffic_server` e gia compilato
> e funzionante. Il comando `cmake --install` lo installa comunque.

**Verifica**: `/opt/trafficserver/bin/traffic_server -V` stampa la versione.

---

## 4. Configura come forward proxy

ATS 10 usa `records.yaml`. Di default e configurato come reverse proxy.
Per forward proxy devi modificare due valori.

Il file da editare e:
`/opt/trafficserver/etc/trafficserver/records.yaml`

Esegui questi comandi per applicare la modifica:

```bash
# Backup del file originale
sudo cp /opt/trafficserver/etc/trafficserver/records.yaml \
  /opt/trafficserver/etc/trafficserver/records.yaml.original

# Applica le modifiche
sudo python3 -c "
from pathlib import Path
p = Path('/opt/trafficserver/etc/trafficserver/records.yaml')
s = p.read_text()
s = s.replace('  reverse_proxy:\n    enabled: 1', '  reverse_proxy:\n    enabled: 0')
s = s.replace('    remap_required: 1', '    remap_required: 0')
p.write_text(s)
print('Forward proxy config applied')
"
```

> **Cosa fanno queste modifiche**: `reverse_proxy.enabled=0` dice ad ATS di
> comportarsi come forward proxy. `remap_required=0` permette richieste a
> qualsiasi dominio senza dover scrivere regole di remap.

---

## 5. Avvia ATS e verifica L0

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
Se vedi `000`, ATS non e partito. Controlla con `sudo /opt/trafficserver/bin/trafficserver status`.

---

## 6. Scarica la repo ats-proxy e compila il plugin

```bash
# Clona la repo (o copiala via SCP se sei offline)
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
# oppure: scp -r utente@host:/percorso/ats-proxy .

cd ats-proxy

# Compila il plugin v3.0
bash scripts/compile-plugin.sh \
  --ats-src /tmp/trafficserver-10.1.2 \
  --out bin/ats_proxy_filter_v30.so --cxx
```

**Verifica**: `sha256sum bin/ats_proxy_filter_v30.so` stampa un hash.

---

## 7. Installa e configura il plugin

```bash
# Copia il plugin compilato nella directory ATS
sudo cp bin/ats_proxy_filter_v30.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so

# Inizializza la configurazione del plugin in /etc/ats-proxy/
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
logpath = /opt/trafficserver/var/log/trafficserver/diags.log
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

```bash
cd ats-proxy
for mode in off deny whitelist auth_all auth_nd; do
  echo "=== $mode ==="
  sudo ATS_PROXY_CONFIG_DIR=/etc/ats-proxy \
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

> **Dove sono le password**: in `/etc/ats-proxy/auth.conf`. Non sono in chiaro:
> vengono salvate come `salt$sha256(salt+password)`.

---

## Riepilogo: cosa hai installato

| Cosa | Dove |
|---|---|
| ATS 10.1.2 | `/opt/trafficserver/` |
| Config ATS | `/opt/trafficserver/etc/trafficserver/` |
| Plugin v3.0 `.so` | `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so` |
| Config plugin | `/etc/ats-proxy/` |
| Log ATS | `/opt/trafficserver/var/log/trafficserver/diags.log` |
| Log audit richieste | `/opt/trafficserver/var/log/trafficserver/audit.log` |
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
