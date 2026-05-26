# STATE CARD 26.04 - ATS Proxy Enterprise

## Stato

- VM: VM136.
- OS: Ubuntu 26.04 LTS.
- IP test: `192.168.89.36`.
- ATS: 9.2.13.
- PCRE1: 8.45 da sorgente in `/usr/local/pcre`.
- Installer 0.13.0: OK.
- Regression: 9/9 OK.
- Hardening: 25/25 OK.

## Note Specifiche 26.04

- `libpcre3-dev` non disponibile nei repo: usare PCRE1 sorgente.
- `libncurses-dev`, non `libncurses5-dev`.
- Il path plugin operativo resta `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so`.

## Comandi Di Verifica

```bash
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

## Gap

- ATS 10.x non validato.
- TLS frontend opzionale non incluso nella batteria 0.13.0.
