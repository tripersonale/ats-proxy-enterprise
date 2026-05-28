# Plugin ATS Proxy Enterprise - Affidabilita e Limiti

## Origine

Il plugin v2.1 e stato ricostruito da comportamento documentato, archivio progetto e reference ATS `basic_auth.c`. Il v3.0 mantiene la logica stabile ma cambia architettura operativa: plugin unico, modalita esplicite, file separati, password hashate.

## Cosa fa bene

- Decisione locale e veloce su host richiesto.
- Nessuna allocazione dinamica nel path caldo.
- Liste statiche con limiti espliciti.
- Hook singolo `TS_HTTP_OS_DNS_HOOK` piu response hook solo quando serve errore.
- Configurazione leggibile e testabile per modo.

## Cosa non promette

- Non e un WAF.
- Non ispeziona contenuto TLS end-to-end.
- Non sostituisce LDAP/OIDC/PAM enterprise.
- Non evita il bisogno di TLS o rete fidata per Basic Auth.
- Non ha ancora reload config senza restart.

## Requisiti per considerarlo beta enterprise

- Runtime test su ATS 10.1.2 e Ubuntu 26.04.
- Test `off`, `deny`, `whitelist`, `auth_all`, `auth_nd` passati.
- Hardening check passato.
- Password solo hashate in `auth.conf`.
- Hash `.so` registrato in `ARTIFACTS.md`.

## Roadmap produzione

1. Reload config senza restart.
2. Backend auth esterno opzionale.
3. Test C unitari per matcher/hash/parser.
4. Load test >50 concorrenti.
5. Penetration test indipendente.
