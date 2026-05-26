# Guida Trasferimento Su VM

Scenario: la VM non ha accesso alla repo privata GitHub. Questo flusso e stato usato nei test end-to-end del 2026-05-26 su VM135 e VM136.

## Stato Testato

| Percorso | Stato |
|----------|-------|
| Package da repo con plugin versionato | OK |
| Trasferimento package su VM | OK |
| `install-ats-proxy.sh --validate-only` su Ubuntu 24.04 | OK |
| `install-ats-proxy.sh` completo su Ubuntu 24.04 | OK |
| `install-ats-proxy.sh --validate-only` su Ubuntu 26.04 | OK |
| `install-ats-proxy.sh` completo su Ubuntu 26.04 | OK |
| Regression post-install | 9/9 OK su entrambe |
| Hardening post-install | 25/25 OK su entrambe |

## 1. Crea Il Pacchetto

Sul PC con accesso GitHub:

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
bash scripts/check-repo-consistency.sh
bash scripts/package-release.sh --output-dir dist --force
```

Output atteso:

```text
[OK] Included versioned plugin: bin/ats_proxy_filter_v21.so
[OK] Package created: dist/ats-proxy-enterprise-YYYYMMDD.tar.gz
```

## 2. Copia Su VM

```bash
scp dist/ats-proxy-enterprise-YYYYMMDD.tar.gz ubuntu@VM_IP:/tmp/
scp ats-proxy.env ubuntu@VM_IP:/tmp/
```

`ats-proxy.env` deve essere locale e non versionato. Non includere password reali nei file tracciati da Git.

## 3. Estrai Su VM

```bash
sudo mkdir -p /opt/ats-proxy-enterprise
sudo tar -xzf /tmp/ats-proxy-enterprise-YYYYMMDD.tar.gz -C /opt/ats-proxy-enterprise --strip-components=1
sudo chown -R "$USER:$USER" /opt/ats-proxy-enterprise
cd /opt/ats-proxy-enterprise
```

## 4. Valida Config

```bash
bash scripts/preflight.sh --env /tmp/ats-proxy.env
sudo bash scripts/install-ats-proxy.sh --env /tmp/ats-proxy.env --non-interactive --validate-only
```

Se fallisce, correggere il file config prima di installare.

## 5. Installa

```bash
sudo bash scripts/install-ats-proxy.sh --env /tmp/ats-proxy.env --non-interactive
```

Lo stesso installer riconosce Ubuntu 24.04 e 26.04. Su 26.04 compila PCRE1 8.45 prima di ATS.

## 6. Verifica

```bash
bash scripts/ats-regression-test.sh 8080 admin '<password>'
sudo bash scripts/ats-hardening-check.sh 8080
```

Esito atteso:

```text
Passed: 9  Failed: 0
Passed: 25  Failed: 0  Warnings: 0
```

## Note

- Usare `ATS_APPLY_NETPLAN=n` salvo accesso console fuori banda.
- Il plugin deve restare in `bin/ats_proxy_filter_v21.so` nel pacchetto.
- Per deploy da repo diretta usare `GUIDA_INSTALLAZIONE_TESTATA.md`.
