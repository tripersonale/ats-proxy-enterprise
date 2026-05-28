# ATS Proxy Enterprise v3.0

Forward proxy HTTP/HTTPS con URL filtering, autenticazione e hardening enterprise.

**ATS 9.2.13 LTS** · **Ubuntu 26.04 LTS** · **Hardening 25/25** · **5 modalità plugin**

[![License: FEL-1.0](https://img.shields.io/badge/license-FEL--1.0-blue)](LICENSE.md)

## Installa in 1 comando

```bash
curl -sSL https://raw.githubusercontent.com/tripersonale/ats-proxy-enterprise/main/INSTALL.sh | sudo bash
```

Oppure, senza internet:

```bash
# Scarica la repo su un PC con internet, copiala su chiavetta, poi:
sudo bash INSTALL.sh
```

## Cosa include

| Pacchetto | Contenuto |
|---|---|
| `ats-core` | ATS 9.2.13 LTS compilato per Ubuntu 26.04, forward proxy pronto |
| `ats-proxy-plugin` | Plugin v3.0 con 5 modi (off, deny, whitelist, auth_all, auth_nd), password hashate |
| `ats-proxy-hardening` | systemd sandbox, UFW, fail2ban, etckeeper, health check, CVE helper |
| `ats-proxy-enterprise` | Meta-pacchetto: installa tutto con un comando |

## Modalità del plugin

| Modo | Comportamento |
|---|---|
| `off` | Plugin trasparente |
| `deny` | Blocca domini in lista nera |
| `whitelist` | Solo domini in lista bianca |
| `auth_all` | Auth obbligatoria per tutto |
| `auth_nd` | Deny > Whitelist > Auth (consigliato) |

## Guide

- [Installazione](GUIDE/GUIDA_INSTALLAZIONE.md) — passo-passo, online e offline
- [Uso quotidiano](GUIDE/GUIDA_USO_QUOTIDIANO.md) — checklist, troubleshooting, backup
- [Presentazione prodotto](GUIDE/GUIDA_PRODOTTO.md) — architettura, confronto, roadmap
- [Plugin e auth](GUIDE/GUIDA_PLUGIN_URL_FILTERING_AUTH.md) — modi, test, upgrade
- [Hardening](GUIDE/GUIDA_HARDENING_ATS.md) — cosa/perché/come modificare
- [Manuale ATS](GUIDE/MANUALE_ATS.md) — riferimento ATS

## Man pages

```bash
man ats-ctl             # Gestione policy
man ats-proxy-filter    # Plugin architecture
```

## Repository

- **Pubblica** (questa): `ats-proxy-enterprise` — installazione e guide
- **Sviluppo**: `ats-proxy-enterprise-dev` — storico, build, documenti interni

## Licenza

Fair Enterprise License v1.0 (FEL-1.0). Vedi [LICENSE.md](LICENSE.md).
