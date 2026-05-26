# Project Archive - Stato Corrente E Memoria Tecnica

Documento corrente ricreato in root. Le note storiche estese sono in `archive/storico/PROJECT_ARCHIVE.md`.

## Decisioni Confermate

- Baseline: ATS 9.2.13.
- Plugin path: `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so`.
- Config plugin: `/etc/trafficserver/ats_proxy_filter.conf`.
- Policy order: `ADMIN -> DENY -> WHITELIST -> AUTH`.
- Installer come percorso supportato.

## Errori Storici Da Non Ripetere

- dichiarare artifact non presenti in repo;
- usare `/opt/trafficserver/lib/modules` come path operativo per questa build;
- usare `.sha256` ATS non disponibile invece di `.sha512`;
- dichiarare ATS 10.x supportato senza build/load/regression;
- dichiarare regex completa senza implementazione PCRE/regex reale.

## Test Nuovi 2026-05-26

- Admin bypass remoto da `192.168.89.55`: OK.
- DNS cache quick test corrente: bypass non riprodotto.
- Vecchio plugin recuperato: nessun vantaggio osservato sul DNS cache quick test.
- ATS 10.1.2 raw header compile: non drop-in, richiede C++17 e header generati.
