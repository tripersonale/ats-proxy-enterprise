# Apache Traffic Server — Guida Upgrade e Gestione CVE

## Mantenere il proxy sicuro nel tempo

**Versione 1.1 — 26 Maggio 2026 — Aggiornata con versioni reali verificate su VM 130 e VM 134**

---

## 1. Perche aggiornare

ATS compilato da sorgente **non riceve aggiornamenti automatici** da `apt`. Ogni nuova CVE risolta upstream richiede intervento manuale.

Questa guida copre:
- Procedura upgrade a nuove versioni ATS
- Monitoraggio CVE delle dipendenze
- Aggiornamento librerie singole
- Prevenzione rotture
- Rollback

---

## 2. Inventario Librerie e Dipendenze

### 2.1 Librerie compilate dentro ATS (da monitorare manualmente)

| Libreria | 24.04 Noble (VM 130) | 26.04 Resolute (VM 134) | Ruolo | Fonte CVE |
|----------|----------------------|------------------------|-------|-----------|
| **ATS** | 9.2.13 | 9.2.13 | Core proxy | [Apache announce](https://lists.apache.org/list.html?announce@trafficserver.apache.org) |
| **PCRE1** | 8.39 (apt) | **8.45 (sorgente)** | Regex engine | [NVD](https://nvd.nist.gov/) |
| **OpenSSL** | 3.0.x LTS | **3.5.5** | TLS, crittografia | [openssl.org/news](https://openssl.org/news/) |
| **Zlib** | 1.3.1 | **1.3.1** | Compressione HTTP | [zlib.net](https://zlib.net/) |
| **LZMA** | 5.4.x | **5.8.3** | Compressione alternativa | NVD |
| **Brotli** | 1.1.x | **1.2.0** | Compressione | [github.com/google/brotli](https://github.com/google/brotli) |
| **libcurl** | 8.x | **8.18.0** | HTTP client interno | [curl.se](https://curl.se/) |
| **libjson-c** | 0.17 | **0.18** | Parsing JSON | [github.com/json-c](https://github.com/json-c) |
| **yaml-cpp** | interno ATS | interno ATS | Parsing YAML ACL/log | [github.com/jbeder/yaml-cpp](https://github.com/jbeder/yaml-cpp) |
| **Kernel** | 6.8.x | **7.0.0** | Sistema | [ubuntu.com/security](https://ubuntu.com/security) |
| **GCC** | 13.x | **15.2.0** | Compilatore | - |

> Versioni verificate con `scripts/cve-check.sh` eseguito su VM134 il 26/05/2026.

### 2.2 Librerie di sistema (coperte da unattended-upgrades)

| Libreria | Aggiornata da | Rischio se non aggiornata |
|----------|-------------|--------------------------|
| Kernel | unattended (security) | Privilege escalation, DoS |
| systemd | unattended (security) | Escalation locale |
| OpenSSH | unattended (security) | Accesso non autorizzato |
| glibc | unattended (security) | Code execution |
| GCC runtime | unattended (security) | Basso |

### 2.3 Comandi verifica versioni

```bash
# Su entrambe le VM, eseguire periodicamente:
echo "=== PCRE ===" && pcre-config --version 2>/dev/null || /usr/local/pcre/bin/pcre-config --version
echo "=== OpenSSL ===" && openssl version
echo "=== Zlib ===" && dpkg -l zlib1g | tail -1
echo "=== LZMA ===" && dpkg -l liblzma5 | tail -1
echo "=== Brotli ===" && dpkg -l libbrotli1 | tail -1
echo "=== libcurl ===" && curl --version | head -1
echo "=== libxml2 ===" && dpkg -l libxml2 | tail -1
echo "=== libjson-c ===" && dpkg -l libjson-c5 | tail -1 || dpkg -l libjson-c-dev | tail -1
echo "=== Kernel ===" && uname -r
echo "=== GCC ===" && gcc --version | head -1
```

---

## 3. Fonti CVE e Canali di Notifica

### 3.1 Da monitorare

| Fonte | URL | Cosa notifica |
|-------|-----|---------------|
| **Apache Traffic Server announce** | [lists.apache.org](https://lists.apache.org/list.html?announce@trafficserver.apache.org) | Nuove release, CVE fix |
| **Apache Traffic Server download** | [downloads.apache.org/trafficserver](https://downloads.apache.org/trafficserver/) | Nuove versioni |
| **NVD (National Vulnerability Database)** | [nvd.nist.gov](https://nvd.nist.gov/) | CVE per tutte le librerie |
| **Ubuntu Security Notices** | [ubuntu.com/security/notices](https://ubuntu.com/security/notices) | CVE pacchetti di sistema |
| **OpenSSL Vulnerabilities** | [openssl.org/news/vulnerabilities](https://www.openssl.org/news/vulnerabilities.html) | CVE OpenSSL |
| **curl Security** | [curl.se/docs/security](https://curl.se/docs/security.html) | CVE libcurl |
| **OSS-Security mailing list** | [oss-security](https://oss-security.openwall.org/wiki/mailing-lists/oss-security) | Pre-disclosure CVE |

### 3.2 Automatizzare il monitoraggio

Lo script `scripts/cve-check.sh` (testato su VM134) esegue la verifica automatica di tutte le librerie. Produce un report in `/var/log/ats-cve.log`.

```bash
# Esecuzione manuale
sudo bash scripts/cve-check.sh

# Attivare via cron settimanale (ogni lunedì alle 8:00)
(sudo crontab -l 2>/dev/null; echo '0 8 * * 1 /opt/cve-check.sh') | sudo crontab -

# Verificare l'ultimo report
sudo tail -30 /var/log/ats-cve.log

# Esempio output (VM134, 26/05/2026):
# ATS version: 9.2.13
# openssl: 3.5.5-1ubuntu3
# PCRE1 (source): 8.45
# zlib1g: 1:1.3.dfsg+really1.3.1-1ubuntu3
# liblzma5: 5.8.3-1
# libbrotli1: 1.2.0-3build1
# libcurl4t64: 8.18.0-1ubuntu2.1
# libjson-c5: 0.18+ds-3
# Kernel: 7.0.0-15-generic
# All checks passed ✅
```

---

## 4. Matrice Compatibilita

### 4.1 Versioni testate

| ATS | Ubuntu | PCRE1 | OpenSSL | GCC | Build System | Stato |
|-----|--------|-------|---------|-----|-------------|-------|
| 9.2.13 | 24.04 Noble | 8.39 (apt) | 3.0.x | 13.x | autotools | ✅ Testato VM 130 |
| 9.2.13 | 26.04 Resolute | 8.45 (sorgente) | 3.5.5 | 15.2.0 | autotools | ✅ Testato VM 134 |
| 10.1.2 | 26.04 | 8.45 | 3.5.5 | 15.2.0 | **CMake** | ⚠️ API check OK, build da completare |

### 4.2 Differenze ATS 9.x → 10.x (verificato 25/05/2026)

| Aspetto | 9.x | 10.x | Impatto sul plugin |
|---------|-----|------|-------------------|
| Build system | autotools (configure/make) | **CMake** | Nuova procedura, flag diversi |
| TSUserArgSet/Get | ✅ | ✅ | **Compatibile** |
| TSUserArgIndexReserve | ✅ | ✅ | **Compatibile** |
| TSMimeHdrFieldValueStringGet | ✅ | ✅ | **Compatibile** |
| TSHttpTxnClientReqGet | ✅ | ✅ | **Compatibile** |
| TS_EVENT_HTTP_OS_DNS | 60003 | da verificare | Probabilmente invariato |
| TS_HTTP_SEND_RESPONSE_HDR_HOOK | ✅ | ✅ | **Compatibile** |
| Records format | records.config (key-value) | da verificare | Potrebbe essere YAML in 10.x |
| Plugin API | Stabile | Stabile | **Plugin v2.1 dovrebbe funzionare** (da ricompilare contro headers 10.x) |

### 4.3 Procedura upgrade a ATS 10.x (preliminare, da testare)

```bash
# 1. Backup
sudo systemctl stop trafficserver
sudo cp -a /opt/trafficserver /opt/trafficserver.bak-9.2.13
sudo cp -a /etc/trafficserver /etc/trafficserver.bak-9.2.13

# 2. Download e build (CMake)
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-10.1.2.tar.bz2
tar -xjf trafficserver-10.1.2.tar.bz2 && cd trafficserver-10.1.2
mkdir build && cd build
cmake .. -DCMAKE_INSTALL_PREFIX=/opt/trafficserver \
  -DCMAKE_BUILD_TYPE=Release \
  -DPCRE_LIBRARY=/usr/local/pcre/lib/libpcre.so \
  -DPCRE_INCLUDE_DIR=/usr/local/pcre/include
make -j$(nproc)
sudo make install

# 3. Ricompilare plugin v2.1 contro nuove headers
cd /tmp/trafficserver-10.1.2
gcc -fPIC -shared -I. -I./include -o /tmp/ats_proxy_filter_v21.so \
  ats_proxy_filter_v21.c

# 4. Riavviare e testare
sudo cp /tmp/ats_proxy_filter_v21.so /opt/trafficserver/lib/modules/ats_proxy_filter.so
sudo ldconfig
sudo systemctl start trafficserver
```

⚠️ **ATTENZIONE**: La procedura di upgrade a 10.x NON è stata testata su VM reale.
- API verificate compatibili
- Build system cambiato (CMake)
- Config format potrebbe essere cambiato (records.config → YAML?)
- Plugin richiede ricompilazione

**Raccomandazione**: Attendere un test completo prima di eseguire in produzione.

---

## 5. Procedura Upgrade ATS

### 5.1 Pre-upgrade

```bash
# 1. Backup completo
sudo tar czf /root/ats-pre-upgrade-$(date +%Y%m%d).tar.gz \
  /etc/trafficserver/ /opt/trafficserver/bin/

# 2. Salvare metriche correnti
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests > /tmp/metrics-pre-upgrade.txt

# 3. Verificare che tutto funzioni prima dell'upgrade
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip
# Deve restituire 200

# 4. Salvare checksum dei binari attuali
sha256sum /opt/trafficserver/bin/traffic_server /opt/trafficserver/bin/traffic_manager > /tmp/ats-binary-checksums.txt
```

### 5.2 Download e compilazione nuova versione

```bash
VERSIONE="9.2.NEW"  # Sostituire con versione reale

cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-${VERSIONE}.tar.bz2
wget https://downloads.apache.org/trafficserver/trafficserver-${VERSIONE}.tar.bz2.sha256
sha256sum -c trafficserver-${VERSIONE}.tar.bz2.sha256

tar -xjf trafficserver-${VERSIONE}.tar.bz2
cd trafficserver-${VERSIONE}

autoreconf -if

# 24.04:
./configure \
  --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --enable-pcre \
  --disable-tests --disable-examples --disable-maintainer-mode

# 26.04:
export PKG_CONFIG_PATH='/usr/local/pcre/lib/pkgconfig'
./configure \
  --prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver \
  --localstatedir=/var/lib/trafficserver --runstatedir=/run/trafficserver \
  --with-user=ats --with-group=ats --with-pcre=/usr/local/pcre \
  --disable-tests --disable-examples --disable-maintainer-mode

make -j$(nproc)
```

### 5.3 Installazione

```bash
# Fermare il servizio
sudo systemctl stop trafficserver

# Installare
sudo make install

# Ricaricare librerie
sudo ldconfig

# Verificare permessi
sudo chown -R ats:ats /opt/trafficserver

# Riavviare
sudo systemctl start trafficserver
```

### 5.4 Post-upgrade — Verifica

```bash
# 1. Versione
/opt/trafficserver/bin/traffic_server -V 2>&1 | head -1

# 2. Stato servizio
sudo systemctl status trafficserver --no-pager

# 3. Test proxy
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip && echo ' HTTP OK'
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 https://httpbin.org/ip && echo ' HTTPS OK'

# 4. Test concorrenza
for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' -x http://localhost:8080 http://httpbin.org/ip & done; wait; echo ''

# 5. Verifica log
sudo tail -3 /var/lib/trafficserver/log/trafficserver/audit.log

# 6. Verifica ACL
# Ripetere batteria test ACL (Guida Installazione Sezione 14)

# 7. Confrontare metriche con pre-upgrade
sudo /opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.incoming_requests

# 8. Verificare eventuali warning nei log
sudo grep -i "warn\|error\|fail" /var/lib/trafficserver/log/trafficserver/diags.log | tail -20
```

---

## 6. Cosa si Puo Rompere e Come Prevenirlo

### 6.1 Cambi formato configurazione

| Sintomo | Causa | Prevenzione |
|---------|-------|------------|
| Servizio non parte | Nuova direttiva obbligatoria in `records.config` | Leggere CHANGELOG prima dell'upgrade |
| ACL non caricate | Cambio formato YAML | Backuppare e confrontare con template nuova versione |
| Log vuoti | Cambio formato `logging.yaml` | Verificare variabili di log ancora valide |

**Procedura preventiva**:
```bash
# Confrontare i config di default della nuova versione con quelli attuali
diff /etc/trafficserver/records.config /tmp/trafficserver-NEW/configs/records.config.default
diff /etc/trafficserver/ip_allow.yaml /tmp/trafficserver-NEW/configs/ip_allow.yaml.default
```

### 6.2 Dipendenze

| Rischio | Sintomo | Prevenzione |
|---------|---------|------------|
| PCRE1 rimosso da OS futuro | `configure: error: Cannot find pcre` | Avere PCRE1 da sorgente pronto |
| OpenSSL API deprecata | `error: implicit declaration` | Verificare changelog OpenSSL |
| GCC troppo nuovo | `error: -Werror=...` | Aggiungere `--disable-werror` al configure se disponibile |
| GCC troppo vecchio | `error: C++17 required` | Verificare requisiti minimi GCC nella doc ATS |

### 6.3 Binary compatibility

```bash
# Verificare che ldconfig trovi le .so giuste
sudo ldconfig -p | grep trafficserver

# Verificare dipendenze binarie
ldd /opt/trafficserver/bin/traffic_server | grep "not found"
# Nessun output = OK
```

### 6.4 Lock file e cache

```bash
# Se il servizio non parte dopo upgrade:
sudo rm -f /var/lib/trafficserver/trafficserver/manager.lock
sudo rm -f /var/lib/trafficserver/trafficserver/server.lock
sudo rm -f /run/trafficserver/*.sock
# Poi riavviare
```

---

## 7. Aggiornamento Dipendenze Singole

### 7.1 OpenSSL (aggiornato da apt su entrambi)

```bash
# Verificare versione corrente
openssl version

# Aggiornare (coperto da unattended-upgrades)
sudo apt install --only-upgrade openssl libssl-dev libssl3

# Verificare che ATS funzioni ancora
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 https://httpbin.org/ip
# Deve restituire 200

# Se 000 dopo upgrade OpenSSL:
# Ricompilare ATS (link contro nuove .so)
cd /tmp/trafficserver-9.2.13
make clean && make -j$(nproc) && sudo make install && sudo ldconfig
sudo systemctl restart trafficserver
```

### 7.2 PCRE1 (da sorgente, solo 26.04)

```bash
# Verificare se ci sono nuove CVE su PCRE 8.45
# URL: https://nvd.nist.gov/vuln/search/results?query=pcre

# Se serve aggiornare PCRE1:
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/NUOVA_VERSIONE/pcre-NUOVA_VERSIONE.tar.gz
tar xzf pcre-NUOVA_VERSIONE.tar.gz
cd pcre-NUOVA_VERSIONE
./configure --prefix=/usr/local/pcre --enable-utf8 --enable-unicode-properties
make -j$(nproc)
sudo make install

# Poi ricompilare ATS
cd /tmp/trafficserver-9.2.13
make clean
export PKG_CONFIG_PATH='/usr/local/pcre/lib/pkgconfig'
./configure ... (stesse opzioni)
make -j$(nproc) && sudo make install && sudo ldconfig
sudo systemctl restart trafficserver
```

### 7.3 Zlib, Brotli, LZMA (da apt, nessuna ricompilazione)

```bash
# Queste sono linkate dinamicamente. Basta apt upgrade.
sudo apt install --only-upgrade zlib1g libbrotli1 liblzma5

# Verificare:
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip
# Deve restituire 200
```

---

## 8. Rollback Procedure

```bash
# 1. Fermare il servizio
sudo systemctl stop trafficserver

# 2. Ripristinare binari dal backup pre-upgrade
sudo tar xzf /root/ats-pre-upgrade-YYYYMMDD.tar.gz -C /

# 3. Ripristinare permessi
sudo chown -R ats:ats /opt/trafficserver /etc/trafficserver

# 4. Ricaricare ldconfig
sudo ldconfig

# 5. Riavviare
sudo systemctl start trafficserver

# 6. Verificare
curl -s -o /dev/null -w '%{http_code}' -x http://localhost:8080 http://httpbin.org/ip

# 7. Bloccare versioni finche non si risolve il problema
# (non applicabile a compilato, ma non aggiornare ulteriormente)
```

---

## 9. Script Test Regressione Post-Upgrade

```bash
#!/bin/bash
# Script: ats-regression-test.sh
# Da eseguire dopo ogni upgrade o modifica configurazione

PASS=0
FAIL=0

echo "=== ATS Regression Test ==="
echo "Target: ${1:-localhost:8080}"
TARGET="${1:-localhost:8080}"

# Test 1: HTTP
echo -n "Test 1: HTTP proxy... "
CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x http://$TARGET http://httpbin.org/ip)
if [ "$CODE" = "200" ]; then echo "✅ $CODE"; ((PASS++)); else echo "❌ $CODE"; ((FAIL++)); fi

# Test 2: HTTPS CONNECT
echo -n "Test 2: HTTPS CONNECT... "
CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x http://$TARGET https://httpbin.org/ip)
if [ "$CODE" = "200" ]; then echo "✅ $CODE"; ((PASS++)); else echo "❌ $CODE"; ((FAIL++)); fi

# Test 3: Concorrenza (10 req)
echo -n "Test 3: 10 concurrent... "
RESULTS=$(for i in $(seq 1 10); do curl -s -o /dev/null -w '%{http_code} ' --connect-timeout 5 -x http://$TARGET http://httpbin.org/ip & done; wait)
FAIL_COUNT=$(echo "$RESULTS" | tr ' ' '\n' | grep -vc '200')
if [ "$FAIL_COUNT" = "0" ]; then echo "✅ All 200"; ((PASS++)); else echo "❌ $FAIL_COUNT failures"; ((FAIL++)); fi

# Test 4: Log contiene FQDN
echo -n "Test 4: Log FQDN... "
LOG=$(sudo tail -3 /var/lib/trafficserver/log/trafficserver/audit.log 2>/dev/null)
if echo "$LOG" | grep -q "httpbin.org"; then echo "✅ FQDN presente"; ((PASS++)); else echo "❌ FQDN assente"; ((FAIL++)); fi

# Test 5: Porta in ascolto
echo -n "Test 5: Port 8080 listening... "
if ss -tlnp | grep -q ":8080"; then echo "✅"; ((PASS++)); else echo "❌"; ((FAIL++)); fi

# Test 6: Servizio attivo
echo -n "Test 6: Service active... "
if systemctl is-active trafficserver > /dev/null 2>&1; then echo "✅"; ((PASS++)); else echo "❌"; ((FAIL++)); fi

echo ""
echo "=== Risultati: $PASS passati, $FAIL falliti ==="
```

---

## 10. Prioritizzazione CVE — Matrice Decisionale

| CVE Severity (CVSS) | Libreria | Azione | Tempistica |
|---------------------|----------|--------|-----------|
| ≥ 9.0 | ATS stesso | Upgrade immediato | Entro 24h |
| ≥ 9.0 | OpenSSL | Ricompilare ATS | Entro 48h |
| ≥ 9.0 | PCRE1 | Ricompilare PCRE1 + ATS | Entro 72h |
| 7.0-8.9 | Qualsiasi | Pianificare upgrade | Entro 1 settimana |
| 4.0-6.9 | ATS / OpenSSL | Alla prossima release LTS | Entro 1 mese |
| 4.0-6.9 | Zlib/Brotli/LZMA | apt upgrade (attended) | Automatico |
| < 4.0 | Qualsiasi | Valutare | Prossimo ciclo |

---

## 11. Checklist Verifica Periodica (mensile)

```bash
#!/bin/bash
# Script: ats-monthly-check.sh

echo "=== Monthly ATS Health Check $(date) ==="
echo ""

# 0. Stato servizio
systemctl is-active trafficserver || echo "⚠️  ATS non attivo!"

# 1. Versioni
echo "ATS: $(/opt/trafficserver/bin/traffic_server -V 2>&1 | head -1)"
echo "OpenSSL: $(openssl version)"
echo "Kernel: $(uname -r)"

# 2. Aggiornamenti disponibili
echo "Aggiornamenti security:"
apt list --upgradable 2>/dev/null | grep -i security || echo "  Nessuno"

# 3. Log errori recenti
echo "Errori ultimi 7 giorni:"
sudo journalctl -u trafficserver --since "7 days ago" -p err --no-pager | tail -5

# 4. Spazio disco
echo "Spazio disco:"
df -h / /var/lib/trafficserver/cache

# 5. Fail2ban
echo "fail2ban SSH:"
sudo fail2ban-client status sshd 2>/dev/null | grep -E "Banned|Total"

# 6. Verifica baseline
curl -s -o /dev/null -w "Proxy test: %{http_code}\n" -x http://localhost:8080 http://httpbin.org/ip
```

---

*Guida basata su ATS 9.2.13 testato su VM 130 (24.04) e VM 134 (26.04)*
*Script CVE: `scripts/cve-check.sh` — eseguibile, testato su VM134*
*Riferimento: GUIDA_INSTALLAZIONE_ATS_v3.0_UNIFICATA.md*
