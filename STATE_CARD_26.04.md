# STATE CARD — ATS Proxy Enterprise (Ubuntu 26.04 LTS)

## Identita
- **Progetto**: Apache Traffic Server — Proxy Outbound Enterprise
- **OS**: Ubuntu 26.04 LTS (Resolute Raccoon)
- **ATS**: 9.2.13 LTS (compilato da sorgente + PCRE1 8.45)
- **VM Proxmox**: ID 134, nome `ats-proxy-02`, IP `192.168.89.28`
- **Creato**: 24 Maggio 2026
- **Guida riferimento**: `GUIDA_INSTALLAZIONE_ATS_v2.0_UBUNTU_26.04.md` (v1.1, testata)

## Stack
- **OS**: Ubuntu 26.04 LTS (Resolute Raccoon) — kernel 6.14+
- **ATS**: 9.2.13 LTS (compilato da sorgente)
- **PCRE**: 8.45 (compilato da sorgente in /usr/local/pcre)
- **Toolchain reale**: GCC 15.2.0, OpenSSL 3.5.5, PCRE2 10.46 (nativo)
- **Porta proxy**: 8080
- **Utente servizio**: ats (nologin)
- **Config dir**: /etc/trafficserver/
- **Install dir**: /opt/trafficserver/

## Documentazione
- **Guida Installazione 26.04**: `GUIDA_INSTALLAZIONE_ATS_v2.0_UBUNTU_26.04.md`
- **Guida Concettuale**: `GUIDA_CONCETTUALE_ATS_v1.0.md` (invariata, ATS e lo stesso)
- **Guida Operativa**: `GUIDA_OPERATIVA_ATS_v1.0.md` (invariata, operazioni identiche)
- **Guida Installazione 24.04**: `GUIDA_INSTALLAZIONE_ATS_v1.0.md` (originale)
- **Audit Sicurezza & Compliance**: `AUDIT_SICUREZZA_COMPLIANCE_v1.0.md`

## Differenze rispetto a 24.04

| Aspetto | 24.04 Noble | 26.04 Resolute |
|---------|------------|----------------|
| Kernel | 6.8.x | 6.14.x+ |
| GCC | 13.x | 14.x |
| OpenSSL | 3.0.x LTS | 3.4.x |
| PCRE1 (libpcre3) | Disponibile | Probabilmente rimosso |
| Systemd hardening base | Minimo | ProtectSystem=strict, PrivateTmp, NoNewPrivileges |
| Firewall backend | iptables | nftables (UFW trasparente) |
| SSH hardening | Non documentato | Aggiunto (key-only, no root) |
| unattended-upgrades | Non documentato | Aggiunto e configurato |
| Versionamento config | Non documentato | etckeeper configurato |
| Verifica integrita download | Non documentata | SHA256 verificato |
| Supporto LTS | 10 anni (fino 2034) | 12 anni (fino 2038) |

## Miglioramenti di sicurezza nella guida 26.04

1. **SHA256 checksum verification** — download ATS verificato
2. **SSH hardening** — key-only auth, no root login
3. **Systemd hardening** — ProtectSystem=strict, PrivateTmp, NoNewPrivileges, MemoryHigh/Max, CPUQuota
4. **unattended-upgrades** — security updates automatici
5. **etckeeper** — versionamento configurazioni con git
6. **sysctl aggiuntivi** — send_redirects=0, log_martians=1, kernel.core_pattern=false, kernel.sysrq=0

## Gap aperti (da AUDIT — validi per entrambe le versioni)

### Critici da risolvere
- [ ] GDPR: IP nei log = dato personale → retention policy, informativa, DPIA
- [ ] D.Lgs 196/2003 Art. 132: conservazione 6 anni dati traffico
- [ ] NIS2: procedura incident response con template notifica
- [ ] Remote syslog / centralizzazione log
- [ ] Fail2ban per SSH e proxy
- [ ] Health check automatico + alerting
- [ ] Test di carico >10 req/s (100, 500, 1000)
- [ ] AppArmor profilo per ATS

### Medi da pianificare
- [ ] Log JSON strutturati
- [ ] Separazione audit/access log
- [ ] Correlation ID (X-Request-Id)
- [ ] Audit accesso amministrativo (auditd)
- [ ] Backup automatico via cron
- [ ] Rate limiting plugin
- [ ] ISO 27001 mapping

## Configurazioni attive
- `records.config`: forward proxy su porta 8080, DNS via systemd-resolved
- `ip_allow.yaml`: 127.0.0.1/::1 + 192.168.89.0/24 allowed, resto deny
- `logging.yaml`: formato audit (IP client, request, status, bytes, FQDN)
- `storage.config`: 10 GB cache su /var/lib/trafficserver/cache
- `remap.config`: vuoto (forward proxy puro)
- Systemd: `/etc/systemd/system/trafficserver.service` (Type=forking + hardening)

## Firewall
- UFW: deny incoming, allow outgoing
- Regole: SSH (22/tcp), ATS proxy da 192.168.89.0/24 (8080/tcp)
- Backend nftables (26.04 default)

## Test eseguiti (validi cross-version)
- ✅ **ACL: ip_allow.yaml e first-match (ordine CONTA)** — deny /32 PRIMA di allow /24 = bloccato
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
- `logging.yaml` ha priorita su `logs_xml.config` in ATS 9.2.x
- `url_remap.remap_required=0` e OBBLIGATORIO per forward proxy
- PCRE1 (`libpcre3-dev`) potrebbe mancare su 26.04 — usare `--enable-pcre2` o compilare PCRE1 da sorgente
- DNS: usare `NULL` per delegare a /etc/resolv.conf (systemd-resolved su 127.0.0.53)
- Mai `ufw enable` senza prima `ufw allow 22/tcp`
- Su 26.04, UFW backend e nftables (trasparente, stessi comandi)

---
*Ultimo aggiornamento: 24 Maggio 2026 — Audit completato, guida 26.04 creata*
