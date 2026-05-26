# Guida replicabilita deploy - ATS Proxy Enterprise v1.0

## Obiettivo

Questa guida descrive il percorso minimo per installare ATS Proxy Enterprise partendo solo dalla repository GitHub, da un file di configurazione compilato e dal binario plugin `ats_proxy_filter_v21.so`.

Il deploy non deve dipendere da memoria chat, file in `/tmp`, password esempio o valori hardcoded non dichiarati.

## Prerequisiti

- VM Ubuntu 24.04 LTS o 26.04 LTS pulita.
- Utente con `sudo`.
- Accesso Internet dalla VM per scaricare pacchetti e sorgente ATS.
- Repository GitHub clonabile.
- Plugin binario v2.1 disponibile in `bin/ats_proxy_filter_v21.so`.

> Stato attuale: il binario plugin v2.1 e stato recuperato dai dischi VM130/VM134 e versionato in `bin/ats_proxy_filter_v21.so`. Il sorgente C originale non e ancora stato recuperato.

## File da usare

| File | Scopo | Commit? |
|------|-------|---------|
| `env/ats-proxy.env.example` | Template pubblico configurazione ATS | Si |
| `ats-proxy.env` | Config reale compilata sulla VM | No |
| `scripts/preflight.sh` | Verifica config e plugin prima dell'installazione | Si |
| `scripts/install-ats-proxy.sh` | Installer ATS + hardening + plugin | Si |
| `bin/ats_proxy_filter_v21.so` | Plugin binario richiesto | Si |

## Variabili obbligatorie

| Variabile | Esempio | Note |
|-----------|---------|------|
| `ATS_HOSTNAME` | `ats-proxy-01` | Hostname VM |
| `ATS_IP_CIDR` | `192.168.89.100/24` | IP con CIDR obbligatorio |
| `ATS_GATEWAY` | `192.168.89.254` | Gateway rete |
| `ATS_DNS` | `1.1.1.1` | DNS |
| `ATS_ALLOWED_SUBNET` | `192.168.89.0/24` | Subnet autorizzata alla porta proxy |
| `ATS_ADMIN_IPS` | `192.168.89.10` | IP admin, separati da virgola |
| `ATS_DENY_DOMAINS` | `httpbin.org,bad.com` | Domini/regex bloccati |
| `ATS_WHITELIST_DOMAINS` | `google.com,github.com` | Accesso senza auth |
| `ATS_AUTH_USERS` | `admin:password-forte` | Mai lasciare `CHANGE_ME` |
| `ATS_PROXY_PORT` | `8080` | Porta proxy |
| `ATS_APPLY_NETPLAN` | `n` | Default sicuro: non cambia rete |
| `ATS_TLS_ENABLED` | `n` | TLS frontend opzionale |
| `ATS_PLUGIN_PATH` | `./bin/ats_proxy_filter_v21.so` | Path plugin obbligatorio |

## Procedura da GitHub

Se la VM non puo accedere alla repository privata, non usare questa sezione dalla VM. Usare invece `GUIDA_TRASFERIMENTO_VM_v1.0.md` per creare un pacchetto sul PC e copiarlo sulla VM.

### 1. Clona la repository

```bash
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise
```

### 2. Prepara configurazione

```bash
cp env/ats-proxy.env.example ats-proxy.env
nano ats-proxy.env
```

Regole:
- sostituire tutti i valori `CHANGE_ME`;
- impostare `ATS_PLUGIN_PATH` al path reale del plugin;
- lasciare `ATS_APPLY_NETPLAN=n` se non si ha console fuori banda;
- non committare `ats-proxy.env`.

### 3. Verifica path plugin

Nel file `ats-proxy.env` lasciare o impostare:

```bash
ATS_PLUGIN_PATH=./bin/ats_proxy_filter_v21.so
```

### 4. Esegui preflight

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

Se il preflight fallisce, non eseguire l'installer.

### 5. Installa

Validazione non distruttiva:

```bash
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive --validate-only
```

Installazione:

```bash
sudo bash scripts/install-ats-proxy.sh --env ats-proxy.env --non-interactive
```

L'installer esegue:
- rilevamento OS;
- validazione configurazione;
- installazione dipendenze;
- compilazione ATS 9.2.13;
- configurazione forward proxy;
- installazione plugin;
- systemd hardening;
- UFW/fail2ban/unattended-upgrades/etckeeper;
- health check;
- test finali.

### 6. Verifica manuale

Sostituire `8080` se `ATS_PROXY_PORT` e diverso.

```bash
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://127.0.0.1:8080 http://httpbin.org/ip
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://127.0.0.1:8080 http://google.com
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://127.0.0.1:8080 http://wikipedia.org
```

Atteso con template standard:
- `httpbin.org`: `403` per DENY;
- `google.com`: `301` o `200` per whitelist;
- `wikipedia.org`: `407` senza credenziali.

Test con credenziali:

```bash
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://127.0.0.1:8080 --proxy-user 'admin:INSERIRE_PASSWORD' http://wikipedia.org
```

## Percorso interattivo

Se non si vuole preparare `ats-proxy.env`, si puo usare:

```bash
sudo bash scripts/install-ats-proxy.sh
```

Lo script chiedera i valori. Questo percorso e meno replicabile: per produzione o lavoro ripetibile usare sempre `ats-proxy.env` + preflight.

## Errori bloccanti intenzionali

L'installer si ferma prima di modificare il sistema se:
- manca una variabile obbligatoria;
- `ATS_AUTH_USERS` contiene `CHANGE_ME`;
- `ATS_IP_CIDR` non contiene il suffisso CIDR;
- il plugin `ats_proxy_filter_v21.so` non esiste nel path indicato.

## Principio di replicabilita

Un deploy valido deve essere ricostruibile con:

```text
repository GitHub + ats-proxy.env locale + ats_proxy_filter_v21.so
```

Non deve dipendere da:

```text
memoria chat + /tmp + password esempio + default non dichiarati
```

## Gap residuo

Il gap principale residuo e il sorgente C del plugin v2.1 non ancora recuperato. Il binario recuperato e versionato, ma prima di dichiarare completa la manutenibilita del ciclo occorre recuperare o ricostruire in modo verificato `ats_proxy_filter_v21.c`.

## Test richiesti prima di dichiarare produzione

- `bash -n scripts/*.sh`: verificato localmente.
- `scripts/preflight.sh` su template: verificato localmente, fallisce se non compilato.
- `scripts/preflight.sh` su config valida con plugin dummy: verificato localmente, passa.
- `scripts/install-ats-proxy.sh` su template: verificato localmente, fallisce prima di modifiche sistema.
- `scripts/install-ats-proxy.sh --validate-only` su config valida con plugin dummy: verificato localmente, passa senza installare.
- `scripts/install-24.04.sh --validate-only` su host 24.04: verificato localmente, passa.
- `scripts/install-26.04.sh --validate-only` su host 24.04: verificato localmente, blocca OS errato.
- Installazione completa su Ubuntu 24.04 pulita: da validare su VM reale.
- Installazione completa su Ubuntu 26.04 pulita: da validare su VM reale.
