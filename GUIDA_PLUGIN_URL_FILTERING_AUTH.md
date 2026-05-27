# Guida Plugin URL Filtering e Auth v3.0

## Obiettivo

Il plugin v3.0 aggiunge policy URL filtering e autenticazione Basic a un forward proxy ATS, con configurazione leggibile e separata per responsabilita.

## Installazione configurazione

```bash
sudo scripts/ats-ctl init
sudo scripts/ats-ctl mode auth_nd
sudo scripts/ats-ctl deny add bad.example
sudo scripts/ats-ctl whitelist add ubuntu.com
sudo scripts/ats-ctl admin add 192.168.89.10
sudo scripts/ats-ctl user add admin
sudo scripts/ats-ctl reload
```

## File usati

| File | Contenuto |
|---|---|
| `/etc/ats-proxy/filter.conf` | MODE e INCLUDE |
| `/etc/ats-proxy/deny.list` | Domini bloccati |
| `/etc/ats-proxy/whitelist.list` | Domini consentiti |
| `/etc/ats-proxy/admin.list` | IP che bypassano tutto |
| `/etc/ats-proxy/auth.conf` | Utenti con password hashate |

## Modi operativi

### `off`

Il plugin e caricato ma non applica policy. Serve per debug e rollback rapido.

Test atteso:

```bash
sudo scripts/ats-ctl mode off
sudo scripts/ats-ctl reload
curl -x http://127.0.0.1:8080 http://example.com -I
```

### `deny`

Blocca solo i domini in deny list. Tutto il resto passa senza auth.

```bash
sudo scripts/ats-ctl mode deny
sudo scripts/ats-ctl deny add httpbin.org
sudo scripts/ats-ctl reload
curl -x http://127.0.0.1:8080 http://httpbin.org/ip -I
# Atteso: 403 Forbidden
```

### `whitelist`

Solo i domini in whitelist passano. Tutto il resto riceve 403.

```bash
sudo scripts/ats-ctl mode whitelist
sudo scripts/ats-ctl whitelist add example.com
sudo scripts/ats-ctl reload
curl -x http://127.0.0.1:8080 http://example.com -I
# Atteso: 200/301
```

### `auth_all`

Auth richiesta per tutto. Un utente valido sovrasta deny e whitelist. Serve quando il proxy e riservato solo a utenti autenticati.

```bash
sudo scripts/ats-ctl mode auth_all
sudo scripts/ats-ctl user add admin
sudo scripts/ats-ctl reload
curl -x http://127.0.0.1:8080 http://example.com -I
# Atteso: 407 Proxy Authentication Required
curl -x http://127.0.0.1:8080 --proxy-user admin:'<password>' http://example.com -I
# Atteso: 200/301
```

### `auth_nd`

Deny blocca sempre, whitelist passa senza auth, il resto richiede auth. E il modo consigliato per beta enterprise.

```bash
sudo scripts/ats-ctl mode auth_nd
sudo scripts/ats-ctl deny add httpbin.org
sudo scripts/ats-ctl whitelist add example.com
sudo scripts/ats-ctl user add admin
sudo scripts/ats-ctl reload
```

Verifiche:

```bash
curl -x http://127.0.0.1:8080 --proxy-user admin:'<password>' http://httpbin.org/ip -I
# Atteso: 403, perche deny vince su auth

curl -x http://127.0.0.1:8080 http://example.com -I
# Atteso: 200/301, perche whitelist bypassa auth

curl -x http://127.0.0.1:8080 http://iana.org -I
# Atteso: 407
```

## Test automatico

```bash
sudo ATS_PROXY_CONFIG_DIR=/etc/ats-proxy bash scripts/ats-mode-test.sh auth_nd 8080 admin '<password>'
```

## Come funziona internamente

Il plugin si aggancia a `TS_HTTP_OS_DNS_HOOK`, legge l'host richiesto e decide se continuare la transazione o generare errore `403`/`407`. Per gli errori aggiunge dinamicamente `TS_HTTP_SEND_RESPONSE_HDR_HOOK`, cosi puo impostare status e header `Proxy-Authenticate`.

Le password non sono salvate in chiaro. `ats-ctl user add` genera un salt casuale e salva `salt$sha256(salt+password)`. Durante la richiesta, il plugin decodifica `Proxy-Authorization: Basic`, ricalcola l'hash e confronta a tempo costante.

## Upgrade futuro

Quando cambia versione ATS:

1. Compilare il plugin con `scripts/compile-plugin.sh --ats-src <path> --out bin/ats_proxy_filter_v30.so`.
2. Installare il `.so` in `libexec/trafficserver/`.
3. Eseguire `scripts/ats-mode-test.sh` per ogni mode usato.
4. Eseguire `scripts/ats-hardening-check.sh`.
5. Aggiornare `ARTIFACTS.md` e `TEST_MATRIX.md` con hash e risultati.
