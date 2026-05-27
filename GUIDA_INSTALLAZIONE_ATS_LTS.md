# Guida Installazione ATS LTS su Ubuntu 26.04

## Stato

Questa guida e il target v3.0: ATS 10.1.2 LTS su Ubuntu 26.04 LTS. Al momento e **da validare su VM pulita**; i risultati v0.14.0 validati restano ATS 9.2.13 su Ubuntu 24.04/26.04.

## Obiettivo L0

Installare ATS come forward proxy puro, senza plugin e senza hardening custom. Solo dopo che L0 funziona si installa il plugin.

## Dipendenze indicative

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build pkg-config \
  libssl-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev \
  libunwind-dev libcurl4-openssl-dev tcl-dev
```

## Build ATS 10.1.2

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-10.1.2.tar.bz2
tar -xjf trafficserver-10.1.2.tar.bz2
cd trafficserver-10.1.2
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/trafficserver
cmake --build build -j"$(nproc)"
sudo cmake --install build
```

## Config forward proxy minima

ATS 10 usa configurazione YAML dove disponibile. La procedura definitiva andra verificata su VM per confermare nomi chiave e path effettivi.

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

## Upgrade futuro

Ogni upgrade ATS richiede:

1. Backup `/opt/trafficserver`, `/etc/trafficserver`, `/etc/ats-proxy`.
2. Build nuova ATS in path temporaneo.
3. Compile plugin contro gli header generati della nuova versione.
4. `traffic_server -C verify_config`.
5. Test L0, poi test plugin mode, poi hardening check.
6. Aggiornamento `ARTIFACTS.md`, `TEST_MATRIX.md`, `CHANGELOG.md`.

## Cosa e speculativo

- Mapping definitivo `records.yaml` per ATS 10.1.2 su Ubuntu 26.04.
- Compatibilita runtime plugin v3.0 su ATS 10.
- Comportamento TLS frontend su ATS 10.

Questi punti diventano fatti solo dopo test VM.
