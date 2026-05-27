# STATE CARD - ATS Proxy Enterprise

## Identita

- Repository: `https://github.com/tripersonale/ats-proxy-enterprise.git`
- Directory operativa: `/home/mvb/CULLA-instance/03_ICT/ats-proxy/`
- Versione progetto: `0.14.0`
- Baseline supportata: ATS 9.2.13 su Ubuntu 24.04/26.04
- Direzione v3.0: ATS 10.1.2 LTS su Ubuntu 26.04, plugin unico a modi, config `/etc/ats-proxy/`, auth hashata.

## Stato Corrente

- Installer end-to-end testato su VM135 Ubuntu 24.04.4: OK.
- Installer end-to-end testato su VM136 Ubuntu 26.04: OK.
- Regression post-install: 9/9 OK su entrambe.
- Hardening post-install: 25/25 OK su entrambe.
- Plugin sorgente e binario versionati con hash in `ARTIFACTS.md`.
- Documentazione ricostruita v0.14.0: `GUIDA_INSTALLAZIONE.md`, `GUIDA_OPERATIVA.md`.
- Guide storiche archiviate in `archive/storico/`.
- Architettura v3.0 avviata: `src/ats_proxy_filter_v30.c`, `scripts/ats-ctl`, `scripts/compile-plugin.sh`, `scripts/ats-mode-test.sh`, guide v3.0 dedicate.

## VM Lab

| VM | OS | IP | Stato |
|----|----|----|-------|
| VM135 | Ubuntu 24.04.4 | 192.168.89.35 | Installer/regression/hardening OK |
| VM136 | Ubuntu 26.04 | 192.168.89.36 | Installer/regression/hardening OK |
| VM137 | Ubuntu 26.04 | 192.168.89.37 | ATS 10.1.2 L0 OK; plugin v3.0 build/load; 5 mode tests OK pre/post core hardening; hardening core 19 OK, 0 fail, 5 warning |

Chiavi operative persistenti: `~/CULLA-instance/01_SECRETS/ssh/`.

## Percorso Operativo Supportato

```bash
bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

## File Chiave

- `README.md`: manifesto ICT e quick start.
- `GUIDA_INSTALLAZIONE.md`: guida installazione completa (manuale + automatizzata, dual-OS).
- `GUIDA_OPERATIVA.md`: guida operativa unificata (day-to-day, CVE, GDPR, incident response).
- `scripts/install-ats-proxy.sh`: installer supportato.
- `scripts/ats-regression-test.sh`: test funzionale.
- `scripts/ats-hardening-check.sh`: test hardening.
- `ARCHITETTURA_ATS_PROXY_V3.md`: architettura target plugin/installer atomico.
- `GUIDA_PLUGIN_URL_FILTERING_AUTH.md`: manuale plugin v3.0 e test mode.
- `GUIDA_INSTALLAZIONE_ATS_LTS.md`: target ATS 10.1.2 su Ubuntu 26.04.
- `MANUALE_ATS.md`: manuale ATS minimo.
- `ARTIFACTS.md`: manifest runtime.
- `TEST_MATRIX.md`: evidenza test.

## Gap Residui

- ATS 10.x non validato.
- Plugin v3.0 compilato/runtime-testato su VM137 ATS 10.1.2; hardening core v3 applicato.
- TLS frontend opzionale non incluso nella batteria e2e.
- Carico oltre 50 richieste concorrenti non validato in questa sessione.
- Revisione legale FEL-1.0/CLA pendente.
- Procedura formale di vulnerability assessment non ancora definita.
- Penetration test annuale non ancora eseguito.

## Prossima Validazione

- Applicare hardening network v3 su VM137: UFW, fail2ban, etckeeper.
- Testare TLS frontend con plugin v3.
- Aggiornare installer atomico L0/L1/L3 con quanto validato su VM137.
