# ATS Proxy Enterprise

Proxy forward enterprise basato su Apache Traffic Server 9.2.13 con plugin C custom per URL filtering, autenticazione Basic, hardening host e test di regressione.

Stato corrente: **installazione end-to-end testata il 2026-05-26 su Ubuntu 24.04 e Ubuntu 26.04** tramite `scripts/install-ats-proxy.sh`, pacchetto trasferibile e file configurazione esterno.

## Manifesto Operativo

- Nessun requisito runtime implicito: sorgente plugin, binario plugin, script e manifest hash sono versionati.
- Ogni comando documentato deve essere testato o marcato esplicitamente come non validato.
- L'installer e la guida manuale non devono divergere: il percorso supportato e quello automatizzato con file config e fallback interattivo.
- Hardening non dichiarato a parole: viene verificato da `scripts/ats-hardening-check.sh`.
- Segreti fuori repo: password e chiavi non vanno versionate; usare file config locali esclusi da Git.
- ATS 10.x non e una baseline supportata finche non passa build plugin e regression test in lab.

## Quick Start Testato

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
cp env/ats-proxy.env.example ats-proxy.env
editor ats-proxy.env

bash scripts/preflight.sh --env ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive

bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

Modalita interattiva supportata:

```bash
sudo bash scripts/install-ats-proxy.sh
```

Se un file config e presente ma mancano valori richiesti, lo script chiede solo i valori mancanti o placeholder. Con `--non-interactive`, invece, fallisce prima di modificare il sistema.

## Risultati Validati

| Target | Installer completo | Regression | Hardening |
|--------|--------------------|------------|-----------|
| VM135 Ubuntu 24.04.4 | OK, 2026-05-26 | 9/9 OK | 25/25 OK |
| VM136 Ubuntu 26.04 | OK, 2026-05-26 | 9/9 OK | 25/25 OK |

Test regression coperti: service active, DENY `403 Forbidden`, WHITELIST `301`, AUTH missing `407`, AUTH valid `301`, AUTH wrong `407`, header `Proxy-Authenticate`, 50 richieste concorrenti DENY, 50 richieste concorrenti whitelist con credenziali.

Hardening coperto: systemd sandbox, UFW, fail2ban `sshd` e `ats-proxy`, unattended upgrades, etckeeper, permessi config/log, health check cron, helper CVE.

## Artefatti Runtime

| Artefatto | Percorso | Hash/Stato |
|-----------|----------|------------|
| Plugin binario | `bin/ats_proxy_filter_v21.so` | SHA256 `26c4371d0c32377498afeb80eb874a11bed2ac8c749c600073356bb3c2087674` |
| Plugin sorgente | `src/ats_proxy_filter_v21.c` | SHA256 `ac742e549c3081af44c320117ce0a8a1e8d9b80dbb76327f154e7d0797a7ffea` |
| Installer | `scripts/install-ats-proxy.sh` | Testato end-to-end 24.04/26.04 |
| Regression | `scripts/ats-regression-test.sh` | Testato 24.04/26.04 |
| Hardening check | `scripts/ats-hardening-check.sh` | Testato 24.04/26.04 |

## Documenti Correnti

| Documento | Scopo |
|-----------|-------|
| [`GUIDA_INSTALLAZIONE_TESTATA.md`](GUIDA_INSTALLAZIONE_TESTATA.md) | Installazione supportata e verificata |
| [`GUIDA_AGGIORNAMENTO_TESTATA.md`](GUIDA_AGGIORNAMENTO_TESTATA.md) | Aggiornamento sicuro entro baseline ATS 9.2.13; ATS 10.x non validato |
| [`GUIDA_TRASFERIMENTO_VM_v1.0.md`](GUIDA_TRASFERIMENTO_VM_v1.0.md) | Flusso repo privata -> pacchetto -> VM |
| [`ARTIFACTS.md`](ARTIFACTS.md) | Manifest artefatti e provenienza |
| [`TEST_MATRIX.md`](TEST_MATRIX.md) | Stato dei test eseguiti e gap residui |
| [`CHANGELOG.md`](CHANGELOG.md) | Cronologia release |
| [`STATE_CARD.md`](STATE_CARD.md) | Stato operativo sintetico |
| [`ROOT_CAUSE_REPLICABILITA_v1.0.md`](ROOT_CAUSE_REPLICABILITA_v1.0.md) | Root cause del precedente problema di replicabilita |

Le guide storiche sono archiviate in `archive/storico/` e non sono il percorso operativo da seguire.

## Limiti Noti

- Il plugin usa `TS_HTTP_OS_DNS_HOOK`: la cache DNS di ATS puo evitare hook successivi per domini gia risolti. Il comportamento e documentato e va considerato nella policy di change/restart.
- TLS frontend su 8443 e implementato nello script ma non incluso nella batteria end-to-end del 2026-05-26.
- ATS 10.x non e validato: non aggiornare produzione ad ATS 10.x finche `GUIDA_AGGIORNAMENTO_TESTATA.md` non riporta test reali.

## Licenza

Licenza draft FEL-1.0: vedere `LICENSE.md`, `LICENSE.plain.md`, `CLA.md`. Revisione legale pendente prima di uso commerciale.
