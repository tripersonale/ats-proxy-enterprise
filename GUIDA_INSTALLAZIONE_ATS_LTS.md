# Guida Installazione ATS LTS su Ubuntu 26.04

## Stato

Questa guida e il target v3.0: ATS 10.1.2 LTS su Ubuntu 26.04 LTS. Validazione completata su VM137 il 2026-05-27: build ATS, forward proxy L0, build/load plugin v3, 5 mode test OK, full hardening 25/25 OK. Solo TLS frontend resta da validare.

## Obiettivo L0

Installare ATS come forward proxy puro, senza plugin e senza hardening custom. Solo dopo che L0 funziona si installa il plugin.

## Dipendenze indicative

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build pkg-config \
  libssl-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev \
  libunwind-dev libcurl4-openssl-dev tcl-dev
```

ATS 10.1.2 richiede ancora PCRE1 per la build: `libpcre2-dev` non basta.

```bash
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.bz2/download -O pcre-8.45.tar.bz2
tar -xjf pcre-8.45.tar.bz2
cd pcre-8.45
./configure --prefix=/usr/local/pcre --enable-utf --enable-unicode-properties
make -j"$(nproc)"
sudo make install
sudo ldconfig
```

## Build ATS 10.1.2

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

## Config forward proxy minima

ATS 10 usa `records.yaml`. Per forward proxy L0 su VM137 sono state validate queste modifiche:

```yaml
records:
  reverse_proxy:
    enabled: 0
  url_remap:
    remap_required: 0
```

Checklist L0:

```bash
/opt/trafficserver/bin/traffic_server -C verify_config
sudo systemctl restart trafficserver
curl -x http://127.0.0.1:8080 http://example.com -I
```

## Install plugin v3.0

```bash
bash scripts/compile-plugin.sh --ats-src /tmp/trafficserver-10.1.2 --out bin/ats_proxy_filter_v30.so --cxx
sudo scripts/ats-ctl init
sudo scripts/ats-ctl mode deny
sudo scripts/ats-ctl deny add httpbin.org
sudo scripts/ats-ctl reload
```

## Hardening core v3

```bash
sudo bash scripts/apply-ats-hardening-v3.sh
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=core bash scripts/ats-hardening-check.sh 8080
```

Risultato validato su VM137:

```text
Passed: 19  Failed: 0  Warnings: 5
```

Dopo hardening network completo (UFW + fail2ban ats-proxy + etckeeper):

```text
Passed: 25  Failed: 0  Warnings: 0
```

Comando: `ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full bash scripts/ats-hardening-check.sh 8080`

## Upgrade futuro

Ogni upgrade ATS richiede:

1. Backup `/opt/trafficserver`, `/etc/trafficserver`, `/etc/ats-proxy`.
2. Build nuova ATS in path temporaneo.
3. Compile plugin contro gli header generati della nuova versione.
4. `traffic_server -C verify_config`.
5. Test L0, poi test plugin mode, poi hardening check.
6. Aggiornamento `ARTIFACTS.md`, `TEST_MATRIX.md`, `CHANGELOG.md`.

## Cosa resta speculativo/non validato

 - Comportamento TLS frontend su ATS 10.

Questi punti diventano fatti solo dopo test VM.
