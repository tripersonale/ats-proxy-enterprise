# STATE CARD - ATS Proxy Enterprise

## Identita

- Repository: `https://github.com/tripersonale/ats-proxy-enterprise.git`
- Directory operativa: `/home/mvb/CULLA-instance/03_ICT/ats-proxy/`
- Versione progetto: `0.12.0`
- Baseline supportata: ATS 9.2.13 su Ubuntu 24.04/26.04

## Stato Corrente

- Installer end-to-end testato su VM135 Ubuntu 24.04.4: OK.
- Installer end-to-end testato su VM136 Ubuntu 26.04: OK.
- Regression post-install: 9/9 OK su entrambe.
- Hardening post-install: 25/25 OK su entrambe.
- Plugin sorgente e binario versionati con hash in `ARTIFACTS.md`.
- Guide storiche archiviate in `archive/storico/`.

## VM Lab

| VM | OS | IP | Stato |
|----|----|----|-------|
| VM135 | Ubuntu 24.04.4 | 192.168.89.35 | Installer/regression/hardening OK |
| VM136 | Ubuntu 26.04 | 192.168.89.36 | Installer/regression/hardening OK |

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

- `README.md`: manifesto e quick start.
- `GUIDA_INSTALLAZIONE_TESTATA.md`: guida installazione corrente.
- `GUIDA_AGGIORNAMENTO_TESTATA.md`: aggiornamento entro baseline, ATS 10.x non validato.
- `scripts/install-ats-proxy.sh`: installer supportato.
- `scripts/ats-regression-test.sh`: test funzionale.
- `scripts/ats-hardening-check.sh`: test hardening.
- `ARTIFACTS.md`: manifest runtime.
- `TEST_MATRIX.md`: evidenza test.

## Gap Residui

- ATS 10.x non validato.
- TLS frontend opzionale non incluso nella batteria e2e.
- Carico oltre 50 richieste concorrenti non validato in questa sessione.
- Revisione legale FEL-1.0/CLA pendente.
