# Guida Aggiornamento Testata

Questa guida documenta solo aggiornamenti verificati o esplicitamente esclusi dalla baseline.

## Baseline Supportata

La baseline validata e:

- Apache Traffic Server 9.2.13.
- Ubuntu 24.04 e 26.04.
- Plugin `ats_proxy_filter_v21` compilato e testato su ATS 9.2.13.
- Installer `scripts/install-ats-proxy.sh` testato end-to-end il 2026-05-26 su VM135 e VM136.

## Aggiornamento Config/Script Entro Baseline

Procedura testata:

```bash
git pull
bash scripts/check-repo-consistency.sh
bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

Esito atteso:

- installer completa senza errori;
- regression `9/9`;
- hardening `25/25`;
- `trafficserver` active.

## Aggiornamento Del Plugin Entro ATS 9.2.13

Procedura sicura:

```bash
bash scripts/check-repo-consistency.sh
sudo install -o ats -g ats -m 755 bin/ats_proxy_filter_v21.so /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo systemctl restart trafficserver
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

Questa procedura e valida solo se il binario mantiene l'hash atteso in `ARTIFACTS.md` o se `ARTIFACTS.md` e `TEST_MATRIX.md` vengono aggiornati con una nuova build realmente testata.

## CVE Monitoring

L'installer copia `scripts/cve-check.sh` in `/opt/cve-check.sh` quando presente. Uso manuale:

```bash
sudo /opt/cve-check.sh
```

Il risultato va letto come segnale operativo, non come prova di compliance completa. Per CVE critiche ATS o OpenSSL, creare una VM lab e ripetere installer + regression + hardening prima della produzione.

## ATS 10.x

Stato: **non validato**.

Non aggiornare produzione ad ATS 10.x finche non sono completati e documentati:

- build ATS 10.x da sorgente;
- compilazione `src/ats_proxy_filter_v21.c` contro header ATS 10.x;
- caricamento plugin senza simboli mancanti;
- regression `9/9`;
- hardening `25/25`;
- verifica del limite DNS hook o migrazione a hook piu adatto.

## Rollback

Rollback minimo entro baseline 9.2.13:

```bash
sudo systemctl stop trafficserver
sudo install -o ats -g ats -m 755 bin/ats_proxy_filter_v21.so /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so
sudo systemctl start trafficserver
bash scripts/ats-regression-test.sh 8080 admin '<password>'
```

Se il problema riguarda config, usare etckeeper:

```bash
cd /etc
sudo git log --oneline -5
```

Non fare rollback ciechi in produzione: salvare prima `systemctl status trafficserver`, log ATS e output regression.
