# ATS Proxy Enterprise — Manifesto dei Principi

## Fondamenti architetturali, sicurezza e conformita normativa

**Versione 1.0 — 24 Maggio 2026**

---

## Preambolo

Questo manifesto definisce i principi fondanti che governano la progettazione, l'implementazione e l'operativita del proxy ATS Enterprise. Ogni principio e mappato ai requisiti normativi applicabili affinche il sistema sia non solo tecnicamente solido, ma anche legalmente conforme.

I riferimenti normativi considerati:
- **GDPR** — Regolamento UE 2016/679 (protezione dati personali)
- **NIS2** — Direttiva UE 2022/2555 (sicurezza reti e informazione)
- **D.Lgs 196/2003** — Codice Privacy italiano (agg. D.Lgs 101/2018)
- **D.Lgs 138/2024** — Recepimento italiano NIS2
- **PSNC** — D.L. 105/2019 + DPCM 81/2021 (Perimetro Sicurezza Nazionale Cibernetica)
- **ISO 27001:2022** — Sistema gestione sicurezza informazioni
- **D.P.R. 15/01/2018 n. 37** — Regolamento ACN (ex AgID) misure minime ICT PA (se applicabile)

---

## Principio 1 — Least Privilege (Minimo Privilegio)

**Enunciato**: Ogni componente esegue con i privilegi minimi necessari alla sua funzione. Nessun servizio gira come root.

**Implementazione**:
- Utente dedicato `ats` con shell `/usr/sbin/nologin`
- Gruppo dedicato `ats`, nessuna appartenenza a gruppi privilegiati
- File system: `ProtectSystem=strict`, `ReadWritePaths` limitati
- `NoNewPrivileges=true` in systemd (impedisce escalation via setuid)

**Mappatura normativa**:
| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| GDPR | Art. 25.1 | Data protection by design and by default |
| GDPR | Art. 32.1(b) | Ability to ensure ongoing confidentiality, integrity, availability |
| NIS2 | Art. 21.2(i) | Human resources security, access control policies |
| ISO 27001 | A.9.2.1 | User access provisioning |
| ISO 27001 | A.8.2 | Privileged access rights |

---

## Principio 2 — Defense in Depth (Difesa a Strati)

**Enunciato**: La sicurezza non dipende da un singolo meccanismo. Barriere multiple indipendenti proteggono il sistema anche se un layer viene compromesso.

**Implementazione**:
- **Layer 1 — Firewall (UFW/nftables)**: Blocco a livello TCP, default deny incoming.
- **Layer 2 — ACL ATS (ip_allow.yaml)**: Blocco a livello HTTP, first-match, loggato.
- **Layer 3 — Kernel hardening (sysctl)**: Protezioni rete (syncookies, rfc1337, no redirects).
- **Layer 4 — Systemd hardening**: Filesystem read-only, namespace privati, device limitati.
- **Layer 5 — Filesystem permissions**: Config file `chmod 640`, ownership `ats:ats`.

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

## Principio 3 — Auditability (Tracciabilita Completa)

**Enunciato**: Ogni azione significativa del sistema deve essere registrata, immutabile, e ricostruibile a posteriori. Chi ha fatto cosa, quando, da dove, con quale esito.

**Implementazione**:
- **Access log**: Ogni richiesta proxy loggata con IP client, timestamp, FQDN, status, bytes, backend (`audit.log`).
- **Log rotation**: Rolling ogni 24h, auto-delete a 10 GB, prevenzione disk-full.
- **Configuration audit**: `etckeeper` (git su `/etc/trafficserver`) per tracciare ogni modifica.
- **System journal**: `journalctl -u trafficserver` per eventi di sistema e diagnostica.
- **SSH access log**: `/var/log/auth.log` traccia sessioni amministrative.

**Da implementare**:
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

## Principio 4 — Data Minimization & Retention (Minimizzazione e Conservazione)

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

## Principio 5 — Resilienza (Resilienza Operativa)

**Enunciato**: Il sistema deve continuare a funzionare in condizioni avverse (guasti, carico, attacchi) e, se interrotto, riprendersi automaticamente nel minor tempo possibile.

**Implementazione**:
- **Auto-restart**: `Restart=on-failure`, `RestartSec=5s` in systemd.
- **Graceful degradation**: Connessioni throttlate a 30000, rifiuto sovraccarico.
- **Lock file recovery**: Documentata procedura cleanup in troubleshooting.
- **Resource limits**: `MemoryHigh=2G`, `MemoryMax=3G` (26.04), `LimitNOFILE=65535`.
- **Backup configurazioni**: Procedura manuale documentata.

**Da implementare**:
- [x] Health check automatico base (gap RES-01 parzialmente chiuso)
- [ ] Alerting esterno su health check
- [ ] Test di carico >100 req/s e benchmark latenza (gap RES-02)
- [ ] Backup automatico via cron (gap RES-05)
- [ ] Disaster recovery runbook completo

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

## Principio 6 — Secure by Default & Vulnerability Management

**Enunciato**: La configurazione predefinita e la piu restrittiva possibile. Le vulnerabilita note sono gestite proattivamente con patching tempestivo.

**Implementazione**:
- **Compilazione minimale**: `--disable-tests`, `--disable-examples`, `--disable-maintainer-mode`
- **Funzioni pericolose disabilitate**: `push_method_enabled=0`
- **Debug disabilitato**: `diags.debug.enabled=0` in produzione
- **ATS 9.2.13 LTS**: 11 CVE chiuse rispetto alla 9.2.3 dai repo Ubuntu
- **Aggiornamenti automatici OS**: `unattended-upgrades` per security patches

**Da implementare**:
- [ ] Procedura formale di vulnerability assessment periodico
- [ ] Canale di notifica per nuove CVE ATS
- [ ] Patching plan per ATS (compilare nuova versione)

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

## Principio 7 — Encryption & Data Protection

**Enunciato**: Proteggere i dati in transito e a riposo con crittografia adeguata. Non ispezionare traffico cifrato senza autorizzazione esplicita e base legale.

**Implementazione**:
- **HTTPS tunnel**: CONNECT end-to-end cifrato, il proxy NON vede il contenuto.
- **Cache sicura**: `/opt/trafficserver/var/trafficserver/cache` accessibile solo da `ats:ats` (mode 700).
- **Config file**: `chmod 640`, leggibili solo da root e ats.

**Da implementare**:
- [x] TLS frontend ATS opzionale documentato su porta 8443 (gap SEC-09 mitigato)
- [ ] Cifratura backup configurazioni se contengono segreti

**Mappatura normativa**:
| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(h) | Policies regarding cryptography and encryption |
| GDPR | Art. 32.1(a) | Pseudonymisation and encryption of personal data |
| ISO 27001 | A.8.24 | Use of cryptography |
| PSNC | Art. 1 DPCM 81/2021 | Protezione dati in transito |
| D.Lgs 196 | Art. 2-ter | Trattamento dati in ambito lavorativo |

---

## Principio 8 — Segregation of Duties (Separazione dei Ruoli)

**Enunciato**: Nessuna persona deve avere il controllo completo su un processo critico. Le attivita di amministrazione, monitoraggio e audit sono separate.

**Implementazione**:
- **Amministratore di sistema**: Accesso SSH (key-only), sudo per modifiche config e restart.
- **Operatore**: Puo visualizzare log, metriche, stato. Non puo modificare config.
- **Auditor**: Accesso read-only ai log, etckeeper history, audit trail.

**Da implementare**:
- [ ] Definire gruppi sudo separati (ats-admin, ats-operator, ats-auditor)
- [ ] Loggare tutti i comandi sudo via auditd

**Mappatura normativa**:
| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(i) | Access control policies, asset management |
| GDPR | Art. 32.4 | Access to personal data only on instructions |
| ISO 27001 | A.5.2 | Segregation of duties |
| ISO 27001 | A.5.3 | Management responsibilities |
| ISO 27001 | A.9.1 | Business requirements of access control |

---

## Principio 9 — Incident Response (Risposta agli Incidenti)

**Enunciato**: Ogni incidente di sicurezza deve essere rilevato, contenuto, analizzato e notificato entro tempi definiti. Le procedure sono predefinite, documentate e testate.

**Implementazione**:
- **Detection**: Monitoraggio log (`tail -f audit.log`, `journalctl`), `traffic_top`.
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

## Principio 10 — Continuous Improvement (Miglioramento Continuo)

**Enunciato**: La sicurezza non e uno stato ma un processo. Il sistema viene regolarmente testato, verificato e migliorato sulla base di nuove minacce, nuove normative e lezioni apprese.

**Implementazione**:
- **Test di regressione**: Batteria test ACL, logging, resilienza dopo ogni modifica.
- **Config validation**: `traffic_server -C verify_config` prima di ogni reload/restart.
- **Versionamento configurazioni**: etckeeper per tracciare ogni modifica.
- **Audit periodici**: Questo manifesto e le guide associate sono soggetti a revisione almeno annuale.

**Da implementare**:
- [ ] Penetration test annuale
- [ ] Review trimestrale ACL
- [ ] Report metriche a CISO/DPO

**Mappatura normativa**:
| Norma | Riferimento | Requisito |
|-------|------------|-----------|
| NIS2 | Art. 21.2(f) | Policies to assess effectiveness |
| GDPR | Art. 32.1(d) | Regular testing, assessing, evaluating |
| ISO 27001 | A.5.1 | Policies for information security (review) |
| ISO 27001 | A.8.16 | Monitoring and review |
| ISO 27001 | A.5.36 | Compliance with policies, rules, standards |

---

## Quadro Riepilogativo: Principi → Normative

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

## Versionamento e Approvazioni

| Versione | Data | Autore | Modifiche |
|----------|------|--------|-----------|
| 1.0 | 24/05/2026 | ATS Proxy Team | Prima emissione — 10 principi con mappatura normativa completa |

**Prossima revisione programmata**: 24/11/2026 (6 mesi)

---

*Documento parte del progetto ATS Proxy Enterprise — da consultare insieme alle guide tecniche e all'audit di sicurezza.*
