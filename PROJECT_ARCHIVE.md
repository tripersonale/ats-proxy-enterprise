# ATS Proxy Enterprise — Archivio di Progetto

## Memoria tecnica, metodologica e decisionale

**25-26 Maggio 2026**

---

## 1. Metodologia — come abbiamo lavorato

> Questi principi sono emersi durante lo sviluppo e vanno applicati a ogni progetto simile.

### Principio 1 — Test minimo, verifica, aggiungi un pezzo

Non scrivere 300 righe di plugin e sperare che funzioni. Scrivi 10 righe che bloccano TUTTO (403 su ogni richiesta). Se funziona, aggiungi il check Host. Se funziona, aggiungi l'auth. Un mattone alla volta.

**Esempio**: Il plugin v2.1 è stato costruito in 5 step incrementali:
1. Plugin che blocca tutto (403) → testato
2. Aggiunto Host check (deny list) → testato
3. Aggiunto auth (407 + Proxy-Authenticate) → testato
4. Aggiunto admin bypass → testato
5. Aggiunto config loader → testato

### Principio 2 — Se non funziona, semplifica

Dopo 5 tentativi falliti di far funzionare il plugin unificato (hook sbagliati, API deprecate, crash silenziosi), la soluzione è stata: **tornare al basic_auth.c funzionante e modificarlo una riga alla volta**, compilando e testando dopo ogni modifica. Il debug "a caccia" non funziona — il debug "per sottrazione" sì.

### Principio 3 — Mai assumere, verifica sulla VM reale

`--enable-pcre2` era scritto nella guida come opzione funzionante. **Testato sulla VM reale: non funziona**. Rimosso. `localhost bypassa le ACL` era scritto in 3 documenti. **Testato: falso quando 127.0.0.1 è in deny**. Corretto. Ogni ipotesi va verificata, anche quelle che sembrano ovvie.

### Principio 4 — Concorrenza: testare a 5, 10, 20, 50

Il plugin funzionava perfettamente con richieste seriali. A 20 concorrenti crashava. A 5 funzionava. La race condition era in `TSmalloc/TSfree` nell'example plugin. Il plugin finale usa solo stack allocation. **Mai fermarsi al test seriale.**

### Principio 5 — Il 000 di curl non è sempre un errore

`curl -sI -o /dev/null -w '%{http_code}'` può restituire `000` per vari motivi:
- `-sI` (HEAD) su alcuni endpoint è più lento
- Output mescolato con stderr
- Timeout DNS non gestito da curl
**Sempre verificare con `curl -v` prima di concludere che qualcosa non funziona.** 30 minuti persi su falsi 000.

---

## 2. Lezioni chiave — bug incontrati e soluzioni

| Bug | Sintomo | Causa | Soluzione | Tempo perso |
|-----|---------|-------|-----------|-------------|
| **AppArmor blocca PCRE** | traffic_server zombie, empty reply | Profilo AppArmor nega accesso a `/usr/local/pcre/lib/libpcre.so.1` (EACCES) | `sudo aa-remove-unknown` | ~1 ora |
| **TSMimeHdrFieldValueStringGet(NULL)** | Plugin crasha su richiesta | `value_len` passato come NULL causa segfault silenzioso | **Sempre `&vlen`**, mai NULL | ~2 ore |
| **TSHttpTxnArgSet deprecato** | Response hook non riceve azione (action=0) | API deprecata in ATS 9.2.13, TSUserArgGet restituisce 0 | Usare `TSUserArgSet/Get` con `TSUserArgIndexReserve` | ~1 ora |
| **Shell escaping** | Comandi bash con heredoc complessi si rompono | Virgolette e backslash in conflitto tra shell e Python | Usare Python injection via scp invece di heredoc inline | ~30 min |
| **Permessi config** | 403 atteso, ricevo 200 | `tee` crea file con ownership `root:root`, ATS (utente ats) non legge | `chown ats:ats` dopo ogni scrittura | ~20 min |
| **Deny non funziona** | 200 invece di 403 | allow /24 matcha prima di deny /32 nel file YAML | Ordine first-match: deny PRIMA di allow | ~15 min |

---

## 3. Cosa ha funzionato al primo colpo

| Cosa | Perché |
|------|--------|
| **ip_allow.yaml first-match** | Comportamento identico su 24.04 e 26.04, prevedibile |
| **header_rewrite URL filtering** | Ha funzionato subito in forward proxy mode con `cond %{READ_REQUEST_HDR_HOOK}` |
| **basic_auth pattern** | Il plugin di esempio compila e funziona. Pattern riutilizzabile per qualsiasi plugin che genera error responses |
| **systemd hardening** | `ProtectSystem=strict` + `RuntimeDirectory=trafficserver` ha funzionato senza rompere nulla |

---

## 4. Cosa ha richiesto debug esteso

| Cosa | Perché è stato difficile |
|------|--------------------------|
| **Plugin C unificato** | 15+ tentativi tra hook sbagliati (READ_REQUEST_HDR non genera errori), API deprecate (TSHttpTxnArgSet), bug TSMimeHdrFieldValueStringGet, AppArmor, compilazione, shell escaping. Alla fine risolto partendo da basic_auth.c funzionante e aggiungendo feature una alla volta |
| **AppArmor** | Il crash era silenzioso: traffic_server zombie, nessun log. Solo `strace` ha rivelato EACCES su libpcre.so.1 |
| **Rate limiting config** | `sed -i '/pattern/a\text'` ha inserito testo in posizione sbagliata, corrompendo records.config. Meglio `echo >>` |
| **Output parsing curl** | `-sI` vs `-s`, `-o /dev/null -w` vs `-v`, stderr mischiato con stdout. Standardizzato su `-s -o /dev/null -w '%{http_code}\n'` |

---

## 5. Decisioni architetturali

| Decisione | Motivazione |
|-----------|------------|
| **OS_DNS hook, non READ_REQUEST_HDR** | READ_REQUEST_HDR non può generare error responses (403/407). OS_DNS sì. Trade-off: DNS cache gap |
| **Plugin singolo, non 2-plugin stack** | Il doppio plugin (header_rewrite + basic_auth) funziona ma richiede 2 file di config e 2 hook diversi. Il plugin singolo è più manutenibile |
| **Self-signed TLS** | Per lab/testing. Sostituibile con certificato aziendale copiando i file in `/etc/trafficserver/certs/` |
| **Hardcoded → Config file** | v2.0: deny/whitelist/user hardcoded in C. v2.1: tutto da `ats_proxy_filter.conf` editabile senza ricompilare |
| **No AppArmor in produzione** | Il profilo creato bloccava PCRE. Richiede tuning manuale con `aa-logprof`. Documentato come "da attivare dopo tuning" |

---

## 6. Frammenti chiave dalla chat

> "Test minimo, verifica, aggiungi un pezzo — un mattone alla volta con solo cose certe e già verificate"
> — Principio fondante ripetuto più volte

> "Se non funziona, semplifica fino al test più piccolo possibile"
> — Dopo 5 crash del plugin, la svolta è stata `pkill + restart + curl`

> "Mai assumere: verifica ogni ipotesi sulla VM reale"
> — `--enable-pcre2` documentato ma non funzionante. "localhost bypassa ACL" falso

> "Il 000 di curl non è sempre un errore: a volte è -sI che mente"
> — 30 minuti di debug su un problema di output parsing

> "Non ti ho detto di inventare un modo nuovo di farlo, hai controllato i tuoi file prima?"
> — Lezione sul riutilizzo di pattern già verificati invece di reinventare

> "C'è bisogno di una modifica strutturale" e "rende le skill visibili sempre in tutti i progetti"
> — Lezione sull'importanza di rendere la conoscenza accessibile e riutilizzabile

---

*Archivio creato il 26 Maggio 2026 — basato sull'intero ciclo di sviluppo del progetto ATS Proxy Enterprise*
