# ATS Proxy Enterprise v3.0

Forward proxy HTTP/HTTPS con URL filtering, autenticazione e hardening enterprise.

**Powered by Apache Traffic Server 9.2.13 LTS** · **Ubuntu 26.04 LTS** · **Hardening 25/25** · **5 modalità plugin**

[![License: FEL-1.0](https://img.shields.io/badge/license-FEL--1.0-blue)](LICENSE.md) [![ATS: Apache 2.0](https://img.shields.io/badge/ATS-Apache%202.0-green)](THIRD_PARTY.md)

> **Nota**: ATS Proxy Enterprise NON è un prodotto Apache. Il plugin, gli script e
> la documentazione sono codice originale sotto licenza FEL-1.0. Apache Traffic Server
> è un progetto della Apache Software Foundation, qui referenziato come dipendenza
> compilabile da sorgente. Vedi [THIRD_PARTY.md](THIRD_PARTY.md).

## Installazione

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
# Segui GUIDE/GUIDA_INSTALLAZIONE.md (testata copia-incolla, 30-45 min)
```

Oppure scarica lo [ZIP](https://github.com/tripersonale/ats-proxy-enterprise/archive/refs/heads/main.zip)
per installazione offline via chiavetta.

## Guide

| Guida | Contenuto |
|---|---|
| [Installazione](GUIDE/GUIDA_INSTALLAZIONE.md) | Passo-passo testato, online e offline |
| [Manuale Operativo](GUIDE/MANUALE_OPERATIVO.md) | Uso quotidiano, troubleshooting, backup |
| [Aggiornamento Futuro](GUIDE/GUIDA_AGGIORNAMENTO_FUTURO.md) | Upgrade ATS e plugin, librerie, rollback |
| [Presentazione Prodotto](GUIDE/GUIDA_PRODOTTO.md) | Architettura, confronto, roadmap |
| [Architettura](GUIDE/ARCHITETTURA_ATS_PROXY_V3.md) | Strati L0-L4, decisioni tecniche |
| [Affidabilità Enterprise](GUIDE/DOCUMENTO_PLUGIN_ENTERPRISE.md) | Limiti, sicurezza, roadmap |

## Man pages

```bash
man ats-ctl             # Gestione policy
man ats-proxy-filter    # Architettura plugin
```

## Repository

- **Pubblica** (questa): `ats-proxy-enterprise` — installazione, guide, sorgenti
- **Sviluppo**: `ats-proxy-enterprise-dev` — storico, build, documenti interni

## Licenza

Fair Enterprise License v1.0 (FEL-1.0). Vedi [LICENSE.md](LICENSE.md).
