# Root Cause - Recupero contesto e artifact gap

## Problema

Il progetto documentava `ats_proxy_filter_v21.c` e `ats_proxy_filter_v21.so` come parti operative del deploy, ma la repository Git non conteneva ne il sorgente ne il binario.

Questo ha reso lento tornare al contesto operativo: le guide descrivevano comportamento testato su VM reali, ma non esisteva un artifact tracciato da cui riprodurre il deploy.

## Perche e successo

1. Il lavoro sul plugin e stato fatto direttamente sulle VM durante iterazioni di debug.
2. Le guide sono state aggiornate con il risultato funzionale, ma l'artifact prodotto sulla VM non e stato copiato e committato nella repo.
3. Non esisteva un gate automatico che verificasse: "ogni file citato come necessario esiste nel repository o e dichiarato come esterno".
4. La state card conteneva stato funzionale, ma non una manifestazione formale degli artifact richiesti.
5. Le chiavi SSH temporanee in `/tmp` hanno reso piu fragile il recupero successivo dalle VM.

## Cosa ci ha fatto perdere tempo

- Ricostruzione del contesto da documenti, session export e log invece che da artifact versionati.
- Ambiguita tra "testato su VM" e "riproducibile da repo".
- Accesso SSH guest non disponibile per VM130/VM134.
- Guest agent Proxmox non disponibile su VM134.
- Mancanza iniziale di un manifest artifact con hash, provenienza e stato sorgente.

## Cosa e stato recuperato

Il binario operativo e stato recuperato in sola lettura dai dischi VM tramite Proxmox/libguestfs:

```text
VM130: /opt/trafficserver/lib/modules/ats_proxy_filter.so
VM134: /opt/trafficserver/lib/modules/ats_proxy_filter.so
```

I due binari sono identici e sono stati versionati come:

```text
bin/ats_proxy_filter_v21.so
```

Hash:

```text
SHA256: 6a1a73ff015ced9d6d35631fecf318d860bfbbf59b6066dcb3eecb8490d8f9c7
```

## Risoluzione

Il sorgente C e stato ricostruito il 2026-05-25 da comportamento documentato e versionato:

```text
src/ats_proxy_filter_v21.c  SHA256: 35c2a1e4c6dec45d52f5e38fd58d640416ba22fcec77cf9087e03cce89f797e4
```

Resta da compilare su VM con ATS 9.2.13 e validare equivalenza funzionale col binario recuperato.

## Regole strutturali introdotte

1. `ARTIFACTS.md` e la fonte autorevole per artifact, hash, provenienza e gap.
2. `CHANGELOG.md` registra ogni cambio rilevante.
3. `VERSION` identifica la versione corrente della repo.
4. `TEST_MATRIX.md` registra cosa e testato, cosa fallisce correttamente e cosa resta da validare.
5. `scripts/check-repo-consistency.sh` fallisce se il plugin manca, cambia hash o le guide contengono affermazioni obsolete.
6. `scripts/preflight.sh` blocca l'installazione se config o plugin non sono presenti.
7. `scripts/package-release.sh` include il plugin versionato nel pacchetto trasferibile.

## Regola futura

Nessuna guida puo dichiarare un file come disponibile o necessario senza una di queste condizioni:
- il file e tracciato in Git;
- il file e generato da uno script tracciato e testato;
- il file e dichiarato in `ARTIFACTS.md` come artifact esterno con provenienza, hash e istruzioni di recupero.

Se una di queste condizioni manca, la guida deve dire esplicitamente "gap aperto" e `scripts/check-repo-consistency.sh` deve fallire o avere un controllo dedicato.
