# Apache Traffic Server - Guida Concettuale

Documento corrente ricreato in root. Spiega il perche tecnico della baseline ATS Proxy Enterprise 0.13.0.

## Cos'e ATS In Questo Progetto

Apache Traffic Server e usato come forward proxy HTTP/HTTPS CONNECT. Non e un semplice port forwarder: termina la connessione client, applica policy e apre una connessione verso l'upstream.

## Pipeline Richiesta

```text
client -> socket ATS -> ip_allow.yaml -> request/plugin hooks -> DNS/upstream -> response/log
```

Nel nostro progetto:

- `ip_allow.yaml` filtra client/subnet;
- `ats_proxy_filter.so` applica policy host/auth;
- `logging.yaml` produce audit log;
- systemd/UFW/fail2ban proteggono host e processo.

## I Quattro Livelli Di Controllo

| Livello | Obiettivo | Config |
|---------|-----------|--------|
| YAML ACL | ammettere solo subnet/client autorizzati | `ip_allow.yaml` |
| URL filter | bloccare o permettere domini | `DENY`, `WHITELIST` |
| Auth | richiedere credenziali per il resto | `USER` |
| Admin bypass | permettere IP amministrativi | `ADMIN` |

UFW e fail2ban sono layer aggiuntivi, non sostitutivi.

## Cache ATS

ATS puo usare cache RAM e disco. Nel progetto e configurata cache disco in `/opt/trafficserver/var/trafficserver/cache` e RAM cache via `records.config`.

La cache HTTP non va confusa con la cache DNS. Il limite noto del plugin riguarda il fatto che `TS_HTTP_OS_DNS_HOOK` puo non scattare quando la risoluzione DNS e gia in cache.

## Perche ATS 9.2.13

- Versione LTS 9.x validata in laboratorio.
- Build autotools nota.
- Plugin C compilato e caricato correttamente.
- Regression e hardening superati su 24.04 e 26.04.

ATS 10.x resta interessante, ma non e baseline finche non passa test reali con plugin.

## Forward Proxy E Remap

Per essere forward proxy puro servono:

```text
CONFIG proxy.config.url_remap.remap_required INT 0
CONFIG proxy.config.reverse_proxy.enabled INT 0
```

Se questi valori vengono persi dopo `make install`, ATS puo rispondere con errori tipo 404/invalid URL.

## Hook Plugin

Il plugin corrente usa `TS_HTTP_OS_DNS_HOOK` per poter produrre risposte `403` e `407` nel flusso validato. Trade-off: DNS cache gap.

Una futura v2.2 dovrebbe valutare hook request/pre-remap o una doppia strategia per applicare policy a ogni richiesta senza perdere la capacita di generare errori proxy corretti.
