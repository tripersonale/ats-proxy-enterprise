# ATS Proxy Enterprise

> Forward Proxy HTTP/HTTPS con URL Filtering, Autenticazione Basic e Hardening Enterprise
> Allineato al MANIFESTO_ICT.md v1.0 e ai principi CULLA v2.0.2

**Versione 0.14.0** · ATS 9.2.13 LTS · Ubuntu 24.04 / 26.04 · Compliance GDPR / NIS2 / D.Lgs 196 / PSNC / ISO 27001

[![License: FEL-1.0](https://img.shields.io/badge/license-FEL--1.0-blue)](LICENSE.md) [![Hardening: 25/25](https://img.shields.io/badge/hardening-25%2F25-brightgreen)](TEST_MATRIX.md) [![Regression: 9/9](https://img.shields.io/badge/regression-9%2F9-brightgreen)](TEST_MATRIX.md)

---

## Manifesto ICT — I 10 Principi Operativi

Questo manifesto e il contratto operativo del proxy. Ogni principio e verificabile, mappato alle normative e legato a implementazioni concrete nel codice e nella configurazione. Derivato da `archive/storico/MANIFESTO_PRINCIPI_v1.0.md`.

I riferimenti normativi considerati:
- **GDPR** — Regolamento UE 2016/679 (protezione dati personali)
- **NIS2** — Direttiva UE 2022/2555 (sicurezza reti e informazione)
- **D.Lgs 196/2003** — Codice Privacy italiano (agg. D.Lgs 101/2018)
- **D.Lgs 138/2024** — Recepimento italiano NIS2
- **PSNC** — D.L. 105/2019 + DPCM 81/2021 (Perimetro Sicurezza Nazionale Cibernetica)
- **ISO 27001:2022** — Sistema gestione sicurezza informazioni

---

### Principio 1 — Least Privilege (Minimo Privilegio)

**Enunciato**: Ogni componente esegue con i privilegi minimi necessari alla sua funzione. Nessun servizio gira come root.

**Implementazione**:
- Utente dedicato `ats` con shell `/usr/sbin/nologin`
- Gruppo dedicato `ats`, nessuna appartenenza a gruppi privilegiati
- File system: `ProtectSystem=strict`, `ReadWritePaths` limitati
- `NoNewPrivileges=true` in systemd (impedisce escalation via setuid)

**Gap residui**:
- [ ] Nessuno — verificato 25/25 da `scripts/ats-hardening-check.sh`

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| GDPR | Art. 25.1 | Data protection by design and by default |
| GDPR | Art. 32.1(b) | Ability to ensure ongoing confidentiality, integrity, availability |
| NIS2 | Art. 21.2(i) | Human resources security, access control policies |
| ISO 27001 | A.9.2.1 | User access provisioning |
| ISO 27001 | A.8.2 | Privileged access rights |

---

### Principio 2 — Defense in Depth (Difesa a Strati)

**Enunciato**: La sicurezza non dipende da un singolo meccanismo. Barriere multiple indipendenti proteggono il sistema anche se un layer viene compromesso.

**Implementazione**:
- **Layer 1 — Firewall (UFW/nftables)**: Blocco a livello TCP, default deny incoming.
- **Layer 2 — ACL ATS (ip_allow.yaml)**: Blocco a livello HTTP, first-match, loggato.
- **Layer 3 — Kernel hardening (sysctl)**: Protezioni rete (syncookies, rfc1337, no redirects).
- **Layer 4 — Systemd hardening**: Filesystem read-only, namespace privati, device limitati.
- **Layer 5 — Filesystem permissions**: Config file `chmod 640`, ownership `ats:ats`.

**Gap residui**:
- [ ] Nessuno — 5 layer verificati dall'hardening check su entrambe le piattaforme

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(a) | Risk analysis and information system security policies |
| NIS2 | Art. 21.2(d) | Supply chain security |
| ISO 27001 | A.8.20 | Network security |
| ISO 27001 | A.8.22 | Web filtering (proxy security) |
| PSNC | Art. 1 DPCM 81/2021 | Misure minime di sicurezza — difesa perimetrale |
| GDPR | Art. 32.1(d) | Process for regular testing of technical measures |

---

### Principio 3 — Auditability (Tracciabilita Completa)

**Enunciato**: Ogni azione significativa del sistema deve essere registrata, immutabile, e ricostruibile a posteriori. Chi ha fatto cosa, quando, da dove, con quale esito.

**Implementazione**:
- **Access log**: Ogni richiesta proxy loggata con IP client, timestamp, FQDN, status, bytes, backend (`audit.log`).
- **Log rotation**: Rolling ogni 24h, auto-delete a 10 GB, prevenzione disk-full.
- **Configuration audit**: `etckeeper` (git su `/etc/trafficserver`) per tracciare ogni modifica.
- **System journal**: `journalctl -u trafficserver` per eventi di sistema e diagnostica.
- **SSH access log**: `/var/log/auth.log` traccia sessioni amministrative.
- **Health check cron**: Log in `/var/log/ats-health.log`, mode `640`, verificato da hardening check.

**Gap residui**:
- [ ] Remote syslog centralizzato (gap AUD-02)
- [ ] Log immutabili / firma hash (gap AUD-01)
- [ ] Log strutturati JSON (gap AUD-04)
- [ ] Auditd per comandi sudo (gap AUD-05)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| GDPR | Art. 30 | Records of processing activities (registro trattamenti) |
| GDPR | Art. 5.2 | Accountability (dimostrare conformita) |
| NIS2 | Art. 21.2(e) | Policies and procedures to assess effectiveness |
| D.Lgs 196 | Art. 132 | Dati di traffico telematico — conservazione |
| ISO 27001 | A.8.15 | Logging of activities |
| ISO 27001 | A.8.16 | Monitoring activities |
| ISO 27001 | A.8.17 | Clock synchronisation (NTP per timestamp accurati) |

---

### Principio 4 — Data Minimization & Retention (Minimizzazione e Conservazione)

**Enunciato**: Raccogliere solo i dati necessari allo scopo dichiarato. Conservarli per il tempo minimo richiesto dalla legge e dallo scopo operativo. Cancellarli automaticamente alla scadenza.

**Implementazione**:
- **Cosa logghiamo**: IP client, timestamp, FQDN richiesto, metodo HTTP, status code, bytes trasferiti, backend hostname.
- **Cosa NON logghiamo**: URL completo (solo FQDN), body delle richieste, header sensibili, cookie.
- **Cosa NON ispezioniamo**: Contenuto tunnel HTTPS (cifrato end-to-end).

**⚠️ NOTA LEGALE (IP = dato personale)**: L'indirizzo IP del client e considerato **dato personale** ai sensi del GDPR (Art. 4.1 + C-582/14 Breyer). Il trattamento deve avere:
1. **Base giuridica** (Art. 6): legittimo interesse del titolare (sicurezza rete) o consenso.
2. **Informativa** (Art. 13-14): gli utenti devono essere informati del trattamento.
3. **Tempo di conservazione** (Art. 5.1.e): definito e documentato.
4. **Diritto di accesso** (Art. 15): procedura per estrarre i log di un IP specifico.
5. **Diritto di cancellazione** (Art. 17): procedura per rimuovere i log di un IP specifico.

**Retention policy proposta**:

| Dato | Conservazione | Base normativa |
|------|--------------|----------------|
| Log accesso proxy (IP, FQDN, timestamp) | 6 mesi operativi + 6 anni giudiziari (su richiesta) | D.Lgs 196 Art. 132 |
| Log di sistema (journald) | 30 giorni | Buona prassi |
| Log diagnostici (diags.log) | 7 giorni | Debugging |
| Modifiche configurazione (etckeeper git) | Illimitato | Audit trail |
| Backup configurazioni | 12 mesi rolling | Business continuity |

**Gap residui**:
- [ ] Automatizzare la cancellazione dei log per scadenza retention (gap RET-01)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| GDPR | Art. 5.1(c) | Data minimisation |
| GDPR | Art. 5.1(e) | Storage limitation |
| GDPR | Art. 25.2 | Data minimisation by default |
| D.Lgs 196 | Art. 132 | Conservazione dati traffico 6 anni |
| ISO 27001 | A.8.10 | Information deletion |
| ISO 27001 | A.8.12 | Data leakage prevention |

---

### Principio 5 — Resilienza (Resilienza Operativa)

**Enunciato**: Il sistema deve continuare a funzionare in condizioni avverse (guasti, carico, attacchi) e, se interrotto, riprendersi automaticamente nel minor tempo possibile.

**Implementazione**:
- **Auto-restart**: `Restart=on-failure`, `RestartSec=5s` in systemd.
- **Graceful degradation**: Connessioni throttlate a 30000, rifiuto sovraccarico.
- **Lock file recovery**: Documentata procedura cleanup in troubleshooting.
- **Resource limits**: `MemoryHigh=2G`, `MemoryMax=3G` (26.04), `LimitNOFILE=65535`.
- **Health check**: Script cron attivo in `/etc/cron.hourly/`, log in `/var/log/ats-health.log`.
- **Backup configurazioni**: Procedura manuale documentata.

**Gap residui**:
- [x] ✅ Health check automatico base — implementato e verificato da hardening check
- [ ] Alerting esterno su health check (gap RES-03)
- [ ] Test di carico >100 req/s e benchmark latenza (gap RES-02)
- [ ] Backup automatico via cron (gap RES-05)
- [ ] Disaster recovery runbook completo (gap RES-04)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(c) | Business continuity, backup management, disaster recovery |
| NIS2 | Art. 21.2(b) | Incident handling |
| ISO 27001 | A.5.29 | ICT readiness for business continuity |
| ISO 27001 | A.5.30 | ICT readiness planning |
| ISO 27001 | A.8.14 | Redundancy of information processing facilities |
| PSNC | Art. 6 DPCM 81/2021 | Business continuity e disaster recovery |

---

### Principio 6 — Secure by Default & Vulnerability Management

**Enunciato**: La configurazione predefinita e la piu restrittiva possibile. Le vulnerabilita note sono gestite proattivamente con patching tempestivo.

**Implementazione**:
- **Compilazione minimale**: `--disable-tests`, `--disable-examples`, `--disable-maintainer-mode`
- **Funzioni pericolose disabilitate**: `push_method_enabled=0`
- **Debug disabilitato**: `diags.debug.enabled=0` in produzione
- **ATS 9.2.13 LTS**: 11 CVE chiuse rispetto alla 9.2.3 dai repo Ubuntu
- **Aggiornamenti automatici OS**: `unattended-upgrades` per security patches
- **fail2ban attivo**: jail `ats-proxy` per tentativi di auth falliti (configurato da installer)
- **Helper CVE**: Script installato per notifiche vulnerabilita note

**Gap residui**:
- [ ] Procedura formale di vulnerability assessment periodico (gap VUL-01)
- [ ] Canale di notifica per nuove CVE ATS (gap VUL-02)
- [ ] Patching plan per ATS (compilare nuova versione — gap VUL-03)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(e) | Security in network and information systems acquisition |
| NIS2 | Art. 21.2(f) | Vulnerability handling and disclosure |
| GDPR | Art. 32.1 | Security of processing (state of the art) |
| ISO 27001 | A.8.8 | Technical vulnerability management |
| ISO 27001 | A.8.9 | Configuration management |
| ISO 27001 | A.8.19 | Installation of software on operational systems |
| PSNC | Art. 1 DPCM 81/2021 | Aggiornamenti di sicurezza |

---

### Principio 7 — Encryption & Data Protection

**Enunciato**: Proteggere i dati in transito e a riposo con crittografia adeguata. Non ispezionare traffico cifrato senza autorizzazione esplicita e base legale.

**Implementazione**:
- **HTTPS tunnel**: CONNECT end-to-end cifrato, il proxy NON vede il contenuto.
- **Cache sicura**: `/var/lib/trafficserver/cache` accessibile solo da `ats:ats` (mode 700).
- **Config file**: `chmod 640`, leggibili solo da root e ats.
- **TLS frontend opzionale**: Porta 8443 documentata, non abilitata di default.

**Gap residui**:
- [x] ✅ TLS frontend ATS opzionale documentato su porta 8443 (gap SEC-09 chiuso — modulo presente nell'installer)
- [ ] TLS frontend non incluso nella batteria end-to-end del 2026-05-26 (gap SEC-10)
- [ ] Cifratura backup configurazioni se contengono segreti (gap SEC-11)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(h) | Policies regarding cryptography and encryption |
| GDPR | Art. 32.1(a) | Pseudonymisation and encryption of personal data |
| ISO 27001 | A.8.24 | Use of cryptography |
| PSNC | Art. 1 DPCM 81/2021 | Protezione dati in transito |
| D.Lgs 196 | Art. 2-ter | Trattamento dati in ambito lavorativo |

---

### Principio 8 — Segregation of Duties (Separazione dei Ruoli)

**Enunciato**: Nessuna persona deve avere il controllo completo su un processo critico. Le attivita di amministrazione, monitoraggio e audit sono separate.

**Implementazione**:
- **Amministratore di sistema**: Accesso SSH (key-only), sudo per modifiche config e restart.
- **Operatore**: Puo visualizzare log, metriche, stato. Non puo modificare config.
- **Auditor**: Accesso read-only ai log, etckeeper history, audit trail.

**Gap residui**:
- [ ] Definire gruppi sudo separati (ats-admin, ats-operator, ats-auditor — gap SEG-01)
- [ ] Loggare tutti i comandi sudo via auditd (gap SEG-02)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(i) | Access control policies, asset management |
| GDPR | Art. 32.4 | Access to personal data only on instructions |
| ISO 27001 | A.5.2 | Segregation of duties |
| ISO 27001 | A.5.3 | Management responsibilities |
| ISO 27001 | A.9.1 | Business requirements of access control |

---

### Principio 9 — Incident Response (Risposta agli Incidenti)

**Enunciato**: Ogni incidente di sicurezza deve essere rilevato, contenuto, analizzato e notificato entro tempi definiti. Le procedure sono predefinite, documentate e testate.

**Implementazione**:
- **Detection**: Monitoraggio log (`tail -f audit.log`, `journalctl`), `traffic_top`, health check cron.
- **Containment**: Blocco IP via `ip_allow.yaml` (deny + restart), blocco UFW.
- **Evidence preservation**: Log non sovrascrivibili, backup immediato config e log.

**Procedura Incident Response (sintesi)** — vedi sezione dedicata nella GUIDA_OPERATIVA.

| Fase | Azione | Tempo |
|------|--------|-------|
| Detection | Identificare anomalia da log/metriche | Immediato |
| Analysis & Classification | Determinare impatto e tipo | Entro 1h |
| Containment | Bloccare IP/utente malevolo | Entro 4h |
| Eradication | Rimuovere causa root (patch, config) | Entro 24h |
| Recovery | Ripristinare servizio normale | Entro 48h |
| Notification NIS2 | Early warning ad autorita competente (ACN in Italia) | **Entro 24h** |
| Notification NIS2 | Notifica completa con dettagli | **Entro 72h** |
| Notification GDPR | Notifica al Garante Privacy (se dati personali violati) | **Entro 72h** |
| Lessons Learned | Post-mortem, aggiornamento procedure | Entro 1 mese |

**Gap residui**:
- [ ] Test annuale del piano di incident response (gap IR-01)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 23.1 | Early warning entro 24h |
| NIS2 | Art. 23.4 | Notifica incidente entro 72h |
| GDPR | Art. 33 | Notifica violazione dati personali entro 72h |
| GDPR | Art. 34 | Comunicazione agli interessati (se rischio elevato) |
| D.Lgs 196 | Art. 32-bis | Notifica violazione dati |
| PSNC | Art. 3 D.L. 105/2019 | Notifica incidenti ACN |
| ISO 27001 | A.5.24 | Incident management planning |
| ISO 27001 | A.5.26 | Response to information security incidents |
| ISO 27001 | A.6.8 | Information security event reporting |

---

### Principio 10 — Continuous Improvement (Miglioramento Continuo)

**Enunciato**: La sicurezza non e uno stato ma un processo. Il sistema viene regolarmente testato, verificato e migliorato sulla base di nuove minacce, nuove normative e lezioni apprese.

**Implementazione**:
- **Test di regressione**: Batteria test ACL, logging, resilienza — eseguita dopo ogni modifica.
- **Hardening check**: Verifica 25 punti di controllo su ogni target.
- **Config validation**: `traffic_server -C verify_config` prima di ogni reload/restart.
- **Versionamento configurazioni**: etckeeper per tracciare ogni modifica.
- **Audit periodici**: Questo manifesto e le guide associate sono soggetti a revisione almeno annuale.
- **Repo consistency**: `scripts/check-repo-consistency.sh` previene riferimenti ad artefatti mancanti.

**Gap residui**:
- [ ] Penetration test annuale (gap CI-01)
- [ ] Review trimestrale ACL (gap CI-02)
- [ ] Report metriche a CISO/DPO (gap CI-03)

**Mappatura normativa**:

| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(f) | Policies to assess effectiveness |
| GDPR | Art. 32.1(d) | Regular testing, assessing, evaluating |
| ISO 27001 | A.5.1 | Policies for information security (review) |
| ISO 27001 | A.8.16 | Monitoring and review |
| ISO 27001 | A.5.36 | Compliance with policies, rules, standards |

---

### Quadro Riepilogativo: Principi → Normative

| Principio | GDPR | NIS2 | D.Lgs 196 | PSNC | ISO 27001 |
|-----------|------|------|-----------|------|-----------|
| 1. Least Privilege | Art. 25, 32 | Art. 21.2(i) | ✅ | ✅ | A.9.2, A.8.2 |
| 2. Defense in Depth | Art. 32 | Art. 21.2(a,d) | ✅ | Art. 1 DPCM 81 | A.8.20, A.8.22 |
| 3. Auditability | Art. 5.2, 30 | Art. 21.2(e) | Art. 132 | ✅ | A.8.15-17 |
| 4. Data Minimization | Art. 5.1(c,e), 25 | ✅ | Art. 132 | ✅ | A.8.10, A.8.12 |
| 5. Resilience | ✅ | Art. 21.2(b,c) | ✅ | Art. 6 DPCM 81 | A.5.29, A.5.30 |
| 6. Secure by Default | Art. 32 | Art. 21.2(e,f) | ✅ | Art. 1 DPCM 81 | A.8.8, A.8.9 |
| 7. Encryption | Art. 32.1(a) | Art. 21.2(h) | ✅ | Art. 1 DPCM 81 | A.8.24 |
| 8. Segregation of Duties | Art. 32.4 | Art. 21.2(i) | ✅ | ✅ | A.5.2, A.9.1 |
| 9. Incident Response | Art. 33, 34 | Art. 23 | Art. 32-bis | Art. 3 D.L. 105 | A.5.24, A.5.26 |
| 10. Continuous Improvement | Art. 32.1(d) | Art. 21.2(f) | ✅ | ✅ | A.5.1, A.5.36 |

---

## Allineamento ICT — Le 6 Domande di Verifica

Per ogni azione su questo progetto, le 6 domande del MANIFESTO_ICT.md v1.0:

1. **Aumenta la liberta integrata?** ✅ — Proxy governabile, documentato, senza vendor lock-in. Installabile su hardware proprio.
2. **E sicuro per default?** ✅ — `ProtectSystem=strict`, `NoNewPrivileges=true`, hardening 25/25.
3. **E documentato abbastanza da essere ripreso tra 6 mesi?** ✅ — Questo README, installer commentato, guide testate, etckeeper.
4. **I segreti sono separati dal metodo?** ✅ — Metodo/Istanza/Segreti: config file locali esclusi da Git, env template senza valori reali.
5. **Serve una DPIA?** ✅ — DPIA presente (`DPIA_v1.0.md`), registro trattamenti (`REGISTRO_TRATTAMENTI_v1.0.md`), retention documentata.
6. **Se domani non ci sono piu, qualcuno puo capirlo?** ✅ — `GUIDA_INSTALLAZIONE.md`, `GUIDA_OPERATIVA.md`, installer commentato, test, CHANGELOG.

---

## Manifesto Operativo (Regole del Progetto)

- Nessun requisito runtime implicito: sorgente plugin, binario plugin, script e manifest hash sono versionati in `ARTIFACTS.md`.
- Ogni comando documentato deve essere testato o marcato esplicitamente come non validato in `TEST_MATRIX.md`.
- L'installer e la guida manuale non devono divergere: il percorso supportato e quello automatizzato con file config e fallback interattivo.
- Hardening non dichiarato a parole: viene verificato da `scripts/ats-hardening-check.sh` (25 punti).
- Segreti fuori repo: password e chiavi non vanno versionate; usare file config locali esclusi da Git.
- ATS 10.x non e una baseline supportata finche non passa build plugin e regression test in lab.
- Repo consistency: `scripts/check-repo-consistency.sh` eseguito ad ogni release.

---

## Quick Start (Testato)

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env

bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive

bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

Modalita interattiva supportata:

```bash
sudo bash scripts/install-ats-proxy.sh
```

Se un file config e presente ma mancano valori richiesti, lo script chiede solo i valori mancanti o placeholder. Con `--non-interactive`, invece, fallisce prima di modificare il sistema.

---

## Risultati Validati

| Target | Installer completo | Regression | Hardening |
|--------|--------------------|------------|-----------|
| VM135 Ubuntu 24.04.4 | OK, 2026-05-26 | 9/9 OK | 25/25 OK |
| VM136 Ubuntu 26.04 | OK, 2026-05-26 | 9/9 OK | 25/25 OK |

Test regression coperti: service active, DENY `403 Forbidden`, WHITELIST `301`, AUTH missing `407`, AUTH valid `301`, AUTH wrong `407`, header `Proxy-Authenticate`, 50 richieste concorrenti DENY, 50 richieste concorrenti whitelist con credenziali.

Hardening coperto: systemd sandbox, UFW, fail2ban `sshd` e `ats-proxy`, unattended upgrades, etckeeper, permessi config/log, health check cron, helper CVE.

---

## Artefatti Runtime

| Artefatto | Percorso | Hash / Stato |
|-----------|----------|-------------|
| Plugin binario v2.1 | `bin/ats_proxy_filter_v21.so` | SHA256 `26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674` |
| Plugin sorgente v2.1 | `src/ats_proxy_filter_v21.c` | SHA256 `ac742e549c3081af44c320117ce0a8a1e8d9b80dbb76327f154e7d0797a7ffea` |
| Installer | `scripts/install-ats-proxy.sh` | End-to-end testato 24.04/26.04 |
| Regression test | `scripts/ats-regression-test.sh` | Testato 24.04/26.04 |
| Hardening check | `scripts/ats-hardening-check.sh` | Testato 24.04/26.04 |

**Provenance**: Plugin binario ricompilato da `src/ats_proxy_filter_v21.c` e validato su ATS 9.2.13. Il binario precedente (`6a1a73ff...`) e stato recuperato readonly da VM130/VM134 via Proxmox/libguestfs, testato transitoriamente su VM135, e sostituito con il build corrente. ATS source tarball verificata via SHA512 nell'installer.

---

## Documenti

| Documento | Scopo |
|-----------|-------|
| [`GUIDA_INSTALLAZIONE.md`](GUIDA_INSTALLAZIONE.md) | Installazione completa — manuale e automatizzato, dual-OS |
| [`GUIDA_OPERATIVA.md`](GUIDA_OPERATIVA.md) | Operativita quotidiana, upgrade, CVE, GDPR, incident response |
| [`GUIDA_TRASFERIMENTO_VM_v1.0.md`](GUIDA_TRASFERIMENTO_VM_v1.0.md) | Flusso repo privata → pacchetto → VM |
| [`AUDIT_SICUREZZA_COMPLIANCE_v1.0.md`](AUDIT_SICUREZZA_COMPLIANCE_v1.0.md) | Audit sicurezza e compliance normativa |
| [`DPIA_v1.0.md`](DPIA_v1.0.md) | Data Protection Impact Assessment |
| [`REGISTRO_TRATTAMENTI_v1.0.md`](REGISTRO_TRATTAMENTI_v1.0.md) | Registro dei trattamenti ex Art. 30 GDPR |
| [`DISASTER_RECOVERY_TEST_v1.0.md`](DISASTER_RECOVERY_TEST_v1.0.md) | Test e procedura di disaster recovery |
| [`ARTIFACTS.md`](ARTIFACTS.md) | Manifest artefatti e provenienza |
| [`TEST_MATRIX.md`](TEST_MATRIX.md) | Stato dei test eseguiti e gap residui |
| [`CHANGELOG.md`](CHANGELOG.md) | Cronologia release |
| [`STATE_CARD.md`](STATE_CARD.md) | Stato operativo sintetico |
| [`ROOT_CAUSE_REPLICABILITA_v1.0.md`](ROOT_CAUSE_REPLICABILITA_v1.0.md) | Root cause del precedente problema di replicabilita |
| [`IMPROVEMENTS.md`](IMPROVEMENTS.md) | Log miglioramenti, problemi noti, soluzioni proposte |
| [`CLA.md`](CLA.md) | Contributor License Agreement (revisione legale pendente) |

Le guide storiche sono in `archive/storico/`. Non sono il percorso operativo da seguire.

---

## Percorso Operativo Supportato

```bash
bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

## Limiti Noti

- Il plugin usa `TS_HTTP_OS_DNS_HOOK`. In teoria la cache DNS potrebbe saltare hook successivi su domini già risolti, ma i test rapidi su VM135/VM136 (v0.13.0) non hanno riprodotto il problema: richieste auth-gated restano `407`, whitelist genera log ripetuti. Comportamento identico tra plugin corrente e binario recuperato.
- ATS 10.x non e validato: fallisce build drop-in con `gcc` (richiede C++17) e con `g++ -std=c++17` (richiede header generati dal build system). Non aggiornare produzione ad ATS 10.x finche `GUIDA_OPERATIVA.md` §10 non riporta test reali.
- TLS frontend su porta 8443 e implementato nell'installer (`ATS_TLS_ENABLED=y`) ma non incluso nella batteria end-to-end del 2026-05-26.
- Carico oltre 50 richieste concorrenti non validato in questa sessione.
- Procedura formale di vulnerability assessment non ancora definita.
- Penetration test annuale non ancora eseguito.

## VM di Laboratorio

| VM | OS | IP | Stato |
|----|----|----|-------|
| VM135 | Ubuntu 24.04.4 | 192.168.89.35 | Installer / regression / hardening OK |
| VM136 | Ubuntu 26.04 | 192.168.89.36 | Installer / regression / hardening OK |

Chiavi operative persistenti in `~/CULLA-instance/01_SECRETS/ssh/`.

---

## Licenza

**Fair Enterprise License v1.0 (FEL-1.0)** — basata su Business Source License 1.1 (MariaDB).

In sintesi (vedi `LICENSE.plain.md` per spiegazione in italiano, `LICENSE.md` per testo vincolante):

- **Puoi**: usarlo in azienda, modificarlo, installarlo per clienti, fare hosting gestito, formazione, consulenza — gratis, citando il progetto.
- **Non puoi**: vendere il software come prodotto o creare un SaaS il cui core e questo proxy, senza accordo.
- **Se lo fai senza permesso**: 25% dei proventi lordi alla fondazione Tripersonale Onlus.
- **Se sei contributore**: royalty ridotta al 10%.
- **Piccola impresa** (<500k€/anno): esente dalle restrizioni commerciali.
- **Scadenza**: ogni versione diventa automaticamente Apache 2.0 dopo 4 anni dalla pubblicazione.

⚠️ **REVISIONE LEGALE PENDENTE**: licenza e modello di business da verificare con un legale italiano prima di uso commerciale.

---

*Documento allineato a: MANIFESTO_ICT.md v1.0, CULLA_DOCUMENTO_FONDATIVO_v2.0.md, CULLA_MANIFESTO_AI_v2.0.md*
*Versione documento: 2.0 — Ricostruito con stile archivio storico da MANIFESTO_PRINCIPI_v1.0.md (2026-05-24)*
