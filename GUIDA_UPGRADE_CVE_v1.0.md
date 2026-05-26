# Apache Traffic Server - Guida Aggiornamento E CVE

Documento corrente, ricreato in root. Mantiene il livello professionale della vecchia guida, ma corregge il messaggio su ATS 10: **ATS 10 non si aggiorna da solo e non rompe automaticamente il plugin**. Semplicemente non e una baseline validata.

## Baseline Di Produzione

| Componente | Versione validata | Stato |
|------------|-------------------|-------|
| ATS | 9.2.13 | supportato |
| Ubuntu | 24.04.4, 26.04 | supportato |
| Plugin | v2.1 | supportato su ATS 9.2.13 |
| Installer | 0.13.0 | testato end-to-end |

ATS e installato da sorgente in `/opt/trafficserver`, quindi `apt upgrade` non aggiorna ATS. Gli aggiornamenti automatici coprono il sistema operativo e le librerie gestite da apt, non il core ATS compilato manualmente.

## Cosa Significa "ATS 10 Non Validato"

Significa:

- non aggiornare manualmente produzione da ATS 9.2.13 ad ATS 10.x senza test;
- ATS 10 usa build system diverso e potrebbe avere differenze API/config;
- il plugin C deve essere ricompilato contro gli header ATS 10.x;
- vanno ripetuti regression, hardening e test DNS cache.

Non significa:

- che la VM si aggiornera da sola ad ATS 10;
- che unattended-upgrades rompera il plugin;
- che la baseline attuale e instabile.

## Librerie Da Monitorare

| Componente | Origine | Aggiornamento | Nota |
|------------|---------|---------------|------|
| ATS 9.2.13 | sorgente Apache | manuale | monitorare announce Apache |
| Plugin C | repo | manuale | ricompilare solo con test |
| PCRE1 24.04 | apt `libpcre3-dev` | apt/security | usato da ATS 9.2.13 |
| PCRE1 26.04 | sorgente 8.45 | manuale | installato in `/usr/local/pcre` |
| OpenSSL | apt | unattended/security | runtime TLS |
| zlib | apt | unattended/security | compressione |
| libcurl | apt | unattended/security | dipendenza ATS |
| libxml2 | apt | unattended/security | dipendenza build/runtime |
| libjson-c | apt | unattended/security | dipendenza build/runtime |
| kernel/OpenSSH/systemd/glibc | apt | unattended/security | OS hardening |

## Fonti CVE

- Apache Traffic Server announce: `https://lists.apache.org/list.html?announce@trafficserver.apache.org`
- Apache Traffic Server downloads: `https://downloads.apache.org/trafficserver/`
- Ubuntu Security Notices: `https://ubuntu.com/security/notices`
- NVD: `https://nvd.nist.gov/`
- OpenSSL vulnerabilities: `https://www.openssl.org/news/vulnerabilities.html`
- curl security: `https://curl.se/docs/security.html`

## Check Locale

```bash
sudo /opt/cve-check.sh || true
openssl version
curl --version | head -1
uname -r
/opt/trafficserver/bin/traffic_server -V 2>&1 | head
```

## Aggiornamento Sicuro Entro Baseline 9.2.13

Quando cambia config/script/plugin ma non major ATS:

```bash
git pull
bash scripts/check-repo-consistency.sh
bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

Esito richiesto:

```text
Passed: 9  Failed: 0
Passed: 25  Failed: 0  Warnings: 0
```

## Aggiornamento Plugin Su ATS 9.2.13

```bash
sudo systemctl stop trafficserver
sudo cp -a /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so.bak.$(date +%Y%m%d-%H%M%S)
sudo install -o ats -g ats -m 755 bin/ats_proxy_filter_v21.so /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo systemctl start trafficserver
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

## Upgrade ATS 10.x

Stato: **non operativo, non produzione, non validato**.

Check rapido eseguito il 2026-05-26 su VM135, senza installare ATS 10:

- download `trafficserver-10.1.2.tar.bz2` verificato con SHA512 ufficiale;
- compile plugin con `gcc` contro header raw ATS 10.1.2 fallisce per richiesta C++17;
- compile con `g++ -std=c++17` arriva oltre, ma fallisce per `ts/apidefs.h` mancante, header generato dal build system;
- conclusione: ATS 10.1.2 non e un drop-in compile check dai sorgenti raw. Serve build CMake completa prima di giudicare compatibilita reale.

Checklist minima prima di cambiare questa frase:

- creare VM lab o snapshot;
- build ATS 10.x;
- ricompilare `src/ats_proxy_filter_v21.c` contro header ATS 10.x;
- verificare caricamento plugin senza `undefined symbol`;
- verificare path plugin corretto su ATS 10.x;
- eseguire regression 9/9;
- eseguire hardening 25/25;
- aggiungere test specifico DNS cache gap;
- aggiornare `TEST_MATRIX.md`, `ARTIFACTS.md`, `CHANGELOG.md`.

Finche non passa questa checklist, ATS 9.2.13 resta la baseline.

## Rollback

Rollback plugin:

```bash
sudo systemctl stop trafficserver
sudo cp /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so.bak.YYYYMMDD-HHMMSS \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo chown ats:ats /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo chmod 755 /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo systemctl start trafficserver
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

Rollback config con etckeeper:

```bash
cd /etc
sudo git log --oneline -10
sudo git diff HEAD~1 -- trafficserver
```

Non usare rollback distruttivi senza salvare prima log e stato servizio.

## DNS Cache Gap Come Debito Tecnico

Non trattarlo come CVE, ma come limite di enforcement policy. Per policy ad alta criticita serve lavoro plugin dedicato per uscire da `TS_HTTP_OS_DNS_HOOK` o mitigare la cache con test reali.
