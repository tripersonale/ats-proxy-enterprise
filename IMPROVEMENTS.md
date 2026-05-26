# Improvements Log - ATS Proxy Enterprise

## Uso

Questo file raccoglie problemi, proposte e miglioramenti non ancora lavorati.
Serve a mantenere contesto minimo sufficiente per riprendere il lavoro in una sessione futura senza dipendere dalla memoria della chat.

Regole operative:
- Usare questo file quando l'utente chiede di segnare un problema, una soluzione proposta, un miglioramento o un appunto da elaborare dopo.
- Non usare questo file come stato corrente del progetto: quello resta in `STATE_CARD.md`.
- Quando una voce diventa azione confermata, aggiornare anche `STATE_CARD.md`.
- Quando una voce diventa decisione stabile o principio di progetto, sintetizzarla in `PROJECT_ARCHIVE.md`.
- Ogni voce deve contenere problema, soluzione proposta e contesto minimo necessario.

## Aperte

### IMP-0002 - Metodo scientifico per ogni comando e percorso operativo

- Stato: in corso
- Priorita: alta
- Data: 2026-05-25
- Problema:
  Il progetto richiede guide e script utilizzabili senza perimetro di errore. Ogni comando documentato e ogni percorso alternativo devono essere testati o marcati esplicitamente come non ancora validati.
- Soluzione proposta:
  Per ogni script aggiungere test locali non distruttivi, validazione sintassi, percorsi di errore attesi e matrice di test. Le guide devono distinguere tra "verificato localmente", "verificato su VM reale" e "da validare".
- Contesto minimo:
  L'utente deve poter scaricare file da repo privata, copiarli su VM Ubuntu 24.04 o 26.04 e avviare il deploy senza dipendere dalla chat. Il principio e debole se resta implicito: deve essere documentato e usato come gate prima di dichiarare un comando affidabile.
- File coinvolti:
  `scripts/*.sh`, `README.md`, `GUIDA_REPLICABILITA_DEPLOY_v1.0.md`, nuova guida trasferimento VM.
- Criterio di completamento:
  Ogni comando pubblicato nella guida ha stato di test dichiarato; i comandi non eseguibili localmente sono marcati come da validare su VM reale; nessuna procedura viene dichiarata completa senza evidenza di test.
- Avanzamento:
  Aggiunto `--validate-only` all'installer e documentata matrice test in `GUIDA_TRASFERIMENTO_VM_v1.0.md` e `GUIDA_REPLICABILITA_DEPLOY_v1.0.md`.

### IMP-0001 - Replicabilita configurazione ambiente

- Stato: in corso
- Priorita: alta
- Data: 2026-05-25
- Problema:
  Valori necessari al deploy e alla riproduzione dell'ambiente sono sparsi tra script, documenti, memoria di sessione e file temporanei. Questo rende difficile ricostruire una VM o un deploy senza contesto implicito.
- Soluzione proposta:
  Introdurre un contratto `.env.example`, separare configurazione pubblica e segreti, rendere persistenti le chiavi SSH in `~/CULLA-instance/01_SECRETS/ssh/`, aggiungere un preflight che validi variabili, chiavi e artefatti senza stampare segreti.
- Contesto minimo:
  La VM134 era documentata con chiave `/tmp/vm-134-key`, ma il file non esiste piu. Alcuni default sono hardcoded negli script. I principi CULLA prevedono repo pubblicabile senza segreti e istanza privata con `.env`/segreti.
- File coinvolti:
  `scripts/install-ats-proxy.sh`, `scripts/ats-proxy.conf.example`, `STATE_CARD.md`, `~/CULLA/INFRA.md`, `~/CULLA/.opencode/rules/04-infra.md`.
- Criterio di completamento:
  Un deploy ATS deve essere ricostruibile da repo + `.env` privata + `01_SECRETS`, senza memoria della chat e senza file temporanei come fonte operativa.
- Avanzamento:
  Creati `env/ats-proxy.env.example`, `env/proxmox.env.example`, `.gitignore`, `scripts/preflight.sh` e `GUIDA_REPLICABILITA_DEPLOY_v1.0.md`. Aggiornato installer per validare configurazione e plugin prima dell'installazione.
  Recuperato e versionato il binario plugin `bin/ats_proxy_filter_v21.so` dai dischi VM130/VM134.
  Ricostruito e versionato il sorgente C `src/ats_proxy_filter_v21.c` il 2026-05-25.
  Resta da compilare e validare il sorgente ricostruito su VM reale e completare test end-to-end dell'installer.

## Completate

### IMP-0003 - Recupero sorgente C plugin v2.1

- Data completamento: 2026-05-25
- Azione: Sorgente ricostruito da comportamento documentato e ATS basic_auth.c base.
- File creato: `src/ats_proxy_filter_v21.c` (334 righe, SHA256: 35c2a1e4c6...).
- Da validare compilazione su VM con ATS 9.2.13 e equivalenza funzionale col binario recuperato.
