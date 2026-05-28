# ATS Proxy Enterprise v3.0 — Presentazione Prodotto

> **Powered by Apache Traffic Server** — ATS Proxy Enterprise è un prodotto
> indipendente costruito su Apache Traffic Server (Apache 2.0). Il plugin,
> gli script e la documentazione sono codice originale sotto licenza FEL-1.0.
> "Apache", "Apache Traffic Server" e il logo Apache feather sono marchi
> registrati di The Apache Software Foundation. Vedi [THIRD_PARTY.md](THIRD_PARTY.md).

## Cos'e

ATS Proxy Enterprise e un **forward proxy HTTP/HTTPS con URL filtering,
autenticazione e hardening** basato su Apache Traffic Server. E pensato per
aziende che devono governare l'accesso a Internet dai propri uffici, con
requisiti di sicurezza e compliance verificabili.

Non e un "pacchetto di regole" da applicare a un proxy generico. E un **prodotto
integrato**: ATS + plugin di filtering + tool di gestione + hardening + test.

## A chi serve

| Profilo | Cosa ci fa |
|---|---|
| **PMI / SMB** | Controlla la navigazione dei dipendenti, blocca siti malevoli, registra accessi per compliance. |
| **Reparto IT interno** | Proxy autenticato con policy separabili (blocco, whitelist, auth). |
| **MSP / System integrator** | Installazione ripetibile via script, test automatici, hardening verificabile. |
| **Revisori / DPO** | DPIA, registro trattamenti, retention policy gia documentati e mappati su GDPR/NIS2. |

## Cosa fa

| Funzione | Dettaglio |
|---|---|
| **Forward proxy** | I client configurano il proxy nelle impostazioni di rete. ATS inoltra le richieste. |
| **URL filtering** | 5 modalita: off, solo deny, solo whitelist, auth totale, auth con deny prioritario. |
| **Autenticazione** | HTTP Basic Auth con password hashate (`salt$sha256`). IP admin bypassano tutto. |
| **Hardening** | systemd sandbox, UFW, fail2ban, unattended-upgrades, etckeeper. Verificabile con 25 check automatici. |
| **Compliance** | GDPR (registro trattamenti, DPIA, retention, diritto accesso/cancellazione), NIS2, ISO 27001. |
| **Test automatici** | Regressione 9 test, hardening 25 check, test per ogni mode del plugin. |

## Architettura a strati

```
Livello 0 — ATS Core        Proxy puro, nessun plugin, nessuna auth.
Livello 1 — Plugin Filter   URL deny e whitelist. Auth disabilitata.
Livello 2 — Auth            Basic Auth con hash. 5 modalita selezionabili.
Livello 3 — Hardening       systemd, firewall, fail2ban, audit, CVE check.
Livello 4 — Operativita     CLI (ats-ctl), test, report.
```

Ogni livello e **indipendente**: puoi fermarti al livello che ti serve.

## Modalita del plugin in 30 secondi

| MODE | Comportamento | Quando usarlo |
|---|---|---|
| `off` | Il plugin non filtra nulla. | Debug, manutenzione. |
| `deny` | Blocca i domini in lista nera. | Bloccare malware, social, siti non professionali. |
| `whitelist` | Solo i domini in lista bianca passano. | Accesso strettissimo (es. chiosco, postazione pubblica). |
| `auth_all` | Serve autenticazione per tutto. | Proxy solo per personale autorizzato. |
| `auth_nd` | Deny blocca sempre, whitelist passa, il resto chiede auth. | **Consigliato**: massimo controllo con minima frizione. |

## Cosa lo rende enterprise

- **Password non in chiaro** nei file di configurazione.
- **Hardening verificabile**: 25 check automatici, non "dovrebbe essere ok".
- **Configurazione separata**: deny, whitelist, admin, auth in file diversi.
- **Tool CLI dedicato**: `ats-ctl` per gestire tutto senza editare file a mano.
- **Test automatici**: ogni mode ha test curl con output atteso.
- **Documentazione normativa**: DPIA, registro trattamenti Art.30, incident response GDPR/NIS2.

## Differenza rispetto ad alternative

| Cosa | ATS Proxy Enterprise | Squid | Soluzione firewall UTM |
|---|---|---|---|
| Proxy forward | Si | Si | Spesso solo filtering, non proxy |
| URL filtering a modi | 5 modi selezionabili | Via ACL complesse | Solo deny/allow |
| Hardening verificabile | 25 check automatici | Manuale | Opaco |
| Config separata per ruolo | deny.list, whitelist.list, auth.conf | Singolo file monolitico | GUI proprietaria |
| Gestione utenti | CLI con hash automatico | htpasswd manuale | Interfaccia web |
| Test automatici | curl-based per ogni mode | Non forniti | Non forniti |
| Compliance documentata | GDPR/NIS2/ISO 27001 | Da scrivere | Da acquistare |
| Open source | Si (Fair Enterprise License) | Si (GPL) | No |

## Come iniziare in 5 minuti

1. **Leggi** `GUIDA_INSTALLAZIONE_ATS_LTS.md` — installazione passo-passo.
2. **Installa** ATS + plugin + hardening con copia-incolla (~30 min).
3. **Configura** la policy con `sudo ats-ctl mode auth_nd`.
4. **Aggiungi** i domini da bloccare: `sudo ats-ctl deny add facebook.com`.
5. **Crea** gli utenti: `sudo ats-ctl user add mario.rossi`.
6. **Verifica**: hardening deve dare 25/25.

## Cosa serve per usarlo

- Una VM o server con **Ubuntu 26.04 LTS** (o 24.04).
- Minimo **4 GB RAM**, **20 GB disco**.
- **Rete interna** con subnet nota (es. `192.168.0.0/24`).
- I client devono configurare il proxy nelle impostazioni di sistema.

## Roadmap

| Cosa | Stato |
|---|---|
| Forward proxy ATS 10.1.2 LTS | Testato su VM |
| Plugin a 5 modi con password hashate | Testato su VM |
| Hardening 25/25 verificabile | Testato su VM |
| CLI `ats-ctl` | Funzionante |
| TLS frontend | Da testare |
| Reload config senza restart | In backlog |
| LDAP/OIDC | In backlog |
| Penetration test | In backlog |
