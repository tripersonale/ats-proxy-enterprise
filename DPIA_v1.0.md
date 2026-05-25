# ATS Proxy Enterprise — DPIA (Data Protection Impact Assessment)

## Valutazione d'Impatto sulla Protezione dei Dati — GDPR Art. 35

**Versione 1.0 — 25 Maggio 2026**
**Da compilare a cura del Titolare del trattamento**

---

## 1. Titolare del trattamento

| Campo | Valore |
|-------|--------|
| **Denominazione** | [Nome Organizzazione] |
| **Indirizzo** | [Indirizzo sede legale] |
| **Referente** | [Nome, email, telefono] |
| **DPO** | [Nome DPO, contatti] |
| **Settore** | [Pubblico / Privato / Infrastrutture] |

---

## 2. Descrizione del trattamento

Il trattamento consiste nella **registrazione dei metadati di navigazione web** degli utenti che accedono a Internet tramite il proxy aziendale ATS (Apache Traffic Server).

**Cosa viene registrato:**
- Indirizzo IP del dispositivo client
- FQDN (nome host) dei siti web visitati — **non l'URL completo**
- Data e ora della richiesta
- Metodo HTTP (GET, POST, CONNECT)
- Status code della risposta
- Byte trasferiti

**Cosa NON viene registrato:**
- URL completi (es. `/pagina?param=valore` non è loggato)
- Contenuto delle pagine visitate
- Dati trasmessi in tunnel HTTPS (cifrati end-to-end)
- Cookie, header Authorization, dati di form

**Volume stimato:** ~10-50 GB di log al mese, in funzione del numero di utenti.

**Automazione:** Il trattamento è completamente automatizzato. I log vengono scritti su disco, ruotati ogni 24 ore, e cancellati automaticamente al raggiungimento di 10 GB totali.

---

## 3. Categorie di dati personali

| Dato | Categoria | Base giuridica |
|------|-----------|---------------|
| **Indirizzo IP** | Dato personale (Art. 4.1 GDPR, C-582/14 Breyer) | Legittimo interesse — sicurezza rete |
| **FQDN visitati** | Dato di traffico telematico (Art. 132 D.Lgs 196/2003) | Obbligo di legge — accertamento reati |
| **Timestamp** | Dato di traffico | Come sopra |
| **Username proxy** (se autenticato) | Dato personale | Esecuzione contratto / policy aziendale |

I dati **non** rientrano nelle categorie particolari di cui all'Art. 9 GDPR (dati sensibili).

---

## 4. Base giuridica del trattamento

| Base | Riferimento | Motivazione |
|------|------------|-------------|
| **Legittimo interesse** | Art. 6.1(f) GDPR | Garantire la sicurezza della rete aziendale, prevenire abusi, monitorare minacce |
| **Obbligo di legge** | Art. 132 D.Lgs 196/2003 | Conservazione dati di traffico telematico per finalità di accertamento e repressione dei reati (6 anni su richiesta dell'autorità giudiziaria) |
| **Esecuzione policy aziendale** | Art. 88 GDPR + D.Lgs 196 | Trattamento dati in ambito lavorativo, previa informativa ai dipendenti |

---

## 5. Necessità e proporzionalità

**Perché è necessario:** Senza logging degli accessi, l'organizzazione non può:
- Rilevare e rispondere a incidenti di sicurezza (NIS2 Art. 21)
- Dimostrare conformità normativa (accountability GDPR)
- Ottemperare agli obblighi di conservazione (Art. 132 D.Lgs 196)
- Applicare policy di URL filtering (blocco siti malevoli)

**Perché è proporzionato:**
- Si logga solo il FQDN, non l'URL completo → minimizzazione
- I tunnel HTTPS non vengono ispezionati → riservatezza dei contenuti
- I log vengono automaticamente cancellati dopo il limite di spazio → limitazione conservazione
- L'accesso ai log è ristretto al personale IT autorizzato → controllo accessi

---

## 6. Valutazione dei rischi

### Rischio 1 — Accesso non autorizzato ai log

| Elemento | Valutazione |
|----------|------------|
| **Probabilità** | Bassa |
| **Impatto** | Alto (esposizione cronologia navigazione utenti) |
| **Mitigazioni** | File di log con permessi 640 (`ats:ats`), accesso SSH solo via chiave, fail2ban attivo, audit trail via etckeeper |
| **Rischio residuo** | Basso |

### Rischio 2 — Violazione dati personali (data breach)

| Elemento | Valutazione |
|----------|------------|
| **Probabilità** | Molto bassa |
| **Impatto** | Alto |
| **Mitigazioni** | UFW firewall (default deny), sistema su rete interna, TLS frontend opzionale, systemd hardening (ProtectSystem=strict, NoNewPrivileges) |
| **Rischio residuo** | Basso |

### Rischio 3 — Uso improprio dei dati di navigazione

| Elemento | Valutazione |
|----------|------------|
| **Probabilità** | Bassa |
| **Impatto** | Medio |
| **Mitigazioni** | Accesso ai log limitato a personale autorizzato, segregazione ruoli (admin vs auditor), policy aziendale |
| **Rischio residuo** | Basso |

### Rischio 4 — Conservazione oltre il necessario

| Elemento | Valutazione |
|----------|------------|
| **Probabilità** | Molto bassa |
| **Impatto** | Basso |
| **Mitigazioni** | Log rotation automatica ogni 24h, auto-delete a 10 GB totali, retention policy documentata |
| **Rischio residuo** | Molto basso |

---

## 7. Misure tecniche e organizzative

| Misura | Implementazione |
|--------|----------------|
| **Minimizzazione** | Solo FQDN, non URL completo. HTTPS non ispezionato |
| **Pseudonimizzazione** | Possibile anonimizzazione IP via hash nei log (non attiva di default) |
| **Cifratura** | Log su disco accessibili solo da `ats:ats`. Traffico amministrativo via SSH cifrato |
| **Controllo accessi** | SSH key-only, utenti dedicati, sudo limitato |
| **Audit trail** | etckeeper versiona ogni modifica di configurazione |
| **Resilienza** | Health check automatico, auto-restart, backup configurazioni |
| **Aggiornamenti** | unattended-upgrades per OS, procedura documentata per ATS |
| **Cancellazione** | Procedura documentata per diritto all'oblio (Art. 17 GDPR) in GUIDA_OPERATIVA |

---

## 8. Informativa agli interessati

**Template** (da personalizzare e distribuire):

> *L'accesso a Internet tramite la rete aziendale è soggetto a registrazione per finalità di sicurezza informatica e ottemperanza agli obblighi di legge (Art. 132 D.Lgs 196/2003).*
>
> *Vengono raccolti: indirizzo IP del dispositivo, nome host dei siti visitati (non l'URL completo), data e ora della richiesta.*
>
> *I dati sono conservati per 6 mesi e accessibili esclusivamente al personale IT autorizzato. Per esercitare i diritti di cui agli Art. 15-22 del GDPR, contattare il DPO all'indirizzo [email].*

---

## 9. Conclusione

Il trattamento dei dati di navigazione tramite il proxy ATS Enterprise:

- **È necessario** per garantire la sicurezza della rete e ottemperare agli obblighi di legge
- **È proporzionato** grazie alle misure di minimizzazione e alle protezioni tecniche implementate
- **Presenta un rischio residuo complessivamente basso** per i diritti e le libertà degli interessati

Non si ritiene necessaria la consultazione preventiva dell'autorità di controllo (Art. 36 GDPR), in quanto il rischio residuo non è elevato.

---

## 10. Approvazioni

| Ruolo | Nome | Data | Firma |
|-------|------|------|-------|
| Titolare del trattamento | | | |
| DPO | | | |
| Responsabile IT | | | |

---

*Documento da completare a cura del Titolare del trattamento. Revisione annuale raccomandata.*
