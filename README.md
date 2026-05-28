# ATS Proxy Enterprise

Forward proxy HTTP/HTTPS basato su Apache Traffic Server con plugin di URL filtering e autenticazione.

**Stato**: in ricostruzione — documentazione in fase di riscrittura dopo test reale su Ubuntu 26.04.

## Quick Start

```bash
# 1. Configura le variabili d'ambiente
cp env/ats-proxy.env.example env/ats-proxy.env
vim env/ats-proxy.env

# 2. Esegui l'installer
sudo bash INSTALL.sh
```

## Struttura

```
scripts/install-ats-proxy.sh   Installer principale (compila ATS + PCRE + plugin)
scripts/compile-plugin.sh      Compila il plugin contro il source tree ATS
scripts/ats-ctl                CLI gestione policy (mode, deny, whitelist, auth)
scripts/ats-mode-test.sh       Test runtime dei mode plugin
scripts/ats-regression-test.sh Test di regressione (9 test)
scripts/ats-hardening-check.sh Verifica hardening (25 check)
scripts/cve-check.sh           Monitoraggio CVE
src/ats_proxy_filter_v30.c     Plugin v3.0 — URL filtering + autenticazione
config/                        Template configurazione plugin
debian/                        Packaging .deb
```

## Requisiti

- Ubuntu 24.04 o 26.04
- 4 GB RAM, 10 GB disco
- Accesso internet per download sorgenti ATS

## Licenza

Vedi [LICENSE.md](LICENSE.md).
