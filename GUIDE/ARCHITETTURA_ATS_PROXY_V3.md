# ATS Proxy Enterprise v3.0 - Architettura Validata

## Scopo

Questa architettura nasce dal test reale del 2026-05-26: il problema non era solo tecnico, era esperienza d'uso. Il proxy deve essere installabile, verificabile e spiegabile per strati.

## Principio guida

> Ogni pezzo deve funzionare da solo prima di funzionare insieme.

## Livelli

| Livello | Responsabilita | Stato |
|---|---|---|
| L0 ATS Core | ATS 10.1.2 LTS come forward proxy puro | Da validare su VM Ubuntu 26.04 |
| L1 Plugin Filter | Plugin unico v3.0, spegnibile, deny/whitelist | Sorgente pronto |
| L2 Auth | Basic Auth con password hashate, gestita da `ats-ctl` | Sorgente/tooling pronto |
| L3 Hardening | systemd, firewall, fail2ban, update, audit | Modello esistente 25/25, da riapplicare |
| L4 Operativita | `ats-ctl`, report, test mode | Base pronta |

## Plugin unico, modi multipli

| MODE | Comportamento |
|---|---|
| `off` | Plugin caricato ma trasparente: tutto passa. |
| `deny` | Deny list attiva, tutto il resto passa senza auth. |
| `whitelist` | Solo whitelist passa, il resto riceve 403. |
| `auth_all` | Auth richiesta per tutto; utente valido sovrasta deny/whitelist. |
| `auth_nd` | Deny blocca sempre; whitelist passa senza auth; il resto richiede auth. |

## Ordine decisionale

1. `ADMIN` passa sempre.
2. `MODE off` passa tutto.
3. `MODE deny`: `DENY` blocca, resto passa.
4. `MODE whitelist`: `WHITELIST` passa, resto 403.
5. `MODE auth_all`: auth valida passa tutto, auth assente/errata 407.
6. `MODE auth_nd`: deny blocca, whitelist passa, resto richiede auth.

## Configurazione target

```text
/etc/ats-proxy/
├── filter.conf
├── deny.list
├── whitelist.list
├── admin.list
└── auth.conf
```

I file example sono in `config/`. L'operatore non deve editare a mano per l'uso ordinario: usa `scripts/ats-ctl`.

## Sicurezza auth

La v2.x salvava password in chiaro. La v3.0 salva `salt$sha256(salt+password)` e confronta hash con funzione a tempo costante. Il canale HTTP Basic resta da proteggere con TLS o rete fidata: hashing protegge il dato a riposo, non il transito.

## Credenziali create in fase VM

Le credenziali operative create da CULLA vanno tracciate come path e ruolo, non come valore in chiaro:

- SSH key privata: `~/CULLA-instance/01_SECRETS/ssh/<vm>.key`
- Utente cloud-init: registrato in STATE_CARD o session log
- Password Basic Auth: generata/migrata con `ats-ctl user add`; mai scritta in documenti o log

## Stato rispetto all'enterprise

Appropriato per beta enterprise interna quando:

- build plugin e test mode passano su VM ATS 10;
- hardening check passa;
- password non sono in chiaro;
- file config hanno permessi `0640 root:trafficserver`;
- rollback e upgrade sono documentati.

Per produzione larga servono ancora: LDAP/OIDC o PAM, reload config senza restart, load test oltre 50 concorrenti, vulnerability assessment indipendente.
