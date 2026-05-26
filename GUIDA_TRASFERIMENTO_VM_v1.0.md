# Guida trasferimento su VM - ATS Proxy Enterprise v1.0

## Scenario

La VM non ha accesso alla repository privata GitHub. Il flusso corretto e:

1. scaricare/clonare la repo su un PC con accesso GitHub;
2. creare un pacchetto `.tar.gz` pulito;
3. copiare il pacchetto sulla VM Ubuntu 24.04 o 26.04;
4. compilare `ats-proxy.env` sulla VM;
5. eseguire preflight;
6. eseguire installer.

## Artefatti necessari

| Artefatto | Dove nasce | Dove serve | Obbligatorio |
|-----------|------------|------------|--------------|
| `ats-proxy-enterprise-YYYYMMDD.tar.gz` | PC con repo privata | VM | Si |
| `bin/ats_proxy_filter_v21.so` | Repo/pacchetto | VM | Si |
| `ats-proxy.env` | VM, da template | VM | Si |

## Stato test comandi

| Comando/percorso | Stato |
|------------------|-------|
| `bash -n scripts/*.sh` | Verificato localmente |
| `scripts/package-release.sh` senza plugin | Verificato localmente |
| `scripts/package-release.sh --include-plugin FILE` | Verificato localmente con file dummy |
| `scripts/preflight.sh` con template non compilato | Verificato localmente: fallisce come previsto |
| `scripts/preflight.sh` con config valida e plugin dummy | Verificato localmente: passa |
| `scripts/install-ats-proxy.sh` con template non compilato | Verificato localmente: fallisce prima di modifiche sistema |
| `scripts/install-ats-proxy.sh --validate-only` con config valida | Verificato localmente: passa senza installare |
| `scripts/install-24.04.sh --validate-only` su host 24.04 | Verificato localmente: passa |
| `scripts/install-26.04.sh --validate-only` su host 24.04 | Verificato localmente: blocca OS errato |
| `scripts/install-24.04.sh` su Ubuntu 24.04 | Da validare su VM reale |
| `scripts/install-26.04.sh` su Ubuntu 26.04 | Da validare su VM reale |
| Installazione completa ATS + plugin | Da validare su VM reale pulita/snapshot |

## 1. Sul PC con accesso GitHub

Clonare o aggiornare la repo privata:

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
```

Se la repo esiste gia:

```bash
cd ats-proxy-enterprise
```

Creare pacchetto con il plugin versionato in `bin/`:

```bash
bash scripts/package-release.sh
```

Output atteso:

```text
[OK] Included versioned plugin: bin/ats_proxy_filter_v21.so
[OK] Package created: .../dist/ats-proxy-enterprise-YYYYMMDD.tar.gz
```

Se si vuole sovrascrivere il plugin versionato con un altro binario esplicito:

```bash
bash scripts/package-release.sh --include-plugin /percorso/ats_proxy_filter_v21.so --force
```

Output atteso:

```text
[OK] Included plugin: ats_proxy_filter_v21.so
[OK] Package created: .../dist/ats-proxy-enterprise-YYYYMMDD.tar.gz
```

## 2. Copiare il pacchetto sulla VM

Sostituire `VM_IP` e utente SSH.

```bash
scp dist/ats-proxy-enterprise-YYYYMMDD.tar.gz ubuntu@VM_IP:/tmp/
```

## 3. Sulla VM

Estrarre il pacchetto:

```bash
cd /opt
sudo tar xzf /tmp/ats-proxy-enterprise-YYYYMMDD.tar.gz
sudo chown -R "$USER:$USER" /opt/ats-proxy-enterprise
cd /opt/ats-proxy-enterprise
```

Preparare configurazione:

```bash
cp env/ats-proxy.env.example ats-proxy.env
nano ats-proxy.env
```

Valori obbligatori da controllare:
- nessun `CHANGE_ME` rimasto;
- `ATS_IP_CIDR` con suffisso `/24` o CIDR corretto;
- `ATS_PLUGIN_PATH=./bin/ats_proxy_filter_v21.so`;
- `ATS_APPLY_NETPLAN=n` salvo console Proxmox/fuori banda disponibile.

## 4. Preflight obbligatorio

```bash
bash scripts/preflight.sh --env ats-proxy.env
```

Output atteso:

```text
[OK] Config file loaded
[OK] Required values present
[OK] Auth placeholders replaced
[OK] Plugin binary present
[OK] Preflight passed
```

Se fallisce, non procedere con l'installer.

## 5. Installazione Ubuntu 24.04

Su Ubuntu 24.04 usare il wrapper dedicato:

```bash
sudo bash scripts/install-24.04.sh --env ats-proxy.env --non-interactive --validate-only
```

Se la validazione passa, installare:

```bash
sudo bash scripts/install-24.04.sh --env ats-proxy.env --non-interactive
```

Il wrapper blocca l'esecuzione se la VM non e Ubuntu 24.04 Noble.

## 6. Installazione Ubuntu 26.04

Su Ubuntu 26.04 usare il wrapper dedicato:

```bash
sudo bash scripts/install-26.04.sh --env ats-proxy.env --non-interactive --validate-only
```

Se la validazione passa, installare:

```bash
sudo bash scripts/install-26.04.sh --env ats-proxy.env --non-interactive
```

Il wrapper blocca l'esecuzione se la VM non e Ubuntu 26.04 Resolute.

## 7. Verifiche post-installazione

Sostituire porta se `ATS_PROXY_PORT` non e `8080`.

```bash
systemctl is-active trafficserver
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://127.0.0.1:8080 http://httpbin.org/ip
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://127.0.0.1:8080 http://google.com
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://127.0.0.1:8080 http://wikipedia.org
```

Atteso con template standard compilato:
- `trafficserver`: `active`;
- `httpbin.org`: `403`;
- `google.com`: `301` o `200`;
- `wikipedia.org`: `407` senza credenziali.

## 8. Regola di metodo scientifico

Un comando entra nella guida solo con stato dichiarato:
- verificato localmente;
- verificato su VM reale;
- da validare su VM reale.

Non dichiarare completo un percorso finche non e stato eseguito su VM pulita o snapshot e il risultato e stato registrato in `STATE_CARD.md`.
