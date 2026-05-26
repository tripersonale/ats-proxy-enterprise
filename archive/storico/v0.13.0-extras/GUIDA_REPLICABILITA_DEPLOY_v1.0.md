# ATS Proxy Enterprise - Guida Replicabilita Deploy

Documento corrente ricreato in root. La replicabilita e stata chiusa nella baseline 0.13.0 con installer testato su VM135 e VM136.

## Requisiti Di Replicabilita

- repo GitHub completa;
- `bin/ats_proxy_filter_v21.so` versionato;
- `src/ats_proxy_filter_v21.c` versionato;
- `env/ats-proxy.env.example` compilabile localmente;
- installer `scripts/install-ats-proxy.sh`;
- test `scripts/ats-regression-test.sh` e `scripts/ats-hardening-check.sh`.

## Percorso Validato

```bash
bash scripts/check-repo-consistency.sh
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env
bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

## Evidenza

| VM | OS | Installer | Regression | Hardening |
|----|----|-----------|------------|-----------|
| VM135 | Ubuntu 24.04.4 | OK | 9/9 | 25/25 |
| VM136 | Ubuntu 26.04 | OK | 9/9 | 25/25 |

## Pacchetto Trasferibile

```bash
bash scripts/package-release.sh --output-dir dist --force
```

Dettaglio completo: `GUIDA_TRASFERIMENTO_VM_v1.0.md`.

## Regola

Nessun comando entra in README/guide correnti senza stato in `TEST_MATRIX.md`.
