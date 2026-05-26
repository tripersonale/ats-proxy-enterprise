# ATS Proxy Enterprise — Registro delle Attività di Trattamento

## Ai sensi dell'Art. 30 del GDPR (Regolamento UE 2016/679)

**Versione 1.0 — 25 Maggio 2026**
**Da compilare a cura del Titolare del trattamento**

---

## Attività di trattamento n. 1 — Logging accessi proxy

| Campo (Art. 30.1) | Valore |
|-------------------|--------|
| **a) Titolare del trattamento** | [Nome Organizzazione] — [Indirizzo sede] |
| **a) DPO** | [Nome DPO] — [Contatti] |
| **b) Finalità del trattamento** | 1. Sicurezza della rete aziendale (rilevamento e risposta incidenti)<br>2. Ottemperanza obblighi di legge (Art. 132 D.Lgs 196/2003 — conservazione dati traffico telematico)<br>3. Applicazione policy di URL filtering aziendale |
| **c) Categorie di interessati** | Dipendenti e collaboratori dell'organizzazione che accedono a Internet tramite il proxy aziendale |
| **c) Categorie di dati personali** | - Indirizzo IP del dispositivo client<br>- FQDN (nome host) dei siti web visitati<br>- Data e ora della richiesta HTTP<br>- Metodo HTTP (GET, POST, CONNECT)<br>- Status code della risposta<br>- Byte trasferiti<br>- Username proxy (se autenticazione attiva) |
| **d) Categorie di destinatari** | - Personale IT autorizzato (amministratori di sistema)<br>- Autorità giudiziaria (su richiesta, ai sensi Art. 132 D.Lgs 196/2003) |
| **e) Trasferimenti extra-UE** | **Nessuno**. I log risiedono esclusivamente su server ubicati in [Italia/UE] |
| **f) Termini di conservazione** | - **6 mesi** per finalità operative (sicurezza rete)<br>- **6 anni** su richiesta dell'autorità giudiziaria (Art. 132 D.Lgs 196/2003)<br>- Cancellazione automatica al raggiungimento di 10 GB totali (log rotation 24h) |
| **g) Misure tecniche e organizzative** | Vedere dettaglio nella tabella sottostante |

### Misure di sicurezza (Art. 32 GDPR)

| Misura | Implementazione | Riferimento |
|--------|----------------|-------------|
| **Controllo accessi fisico** | Server in datacenter con accesso controllato | Policy aziendale |
| **Controllo accessi logico** | SSH key-only, utenti dedicati, sudo limitato, fail2ban | `GUIDA_COMPLETA §8` |
| **Cifratura dati in transito** | HTTPS tunnel end-to-end, SSH per amministrazione, TLS frontend opzionale | `GUIDA_COMPLETA §12` |
| **Cifratura dati a riposo** | File di log accessibili solo da utente `ats` (permessi 640) | `GUIDA_COMPLETA §4` |
| **Minimizzazione** | Solo FQDN loggato (non URL completo), HTTPS non ispezionato | `DPIA §2` |
| **Resilienza** | Health check automatico, auto-restart, systemd hardening | `GUIDA_COMPLETA §9` |
| **Audit trail** | etckeeper (versionamento configurazioni), audit.log (ogni richiesta) | `GUIDA_COMPLETA §8.4` |
| **Gestione vulnerabilità** | unattended-upgrades per OS, procedura upgrade ATS documentata, script CVE check | `GUIDA_OPERATIVA.md` |
| **Backup** | Backup configurazioni (tar + etckeeper), procedura ripristino documentata | `GUIDA_OPERATIVA §6` |
| **Cancellazione dati** | Procedura per diritto all'oblio (Art. 17 GDPR) documentata | `GUIDA_OPERATIVA §11` |
| **Incident response** | Procedura documentata con template notifica NIS2 24h/72h | `GUIDA_OPERATIVA §12` |

### Base giuridica del trattamento

| Base | Riferimento normativo |
|------|----------------------|
| Legittimo interesse del titolare (sicurezza rete) | Art. 6.1(f) GDPR |
| Obbligo di legge (conservazione dati traffico) | Art. 132 D.Lgs 196/2003 |
| Policy aziendale (URL filtering, uso accettabile) | Art. 88 GDPR, D.Lgs 196/2003 |

### Informativa

L'informativa è fornita agli interessati tramite [policy aziendale / contratto / comunicazione interna]. Template disponibile in `DPIA_v1.0.md §8`.

---

## Attività di trattamento n. 2 — Autenticazione proxy (se attiva)

| Campo (Art. 30.1) | Valore |
|-------------------|--------|
| **b) Finalità** | Autenticazione utenti per accesso a Internet tramite proxy |
| **c) Categorie interessati** | Utenti autorizzati ad accedere a Internet |
| **c) Categorie dati** | Username, password (hash in transito via Basic auth) |
| **f) Conservazione** | Credenziali nel file di configurazione. Nessun log delle password |
| **g) Misure** | File config accessibile solo da root e ats (640). Plugin in C compilato |

---

## Attività di trattamento n. 3 — Monitoring e health check

| Campo (Art. 30.1) | Valore |
|-------------------|--------|
| **b) Finalità** | Garantire la disponibilità del servizio proxy |
| **c) Categorie dati** | HTTP status code, stato servizio systemd |
| **f) Conservazione** | Log di health check: 30 giorni. Nessun dato personale |
| **g) Misure** | Script eseguito via cron, log locale |

---

## Riepilogo

| Attività | Base giuridica | Dati personali | Conservazione |
|----------|---------------|---------------|---------------|
| Logging accessi proxy | Art. 6.1(f) + Art. 132 D.Lgs 196 | IP, FQDN, timestamp | 6 mesi (+6 anni giud.) |
| Autenticazione proxy | Policy aziendale | Username | File config |
| Monitoring | Legittimo interesse | Status code | 30 giorni |

---

## Approvazioni

| Ruolo | Nome | Data | Firma |
|-------|------|------|-------|
| Titolare del trattamento | | | |
| DPO | | | |

---

*Documento da completare a cura del Titolare del trattamento. Revisione annuale raccomandata.*
