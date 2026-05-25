# STATE CARD — ATS Proxy Enterprise

## Identità
- **Progetto**: Apache Traffic Server — Proxy Outbound Enterprise
- **Directory**: `~/CULLA-instance/03_ICT/ats-proxy/`
- **Repository GitHub**: `https://github.com/tripersonale/ats-proxy-enterprise.git`
- **VM Proxmox**: ID 130, nome `ats-proxy-01`, IP `192.168.89.27`
- **Creato**: 24 Maggio 2026

## Stack
- **OS**: Ubuntu 24.04.4 LTS (Noble)
- **ATS**: 9.2.13 LTS (compilato da sorgente)
- **Porta proxy**: 8080
- **Utente servizio**: ats (nologin)
- **Config dir**: /etc/trafficserver/
- **Install dir**: /opt/trafficserver/

## Documentazione
- **Guida Installazione (UNIFICATA)**: `GUIDA_INSTALLAZIONE_ATS_v3.0_UNIFICATA.md` — copre 24.04 e 26.04
- **Guida Installazione 24.04**: `GUIDA_INSTALLAZIONE_ATS_v1.0.md` (v1.2, storico)
- **Guida Installazione 26.04**: `GUIDA_INSTALLAZIONE_ATS_v2.0_UBUNTU_26.04.md` (v1.1, storico)
- **Guida Concettuale**: `GUIDA_CONCETTUALE_ATS_v1.0.md`
- **Guida Operativa**: `GUIDA_OPERATIVA_ATS_v1.0.md` (v1.1 — debug, compliance, incident response)
- **Guida Upgrade + CVE**: `GUIDA_UPGRADE_CVE_v1.0.md` — aggiornamento, compatibilita, rollback
- **Manifesto Principi**: `MANIFESTO_PRINCIPI_v1.0.md`
- **Guida URL Filtering**: `GUIDA_URL_FILTER_v1.0.md` — 3 livelli: Deny, Whitelist, Auth-Gated + Admin bypass
- **Guida Log & SIEM**: `GUIDA_LOG_SIEM_v1.0.md` — forwarding audit log a syslog/ELK
- **Guida Plugin Unificato**: `GUIDA_PLUGIN_UNIFICATO_v1.0.md` — header_rewrite + basic_auth
- **Audit Sicurezza & Compliance**: `AUDIT_SICUREZZA_COMPLIANCE_v1.0.md`
- **State Card 26.04**: `STATE_CARD_26.04.md`

## Stato
🟢 **24.04 Operativo + Hardened** — VM 130 (192.168.89.27). SSH hardening, fail2ban, etckeeper, systemd hardening applicati.
🟢 **26.04 Operativo + Testato** — VM 134 (192.168.89.28). Compilato ATS 9.2.13 + PCRE1 8.45 da sorgente. Batteria test superata.

## Accesso
- **VM 130 (24.04)**: `ssh -i /tmp/vm-130-key ubuntu@192.168.89.27`
- **VM 134 (26.04)**: `ssh -i /tmp/vm-134-key ubuntu@192.168.89.28`

## Configurazioni attive
- `records.config`: forward proxy su porta 8080, DNS via systemd-resolved
- `ip_allow.yaml`: 127.0.0.1/::1 + 192.168.89.0/24 allowed, resto deny
- `logging.yaml`: formato audit (IP client, request, status, bytes, FQDN)
- `storage.config`: 10 GB cache su /var/lib/trafficserver/cache
- `remap.config`: vuoto (forward proxy puro)
- Systemd: `/etc/systemd/system/trafficserver.service` (Type=forking + ProtectSystem=strict, NoNewPrivileges, PrivateTmp, MemoryHigh=2G)
- SSH: key-only auth, root login disabilitato
- fail2ban: jail SSH attivo
- unattended-upgrades: security updates automatici
- etckeeper: versionamento /etc/trafficserver con git

## Firewall
- UFW: deny incoming, allow outgoing
- Regole: SSH (22/tcp), ATS proxy da 192.168.89.0/24 (8080/tcp)

## Prossime azioni
- [ ] Aggiungere subnet aggiuntive a ip_allow.yaml per produzione
- [ ] Testare ACL da IP remoto (localhost non testa UFW)
- [ ] Configurare plugin rate_limit se necessario
- [ ] Testare sotto carico reale (>100 req/s)
- [ ] Automatizzare backup configurazioni via cron
- [ ] Valutare Prometheus exporter per monitoring

## Test eseguiti (2026-05-24, 2 batterie)
- ✅ **ACL: ip_allow.yaml è first-match (ordine CONTA)** — deny /32 PRIMA di allow /24 = bloccato
- ✅ **ACL: deny /32 funziona** — con RESTART, blocco a livello TCP (connection fail)
- ✅ **ACL: reload NON applica deny** — `traffic_ctl config reload` ignora ip_allow.yaml per i deny
- ✅ **Logging**: FQDN + backend hostname per HTTP e HTTPS CONNECT
- ✅ **Resilienza**: stop/start pulito, 10 richieste concorrenti 200 OK
- ✅ **UFW**: due layer di sicurezza funzionanti
- ⚠️ CONNECT bypassa filtro `method:` in ip_allow.yaml
- ⚠️ `%<{SERVC}pquc>` non valido in logging.yaml — usare `%<shn>`

## Regola ip_allow.yaml definitiva
1. **First-match** (ordine conta, come iptables)
2. **Deny PRIMA di allow** per bloccare
3. **RESTART obbligatorio** per i deny (reload non basta)
4. **Blocco a livello TCP** (connection fail), non HTTP 403

## Note tecniche
- `logging.yaml` ha priorità su `logs_xml.config` in ATS 9.2.x
- `url_remap.remap_required=0` e OBBLIGATORIO per forward proxy
- `libpcre3-dev` richiesto OLTRE a `libpcre2-dev` (ATS 9.2.13 usa PCRE1)
- DNS: usare `NULL` per delegare a /etc/resolv.conf (systemd-resolved su 127.0.0.53)
- Mai `ufw enable` senza prima `ufw allow 22/tcp`

---
*Ultimo aggiornamento: 24 Maggio 2026 — Sessione deploy + test*
