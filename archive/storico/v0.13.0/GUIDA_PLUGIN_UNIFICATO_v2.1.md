# ATS Proxy Enterprise - Plugin Unificato v2.1

Documento corrente, ricreato in root per non perdere il dettaglio operativo storico.  
Baseline validata: commit `90eb329`, versione `0.13.0`, ATS 9.2.13, VM135 Ubuntu 24.04.4 e VM136 Ubuntu 26.04.

## Risposta Alla Domanda Chiave

I 4 livelli non sono stati persi. Il comportamento validato e:

| Livello | Dove vive | Stato |
|---------|-----------|-------|
| ACL rete ATS | `/etc/trafficserver/ip_allow.yaml` | Validato come parte installer/hardening |
| URL filtering | `DENY` / `WHITELIST` in `/etc/trafficserver/ats_proxy_filter.conf` | Validato con `httpbin.org` e `google.com` |
| Auth da file | `USER user password` in `/etc/trafficserver/ats_proxy_filter.conf` | Validato con auth mancante, valida e errata |
| Admin bypass IP | `ADMIN ip` in `/etc/trafficserver/ats_proxy_filter.conf` | Implementato nel sorgente; da testare esplicitamente da IP remoto admin in una prossima batteria |

In piu l'installer applica UFW e fail2ban, quindi i layer effettivi sono piu di quattro.

## Stato DNS Cache Gap

Il plugin corrente usa `TS_HTTP_OS_DNS_HOOK`, come si vede in `src/ats_proxy_filter_v21.c`. Questo hook puo non scattare quando ATS ha gia in cache la risoluzione DNS del dominio.

Conclusione corretta:

- Il DNS cache gap **non va dichiarato risolto universalmente** nella baseline 0.13.0 senza una batteria piu lunga e dedicata.
- La vecchia guida v2.0 lo indicava come risolvibile con `READ_REQUEST_HDR`; quella era una direzione/proposta, non la baseline finale verificata.
- La vecchia guida v2.1 storica gia documentava il limite: `OS_DNS hook`, gap DNS cache documentato.
- Test rapidi del 2026-05-26 su VM135/VM136 **non hanno riprodotto il bypass**: dopo una richiesta autenticata a `reddit.com`, richieste successive senza auth restano `407`; cinque richieste consecutive a `google.com` producono cinque log `WHITELIST`.
- Il vecchio plugin recuperato SHA `6a1a73...` e stato testato temporaneamente su VM135 e non ha mostrato un comportamento migliore: auth valida `301`, poi no-auth `407`.
- Per chiuderlo definitivamente serve una batteria lunga con hostdb/TTL, HTTP e CONNECT, e possibilmente confronto hook alternativo.

## File Config

Percorso:

```text
/etc/trafficserver/ats_proxy_filter.conf
```

Esempio:

```conf
ADMIN 192.168.89.10
ADMIN 192.168.89.27

DENY httpbin.org
DENY bad.com
DENY malware.net

WHITELIST google.com
WHITELIST github.com
WHITELIST ubuntu.com
WHITELIST example.com

USER admin password-forte
USER user1 password-forte-2
USER operator password-forte-3
```

Nota pattern: nella baseline 0.13.0 sono validati match esatti di host. Non dichiarare regex completa o suffissi wildcard come supportati finche non viene aggiunta una batteria test dedicata.

## Ordine Decisionale

```text
Richiesta -> OS_DNS hook
  -> client IP in ADMIN? continue
  -> Host in DENY? 403 Forbidden
  -> Host in WHITELIST? continue
  -> Proxy-Authorization valida? continue
  -> altrimenti 407 Proxy Authentication Required
```

Dettagli validati:

- `DENY httpbin.org` restituisce `403 Forbidden`.
- `WHITELIST google.com` passa e restituisce `301` nei test reali.
- dominio non whitelist senza credenziali restituisce `407`.
- header `Proxy-Authenticate: Basic realm="ATS Proxy"` presente.
- credenziali valide da file permettono il passaggio.
- credenziali errate restituiscono `407`.

## Deploy Plugin

Path corretto validato:

```bash
sudo install -o ats -g ats -m 755 bin/ats_proxy_filter_v21.so /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo tee /etc/trafficserver/plugin.config >/dev/null <<'EOF'
ats_proxy_filter.so
EOF
sudo chown ats:ats /etc/trafficserver/plugin.config /etc/trafficserver/ats_proxy_filter.conf
sudo chmod 640 /etc/trafficserver/plugin.config /etc/trafficserver/ats_proxy_filter.conf
sudo systemctl restart trafficserver
```

Path storico non corretto per questa build:

```text
/opt/trafficserver/lib/modules/ats_proxy_filter.so
```

ATS 9.2.13 testato cerca il plugin in `/opt/trafficserver/libexec/trafficserver/` quando `plugin.config` contiene solo `ats_proxy_filter.so`.

## Test

```bash
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

Esito validato su VM135 e VM136:

```text
Passed: 9  Failed: 0
```

Test admin bypass da fare esplicitamente da un IP presente in `ADMIN`, non da localhost se localhost non e nella lista admin. Questo e un test residuo puntuale, non una perdita di feature: il codice implementa `ip_is_admin()` prima di DENY/WHITELIST/AUTH.

## Sorgente

File:

```text
src/ats_proxy_filter_v21.c
```

Hash:

```text
SHA256 ac742e549c3081af44c320117ce0a8a1e8d9b80dbb76327f154e7d0797a7ffea
```

Binario:

```text
bin/ats_proxy_filter_v21.so
SHA256 26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674
```

## Cosa Serve Per Risolvere Davvero Il DNS Cache Gap

Opzione di sviluppo da testare:

- spostare la decisione policy su un hook che scatta sempre per richiesta, per esempio request header/pre-remap;
- mantenere la capacita di generare `403` e `407` con reason/header corretti;
- validare HTTP e CONNECT;
- ripetere regression 9/9 e test cache DNS specifico;
- aggiornare `TEST_MATRIX.md` solo dopo esito reale.

Finche questo non viene fatto, il gap resta documentato e non va venduto come chiuso.
