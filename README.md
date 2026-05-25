# ATS Proxy Enterprise

**Apache Traffic Server 9.2.13 — Proxy Outbound Enterprise con URL Filtering, Autenticazione e Hardening**

[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04%20LTS-orange)](https://releases.ubuntu.com/24.04/)
[![Ubuntu 26.04](https://img.shields.io/badge/Ubuntu-26.04%20LTS-orange)](https://releases.ubuntu.com/26.04/)
[![ATS 9.2.13](https://img.shields.io/badge/ATS-9.2.13-blue)](https://trafficserver.apache.org/)
[![Tested](https://img.shields.io/badge/Tested-50%20concurrent-green)]()
[![NIS2](https://img.shields.io/badge/Compliance-NIS2%20%7C%20GDPR%20%7C%20ISO%2027001-lightgrey)]()

## Cosa offre

Proxy HTTP/HTTPS enterprise con autenticazione integrata, URL filtering a 3 livelli, hardening completo e logging forense. Due VM di test (Ubuntu 24.04 e 26.04) con batteria test a 50 richieste concorrenti.

| Funzione | Dettaglio |
|----------|-----------|
| **Proxy forward** | HTTP + HTTPS CONNECT su porta 8080 e 8443 (TLS) |
| **URL Filtering** | DENY (403), WHITELIST (pass), AUTH-GATED (407) |
| **Autenticazione** | Proxy-Authorization Basic con utenti da config file |
| **Admin bypass** | IP in whitelist saltano tutte le regole |
| **Hardening** | SSH key-only, fail2ban, UFW, systemd hardening, sysctl |
| **Logging** | Audit log con FQDN, IP, status — forwardabile a SIEM/ELK |
| **Monitoraggio** | Health check automatico, metriche traffic_ctl |
| **Plugin custom** | `ats_proxy_filter.so` — 300 righe C, 50+ concorrenti testato |

## Principi fondanti

```yaml
1. Least Privilege      — utente dedicato ats, shell nologin, systemd hardening
2. Defense in Depth     — UFW → ip_allow.yaml → URL filter → Auth
3. Auditability         — ogni richiesta loggata, etckeeper per config
4. Data Minimization    — FQDN loggato, non URL completo. HTTPS tunnel cifrato
5. Resilience           — auto-restart, lock recovery, 50 req/s concorrenti
6. Secure by Default    — ATS 9.2.13 compilato da sorgente (11 CVE chiuse)
7. Encryption           — TLS 1.3 frontend, HTTPS end-to-end
8. Segregation of Duties— admin/operator/auditor via SSH key + sudo
9. Incident Response    — procedura documentata, notifica NIS2 24h/72h
10. Continuous Improvement — audit periodico, test regressione, CVE monitoring
```

## Guida rapida

### Installazione (5 minuti)

```bash
# 1. Installa dipendenze
sudo apt install -y build-essential libssl-dev libpcre3-dev zlib1g-dev ...

# 2. Compila ATS da sorgente
cd /tmp && wget https://downloads.apache.org/trafficserver/trafficserver-9.2.13.tar.bz2
tar -xjf trafficserver-9.2.13.tar.bz2 && cd trafficserver-9.2.13
./configure --prefix=/opt/trafficserver --with-user=ats --enable-pcre
make -j$(nproc) && sudo make install

# 3. Configura e avvia
sudo tee /etc/trafficserver/records.config ... # porta 8080, forward proxy
sudo tee /etc/trafficserver/ip_allow.yaml ...  # subnet autorizzate
sudo systemctl enable --now trafficserver

# 4. Verifica
curl -x http://localhost:8080 http://httpbin.org/ip  # → 200 OK
```

### Plugin URL Filtering + Auth (2 minuti)

```bash
# Copia il plugin
sudo cp ats_proxy_filter.so /opt/trafficserver/lib/modules/

# Configura
sudo tee /etc/trafficserver/ats_proxy_filter.conf << 'EOF'
ADMIN 192.168.89.10
DENY httpbin.org
DENY bad.com
WHITELIST google.com
WHITELIST github.com
USER admin proxy2026
USER user1 pass123
EOF

sudo tee /etc/trafficserver/plugin.config << 'EOF'
ats_proxy_filter.so
EOF

sudo systemctl restart trafficserver

# Test
curl -x http://proxy:8080 http://httpbin.org/ip            # → 403 Forbidden
curl -x http://proxy:8080 http://google.com                 # → 301 (whitelist)
curl -x http://proxy:8080 http://wikipedia.org              # → 407 Auth Required
curl -x http://proxy:8080 --proxy-user admin:proxy2026 ...  # → 200 OK
```

## Documentazione

| Documento | Contenuto |
|-----------|-----------|
| [`GUIDA_INSTALLAZIONE_ATS_v3.0_UNIFICATA.md`](GUIDA_INSTALLAZIONE_ATS_v3.0_UNIFICATA.md) | Installazione completa Ubuntu 24.04 e 26.04 |
| [`GUIDA_PLUGIN_UNIFICATO_v2.0.md`](GUIDA_PLUGIN_UNIFICATO_v2.0.md) | Plugin URL filtering + auth |
| [`GUIDA_UPGRADE_CVE_v1.0.md`](GUIDA_UPGRADE_CVE_v1.0.md) | Upgrade ATS, gestione CVE, compatibilità |
| [`GUIDA_OPERATIVA_ATS_v1.0.md`](GUIDA_OPERATIVA_ATS_v1.0.md) | Operazioni quotidiane, debug, compliance GDPR |
| [`GUIDA_URL_FILTER_v1.0.md`](GUIDA_URL_FILTER_v1.0.md) | URL filtering con header_rewrite |
| [`GUIDA_LOG_SIEM_v1.0.md`](GUIDA_LOG_SIEM_v1.0.md) | Log forwarding a syslog/ELK |
| [`GUIDA_CONCETTUALE_ATS_v1.0.md`](GUIDA_CONCETTUALE_ATS_v1.0.md) | Come funziona ATS, architettura, ACL |
| [`MANIFESTO_PRINCIPI_v1.0.md`](MANIFESTO_PRINCIPI_v1.0.md) | 10 principi, mappatura NIS2/GDPR/ISO 27001 |
| [`AUDIT_SICUREZZA_COMPLIANCE_v1.0.md`](AUDIT_SICUREZZA_COMPLIANCE_v1.0.md) | 42 gap identificati e risolti |

## VM di test

| VM | OS | IP | Plugin |
|----|----|----|--------|
| **130** | Ubuntu 24.04.4 LTS | 192.168.89.27 | v2.1 |
| **134** | Ubuntu 26.04 LTS | 192.168.89.28 | v2.1 |

## Stack tecnico

```
ATS 9.2.13 (compilato da sorgente)
├── Porta 8080 (HTTP)
├── Porta 8443 (TLS 1.3, CONNECT)
├── Plugin: ats_proxy_filter.so (OS_DNS hook)
├── Firewall: UFW + ip_allow.yaml
├── Hardening: SSH key-only, fail2ban, systemd, sysctl
├── Logging: audit.log → rsyslog/Filebeat → ELK/SIEM
├── Backup: etckeeper (git su /etc)
└── Monitor: health check cron, traffic_ctl metrics
```

## Requisiti

- Ubuntu Server 24.04 LTS o 26.04 LTS
- 2+ GB RAM, 10+ GB disco
- GCC, OpenSSL, PCRE1 (da apt su 24.04, da sorgente su 26.04)

## Licenza

Apache 2.0 — vedi [LICENSE](LICENSE)

---

*Progetto creato il 24 Maggio 2026. Ultimo aggiornamento: 25 Maggio 2026.*
