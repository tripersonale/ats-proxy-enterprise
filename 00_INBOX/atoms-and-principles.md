# ATS Proxy Enterprise — Atomic Design & Principles

## Contesto

Questo documento nasce dall'esperienza reale del 2026-05-26: un utente non tecnico
ha provato a usare la repo e ha incontrato attriti a ogni livello. Non e un fallimento
del codice, ma un fallimento di design dell'esperienza.

## Problemi Incontrati

1.  **Repo privata non accessibile** — primo comando `git clone`, fallito subito.
    Manca un percorso offline primario (tarball + scp).
2.  **Script opaco** — `install-ats-proxy.sh` ha 724 righe, 15 flag, due modalita.
    L'utente non sa cosa fa ne come si usa.
3.  **Campi obbligatori senza auto-detect** — chiede IP, gateway, DNS anche se la VM
    li ha gia. L'utente non li sa.
4.  **Warning confusivi durante install** — messaggi tecnici sul DNS cache gap
    appaiono prima che il proxy funzioni. Rumore.
5.  **Auth forzata dopo plugin** — impossibile testare il proxy base senza
    configurare utenti e whitelist.
6.  **Gestione filter file scomoda** — editare file a mano, chown, chmod, restart.
    Un'operazione semplice richiede 5 comandi.

## Principio Fondamentale

> **Ogni pezzo deve funzionare da solo, prima di funzionare assieme.**

## Architettura A Strati (Mattoncini)

```
Livello 0 — ATS Core (proxy puro, nessun plugin, nessuna auth)
  Script:    install-ats-core.sh       (~80 righe)
  Guida:     GUIDA_ATS_CORE.md         (~2 pagine)
  Test:      test-ats-core.sh          (porta aperta? proxy funziona?)

Livello 1 — Plugin Filtering (DENY + WHITELIST, auth DISABILITATA)
  Script:    install-ats-plugin.sh     (~50 righe)
  Guida:     GUIDA_PLUGIN_BASE.md      (~2 pagine)
  Test:      test-ats-plugin-base.sh   (DENY 403? WHITELIST passa?)

Livello 2 — Auth (USER, ADMIN, auth ABILITATA)
  Script:    enable-ats-auth.sh        (~40 righe)
  Guida:     GUIDA_AUTH.md             (~2 pagine)
  Test:      test-ats-auth.sh          (407 senza? 301 con?)

Livello 3 — Hardening (UFW, fail2ban, systemd, etc.)
  Script:    apply-ats-hardening.sh    (esistente, gia modulare)
  Guida:     GUIDA_HARDENING.md        (esistente)
  Test:      ats-hardening-check.sh    (esistente, 25/25)

Livello 4 — Tooling CLI
  Script:    ats-ctl                   (nuovo, Bash o Go)
  Guida:     GUIDA_ATS_CTL.md
  Comandi:   ats-ctl deny add <domain>
             ats-ctl deny remove <domain>
             ats-ctl whitelist add <domain>
             ats-ctl user add <name> <pass>
             ats-ctl admin add <ip>
             ats-ctl status
             ats-ctl test
```

## Proprieta Di Ogni Livello

- **Indipendente**: puo essere installato da solo.
- **Ordinabile**: l'ordine e libero (tranne dipendenze ovvie).
- **Testabile**: ogni livello ha un test di verifica.
- **Idempotente**: se eseguito due volte, non rompe.
- **Offline-first**: il percorso primario e tarball, non git clone.

## Regole Di Design Per Ogni Script

Prima di scrivere output operativo, verificare mentalmente:

1. Chi usera questo?
2. Cosa sa gia?
3. Cosa ha a disposizione (internet? IP? chiavi?)?
4. Qual e il primo comando che digitera?
5. Se quel comando fallisce, cosa vede?
6. C'e un percorso offline?
7. C'e un test che conferma il successo?

## Checklist Anti-Attrito

- [ ] Il primo comando funziona senza internet? (tarball > git clone)
- [ ] I valori di default vengono auto-rilevati dal sistema? (ip, hostname, dns)
- [ ] I warning tecnici sono post-install, non durante?
- [ ] L'auth e disabilitata di default dopo install plugin?
- [ ] Esiste un tool CLI per gestire la config senza editare file a mano?
- [ ] Ogni script ha un --help chiaro con esempio?
- [ ] Ogni script ha un test di verifica dedicato?
- [ ] Il fallimento e diagnostico ("manca X in Y"), non misterioso?

## Cosa Abbiamo Gia

| Cosa | Stato |
|---|---|
| ATS core compilation | Funziona, va estratto dall'installer monolite |
| Plugin v21 (stabile) | Funziona su ATS 9.2.13 |
| Plugin v22 (beta, duale) | Compila e test base OK su ATS 9 e ATS 10 |
| Regression test | 9/9 script pronto |
| Hardening test | 25/25 script pronto |
| Package release | Script pronto |
| Preflight | Script pronto |
| Check consistency | Script pronto |

## Cosa Manca

| Cosa | Priorita |
|---|---|
| Stratificare installer in script atomici | Alta |
| Aggiungere auto-detect per IP/DNS/hostname | Alta |
| Disabilitare auth di default nel plugin | Alta |
| Creare `ats-ctl` CLI | Media |
| Percorso offline primario in README | Alta |
| Guide atomiche per ogni livello | Media |
| Test concorrenti e hardening su ATS 10 | Media |

## ATS 10 — Stato Plugin v22 Beta

- Compila con `g++ -std=c++17` contro header ATS 10.1.2 generati da CMake.
- Carica senza `undefined symbol`.
- Test funzionali base passati: DENY, WHITELIST, AUTH missing/valid/wrong.
- **Non ancora testato**: concorrenti, hardening, admin bypass, DNS cache.
- ATS 10 richiede `records.yaml` (non `records.config`).
- ATS 10 richiede CMake (non autotools).
- Il plugin v22 usa `TSConfigDirGet()` per il path config, portabile tra versioni.

## Principi Culla / Anima / Core

- **Culla** (infrastruttura): Proxmox, cloud-init, deploy VM atomico.
- **Anima** (AI tooling): Skill ATS come agenti con contesto, non copia-incolla.
  Ogni skill deve includere: scenario utente, failure mode, alternative offline.
- **Core** (applicazioni): emerge quando Culla e Anima sono solide.

## File Di Regole

Questo documento dovrebbe essere referenziato da una regola in
`.opencode/rules/05-design.md` che impone la checklist anti-attrito
prima di ogni task operativo.

---

Scritto il 2026-05-26, dopo test reale con utente non tecnico.
Basato su esperienza diretta, non su teoria.
