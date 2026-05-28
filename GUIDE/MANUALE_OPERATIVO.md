# Manuale Operativo — ATS Proxy Enterprise v3.0

Manuale unificato per l'operatore. Copre gestione ATS, plugin v3, troubleshooting,
configurazione client, backup e manutenzione periodica.

**Convenzioni path**: questo manuale usa i path di ATS9 da pacchetto Ubuntu
(`/etc/trafficserver`, `/opt/trafficserver/var/trafficserver/`). Se ATS e compilato manualmente
in `/opt/trafficserver`, i path equivalenti sono:
Config: `/opt/trafficserver/etc/trafficserver/`
Log: `/opt/trafficserver/var/log/trafficserver/`
Binari: `/opt/trafficserver/bin/` (al posto di `/usr/bin/`)

---

## 1. Comandi rapidi (cheatsheet)

| Comando | Cosa fa |
|---|---|
| `sudo systemctl status trafficserver` | Stato del servizio ATS |
| `sudo systemctl restart trafficserver` | Riavvia ATS |
| `sudo systemctl stop trafficserver` | Ferma ATS |
| `sudo systemctl start trafficserver` | Avvia ATS |
| `sudo ats-ctl status` | Stato policy plugin (MODE, conteggi) |
| `sudo ats-ctl mode <mode>` | Cambia modalita operativa |
| `sudo ats-ctl deny add <dominio>` | Blocca un dominio |
| `sudo ats-ctl deny remove <dominio>` | Sblocca un dominio |
| `sudo ats-ctl whitelist add <dominio>` | Consenti dominio senza auth |
| `sudo ats-ctl whitelist remove <dominio>` | Rimuovi da whitelist |
| `sudo ats-ctl user add <nome>` | Crea utente (chiede password) |
| `sudo ats-ctl user remove <nome>` | Rimuovi utente |
| `sudo ats-ctl admin add <ip>` | IP che bypassa ogni regola |
| `sudo ats-ctl admin remove <ip>` | Rimuovi IP admin |
| `sudo ats-ctl reload` | Applica modifiche e riavvia ATS |
| `sudo ats-ctl init` | Inizializza file config se mancanti |
| `/opt/trafficserver/bin/traffic_top` | Metriche in tempo reale |
| `sudo tail -f /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log` | Segui log diagnostici |
| `sudo bash scripts/ats-mode-test.sh auth_nd 8080 admin '<password>'` | Test automatico policy |
| `sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full bash scripts/ats-hardening-check.sh 8080` | Verifica hardening |
| `sudo bash scripts/ats-version-report.sh` | Report diagnostico completo |
| `man ats-ctl` | Man page di ats-ctl |
| `man ats-proxy-filter` | Man page del plugin |
| `curl -x http://127.0.0.1:8080 http://example.com -I` | Test rapido proxy |

---

## 2. Gestione ATS

### 2.1 Avvio, stop, restart, status

ATS e gestito da systemd tramite l'unita `trafficserver.service`.

```bash
# Stato del servizio
sudo systemctl status trafficserver
# Output atteso: Active: active (running)

# Avvio
sudo systemctl start trafficserver

# Stop
sudo systemctl stop trafficserver

# Restart
sudo systemctl restart trafficserver

# Riavvio dopo modifica configurazione (preferire ats-ctl reload)
sudo systemctl reload trafficserver

# Verifica caricamento al boot
sudo systemctl is-enabled trafficserver
# Output atteso: enabled

# Riabilitare al boot se disabilitato
sudo systemctl enable trafficserver
```

**Verifica rapida che il proxy risponda**:

```bash
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
# Output atteso: 200
```

**Verifica configurazione senza riavviare** (solo su ATS compilato in `/opt/trafficserver`):

```bash
/opt/trafficserver/bin/traffic_server -C verify_config
```

### 2.2 Log: dove sono, come leggerli, cosa cercare

| File | Contenuto |
|---|---|
| `diags.log` | Log diagnostici: errori, warning, eventi plugin |
| `squid.blog` | Log accessi in formato squid-compatibile |
| `audit.log` | Richieste processate (audit trail) |

Path canonico: `/opt/trafficserver/var/trafficserver/log/trafficserver/`
(Se ATS compilato: `/opt/trafficserver/var/log/trafficserver/`)

```bash
# Seguire log in tempo reale
sudo tail -f /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log

# Ultimi 20 errori
sudo grep -i 'error\|fail\|alert' \
  /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -20

# Tentativi di auth falliti
sudo grep 'AUTH FAIL' \
  /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -20

# Domini bloccati nelle ultime richieste
sudo grep 'DENY' \
  /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -20

# Chi ha usato il bypass admin
sudo grep 'ADMIN bypass' \
  /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -10

# Richieste processate (audit)
sudo tail -50 /opt/trafficserver/var/trafficserver/log/trafficserver/audit.log

# Ultima riga di log (check rapido che il servizio processi richieste)
sudo tail -1 /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log
```

**Cosa cercare nei log**:
- `AUTH FAIL` — password sbagliata o utente inesistente
- `DENY` — dominio bloccato dalla deny list
- `403` — risposta Forbidden generata dal plugin
- `407` — Proxy Authentication Required (auth mancante)
- `ADMIN bypass` — IP admin ha bypassato le regole
- `error` / `fail` / `alert` — problemi ATS core

**Log del plugin specifico**:

```bash
sudo grep ats_proxy_filter /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -20
```

### 2.3 Monitoring: traffic_top, metriche, spazio disco

**Metriche in tempo reale**:

```bash
# Dashboard testuale in tempo reale
/opt/trafficserver/bin/traffic_top

# Connessioni client attive
/opt/trafficserver/bin/traffic_ctl metric get \
  proxy.process.http.current_client_connections
```

**Spazio disco** (cache ATS + log possono saturarsi):

```bash
# Spazio su disco
df -h

# Spazio occupato da ATS
du -sh /opt/trafficserver/

# Spazio log
du -sh /opt/trafficserver/var/trafficserver/log/
```

**RAM e CPU**:

```bash
# Memoria
free -h

# Carico CPU
uptime

# Processi ATS
ps aux | grep traffic
```

**Report diagnostico completo** (da inviare al supporto):

```bash
sudo bash scripts/ats-version-report.sh
```

Output include: versione OS, versione ATS, stato servizio, hash plugin,
config, porte in ascolto, ultimi errori di log.

**Health check automatico**: se installato hardening v3, un cron ogni minuto
verifica che `traffic_server` sia running e lo riavvia se fermo.

```bash
# Verificare che il cron sia attivo
sudo crontab -l | grep ats_health

# Log health check
sudo tail /var/log/ats-health.log
```

### 2.4 Configurazione ATS: dove sono i file, come modificarli

**File principali** (path ATS9 da pacchetto):

| File | Contenuto |
|---|---|
| `/etc/trafficserver/records.config` | Parametri runtime (porte, cache, timeout) |
| `/etc/trafficserver/plugin.config` | Lista plugin caricati all'avvio |
| `/opt/trafficserver/etc/trafficserver/ip_allow.yaml` | ACL IP sorgenti abilitati |
| `/opt/trafficserver/etc/trafficserver/remap.config` | Mappature reverse proxy |

Se ATS e compilato in `/opt/trafficserver`, i path sono
`/opt/trafficserver/etc/trafficserver/`.

**Modifica configurazione ATS core**:

```bash
# Editare con permessi corretti
sudoedit /etc/trafficserver/records.config

# Verificare sintassi (solo ATS compilato)
/opt/trafficserver/bin/traffic_server -C verify_config

# Riavviare per applicare
sudo systemctl restart trafficserver
```

**ATTENZIONE**: non modificare `plugin.config` a mano per il plugin v3.
Usare `ats-ctl init` e `ats-ctl reload`. Il plugin va dichiarato in
`plugin.config` una volta sola durante l'installazione.

**Permessi corretti**:

```bash
# Config ATS: proprietario root:trafficserver, permessi 0640
# Config plugin: proprietario root:trafficserver, permessi 0640
# Directory plugin: 0750
ls -la /etc/trafficserver/plugin/
ls -la /opt/trafficserver/etc/trafficserver/
```

**Componenti ATS** (per riferimento):

| Componente | Ruolo |
|---|---|
| `traffic_server` | Processo dati: accetta richieste, applica plugin/config |
| `traffic_manager` | Supervisione: monitoring e restart automatico |
| `traffic_ctl` | CLI amministrativa per metriche e controllo |
| `traffic_top` | Dashboard real-time |

**Regola operativa**: se qualcosa non funziona, prima isola ATS core dal plugin.

1. `sudo ats-ctl mode off && sudo ats-ctl reload`
2. Verifica che ATS core risponda: `curl -x http://127.0.0.1:8080 http://example.com -I`
3. Se ATS core funziona, ripristina plugin in `deny`: `sudo ats-ctl mode deny && sudo ats-ctl reload`
4. Solo dopo attiva auth/hardening.

---

## 3. Gestione Plugin v3

Il plugin si gestisce con `ats-ctl` (`/usr/local/bin/ats-ctl` dopo installazione DEB,
oppure `scripts/ats-ctl` dalla directory del repository).

### 3.1 Modalita operative

| Modo | Deny list | Whitelist | Auth richiesta | Uso tipico |
|---|---|---|---|---|
| `off` | ignorata | ignorata | nessuna | Debug, manutenzione, rollback rapido |
| `deny` | attiva — 403 sui domini in lista | ignorata | nessuna | Blocco selettivo senza auth |
| `whitelist` | ignorata | attiva — solo domini in lista passano, resto 403 | nessuna | Proxy ultra-restrittivo (kiosk, scuola) |
| `auth_all` | superata da auth valida | superata da auth valida | obbligatoria per ogni richiesta | Proxy riservato a utenti autenticati |
| `auth_nd` | attiva — blocca sempre, anche con auth | attiva — passa senza auth | richiesta per il resto | **Modo consigliato beta enterprise** |

**Matrice decisionale `auth_nd`**:

| Condizione | Risultato |
|---|---|
| Dominio in deny list | 403 — bloccato sempre |
| Dominio in whitelist | Passa senza auth |
| IP in admin list | Passa senza auth ne deny |
| Dominio non in liste, senza auth | 407 — Proxy Authentication Required |
| Dominio non in liste, con auth valida | Passa |

### 3.2 Gestione deny list

```bash
# Bloccare un dominio
sudo ats-ctl deny add facebook.com
# Output atteso: [OK] deny added: facebook.com

# Bloccare con regex (tutti i domini .ru)
sudo ats-ctl deny add '.*\.ru$'

# Bloccare piu domini in sequenza
sudo ats-ctl deny add instagram.com
sudo ats-ctl deny add tiktok.com

# Rimuovere un blocco
sudo ats-ctl deny remove facebook.com
# Output atteso: [OK] deny removed if present: facebook.com

# Applicare le modifiche
sudo ats-ctl reload
# Output atteso: [OK] restarted trafficserver

# Vedere la lista corrente
cat /etc/trafficserver/plugin/deny.list
```

**Test**:

```bash
# Verificare che un dominio sia bloccato
curl -x http://127.0.0.1:8080 http://facebook.com -I
# Output atteso: HTTP/1.1 403 Forbidden
```

### 3.3 Gestione whitelist

```bash
# Consentire un dominio senza autenticazione
sudo ats-ctl whitelist add github.com
# Output atteso: [OK] whitelist added: github.com

sudo ats-ctl whitelist add ubuntu.com

# Rimuovere
sudo ats-ctl whitelist remove github.com
# Output atteso: [OK] whitelist removed if present: github.com

# Applicare
sudo ats-ctl reload

# Vedere la lista corrente
cat /etc/trafficserver/plugin/whitelist.list
```

**Test in modo whitelist**:

```bash
sudo ats-ctl mode whitelist && sudo ats-ctl reload

# Dominio whitelistato — deve passare
curl -x http://127.0.0.1:8080 http://example.com -I
# Output atteso: HTTP/1.1 200 OK o 301

# Dominio NON whitelistato — deve essere bloccato
curl -x http://127.0.0.1:8080 http://iana.org -I
# Output atteso: HTTP/1.1 403 Forbidden
```

### 3.4 Gestione utenti e auth

Le password **non sono mai salvate in chiaro**. `ats-ctl user add` genera un salt
casuale (8 byte hex) e salva `salt$sha256(salt+password)`.

```bash
# Aggiungere un utente (password chiesta in modo sicuro, no echo)
sudo ats-ctl user add mario.rossi
# Password: ******  (digitare, non si vede)
# Output atteso: [OK] user configured: mario.rossi

# Aggiungere utente con password su riga comando (solo per automazione)
sudo ats-ctl user add mario.rossi 'SuaPassword123'

# Rimuovere un utente
sudo ats-ctl user remove mario.rossi
# Output atteso: [OK] user removed if present: mario.rossi

# Applicare
sudo ats-ctl reload

# Lista utenti (mostra solo nomi, non hash)
grep '^USER ' /etc/trafficserver/plugin/auth.conf
# Output esempio:
# USER admin 3f8a2c1b$9d4e1f...
# USER mario.rossi a1b2c3d4$7f6e5d...
```

**Test auth**:

```bash
# Senza credenziali — deve chiedere auth
curl -x http://127.0.0.1:8080 http://example.com -I
# Output atteso: HTTP/1.1 407 Proxy Authentication Required

# Con credenziali valide
curl -x http://127.0.0.1:8080 --proxy-user mario.rossi:'SuaPassword123' \
  http://example.com -I
# Output atteso: HTTP/1.1 200 OK
```

**File auth.conf formato**:

```
USER <nome> <salt>$<sha256>
```

### 3.5 Gestione admin IP

Un IP in admin list **bypassa ogni regola**: deny, whitelist e auth non si applicano.
Usare solo per postazioni amministrative fidate.

```bash
# Aggiungere IP admin
sudo ats-ctl admin add 192.168.89.10
# Output atteso: [OK] admin added: 192.168.89.10

# Rimuovere
sudo ats-ctl admin remove 192.168.89.10
# Output atteso: [OK] admin removed if present: 192.168.89.10

# Applicare
sudo ats-ctl reload

# Lista corrente
cat /etc/trafficserver/plugin/admin.list
```

### 3.6 Cambio modalita

```bash
# Modo consigliato: deny + auth per il resto
sudo ats-ctl mode auth_nd

# Solo blocco, nessuna auth
sudo ats-ctl mode deny

# Solo whitelist, tutto il resto bloccato
sudo ats-ctl mode whitelist

# Auth obbligatoria per tutto
sudo ats-ctl mode auth_all

# Plugin spento (debug/manutenzione)
sudo ats-ctl mode off

# Ogni cambio modo richiede reload
sudo ats-ctl reload
```

**Output atteso per cambio modo**:
```
[OK] MODE=auth_nd
```

### 3.7 Stato policy

```bash
sudo ats-ctl status
```

**Output esempio**:
```
[STEP] Config dir: /etc/trafficserver/plugin
MODE auth_nd
deny: 12
whitelist: 5
admin: 2
users: 8
```

### 3.8 Riavvio dopo modifiche

`ats-ctl reload` esegue il restart di ATS. Equivale a:

```bash
# Se disponibile il binario compilato
/opt/trafficserver/bin/trafficserver restart

# Altrimenti via systemd
sudo systemctl restart trafficserver
```

Non serve `reload` dopo `status`. Serve dopo: `mode`, `deny add/remove`,
`whitelist add/remove`, `admin add/remove`, `user add/remove`.

### 3.9 File di configurazione

**Directory**: `/etc/trafficserver/plugin/` (creata da `ats-ctl init`)

| File | Contenuto | Formato |
|---|---|---|
| `filter.conf` | `MODE <modo>` + `INCLUDE` | Una riga per direttiva |
| `deny.list` | Domini bloccati (regex supportate) | Un dominio per riga |
| `whitelist.list` | Domini consentiti | Un dominio per riga |
| `admin.list` | IP che bypassano tutto | Un IP per riga |
| `auth.conf` | Utenti e password hashate | `USER <nome> <hash>` |

**Permessi corretti**:

```bash
# Directory
drwxr-x--- 2 root trafficserver 4096 /etc/trafficserver/plugin/

# File
-rw-r----- 1 root trafficserver 1234 /etc/trafficserver/plugin/filter.conf
-rw-r----- 1 root trafficserver  256 /etc/trafficserver/plugin/deny.list
-rw-r----- 1 root trafficserver  128 /etc/trafficserver/plugin/whitelist.list
-rw-r----- 1 root trafficserver   64 /etc/trafficserver/plugin/admin.list
-rw-r----- 1 root trafficserver  512 /etc/trafficserver/plugin/auth.conf
```

**Inizializzazione** (se i file mancano):

```bash
sudo ats-ctl init
# Output atteso: [OK] Config initialized in /etc/trafficserver/plugin
```

Copia i file `.example` da `config/` nella directory di installazione.
Non sovrascrive file esistenti.

**ATTENZIONE**: non modificare i file a mano con `sudoedit` senza poi eseguire
`ats-ctl reload`. `ats-ctl` si occupa di permessi e proprietario automaticamente.

### 3.10 Test automatici (ats-mode-test.sh)

Il test automatico verifica ogni modo con richieste HTTP reali e confronta
il codice di risposta atteso.

```bash
# Sintassi
sudo ATS_PROXY_CONFIG_DIR=/etc/trafficserver/plugin \
  bash scripts/ats-mode-test.sh <modo> <porta> <utente> '<password>'

# Esempio: test del modo auth_nd
sudo ATS_PROXY_CONFIG_DIR=/etc/trafficserver/plugin \
  bash scripts/ats-mode-test.sh auth_nd 8080 admin 'testpass'
```

**Output atteso per `auth_nd`**:
```
[STEP] Testing plugin MODE=auth_nd on http://127.0.0.1:8080
[OK] AUTH_ND: deny before auth -> 403              403
[OK] AUTH_ND: whitelist bypasses auth              200
[OK] AUTH_ND: other host needs auth                407
[STEP] Passed=3 Failed=0
```

**Test per ogni modo**:

```bash
# off: tutto passa
sudo bash scripts/ats-mode-test.sh off 8080 admin 'testpass'

# deny: solo domini in deny list bloccati
sudo bash scripts/ats-mode-test.sh deny 8080 admin 'testpass'

# whitelist: solo whitelist passa
sudo bash scripts/ats-mode-test.sh whitelist 8080 admin 'testpass'

# auth_all: auth obbligatoria per tutto
sudo bash scripts/ats-mode-test.sh auth_all 8080 admin 'testpass'

# auth_nd: deny vince, whitelist bypassa, resto chiede auth
sudo bash scripts/ats-mode-test.sh auth_nd 8080 admin 'testpass'
```

Il test modifica temporaneamente la policy. Dopo il test, ripristinare il modo
desiderato:

```bash
sudo ats-ctl mode auth_nd && sudo ats-ctl reload
```

---

## 4. Troubleshooting

### 4.1 Proxy non risponde (HTTP 000)

**Sintomo**: `curl` restituisce `000`, timeout, o "connection refused".

**Cause probabili**:
1. Servizio ATS fermo
2. Porta sbagliata o occupata
3. Firewall blocca la porta
4. ATS in crash loop

**Diagnostica**:

```bash
# Passo 1: il servizio e attivo?
sudo systemctl status trafficserver | head -3
# Output atteso: Active: active (running) since ...

# Passo 2: la porta e in ascolto?
sudo ss -tlnp | grep 8080
# Output atteso: LISTEN  0  128  *:8080  *:*  users:(("traffic_server",...

# Passo 3: test locale
curl -v -x http://127.0.0.1:8080 http://example.com 2>&1 | head -20

# Passo 4: errori recenti nei log
sudo tail -50 /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log
```

**Soluzione**:

```bash
# Riavvia il servizio
sudo systemctl restart trafficserver

# Se non si avvia, controlla i log di sistema
sudo journalctl -u trafficserver -n 50 --no-pager

# Verifica che la porta non sia occupata
sudo lsof -i :8080
```

### 4.2 Auth fallita (407)

**Sintomo**: il client riceve `407 Proxy Authentication Required` ma l'utente
ha inserito credenziali.

**Cause probabili**:
1. Password sbagliata
2. Utente non esiste
3. Il client non invia l'header `Proxy-Authorization`
4. Modo `off` o `deny` attivo (la richiesta e bloccata per altro motivo)

**Diagnostica**:

```bash
# Passo 1: l'utente esiste?
grep "^USER mar.rossi" /etc/trafficserver/plugin/auth.conf
# Se vuoto: utente non esiste

# Passo 2: tentativi falliti nei log
sudo grep 'AUTH FAIL' /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -10
# Cerca l'IP del client per risalire all'utente

# Passo 3: qual e il modo attuale?
sudo ats-ctl status | grep MODE

# Passo 4: test con credenziali esplicite
curl -v -x http://192.168.89.37:8080 \
  --proxy-user mario.rossi:'password' http://example.com 2>&1 | head -30
```

**Soluzione**:

```bash
# Reset password (rimuovi e riaggiungi)
sudo ats-ctl user remove mario.rossi
sudo ats-ctl user add mario.rossi   # inserisci nuova password
sudo ats-ctl reload

# Verifica che il client invii le credenziali:
# - Browser: deve apparire la finestra di login. Se non appare,
#   il client non sta configurando il proxy correttamente.
# - CLI: export http_proxy=http://utente:password@proxy:8080
```

### 4.3 Dominio bloccato (403)

**Sintomo**: il client riceve `403 Forbidden` su un dominio che dovrebbe
essere accessibile.

**Cause probabili**:
1. Il dominio e nella deny list
2. Modo `whitelist` attivo e il dominio non e in whitelist
3. Regex nella deny list troppo ampia

**Diagnostica**:

```bash
# Passo 1: il dominio e in deny?
grep -i "dominio-segnalato" /etc/trafficserver/plugin/deny.list

# Passo 2: il modo e whitelist?
sudo ats-ctl status | grep MODE

# Passo 3: se whitelist, il dominio e nella lista?
grep -i "dominio-segnalato" /etc/trafficserver/plugin/whitelist.list

# Passo 4: il plugin ha registrato un DENY?
sudo grep 'DENY.*dominio' /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -5
```

**Soluzione**:

```bash
# Rimuovere dalla deny list
sudo ats-ctl deny remove dominio-segnalato
sudo ats-ctl reload

# Aggiungere alla whitelist (se in modo whitelist)
sudo ats-ctl whitelist add dominio-segnalato
sudo ats-ctl reload

# Se il dominio e legittimo ma bloccato da regex, rimuovi la regex:
sudo ats-ctl deny remove '.*\.ru$'
sudo ats-ctl reload
```

### 4.4 Proxy lento

**Sintomo**: navigazione rallentata, timeout frequenti.

**Cause probabili**:
1. Cache piena (spazio disco esaurito)
2. RAM satura
3. CPU al 100%
4. DNS lento
5. Troppe connessioni client

**Diagnostica**:

```bash
# Passo 1: spazio disco
df -h / /opt/trafficserver
# Se >90%, pulire cache/log

# Passo 2: RAM
free -h

# Passo 3: CPU e connessioni
/opt/trafficserver/bin/traffic_top
# Osserva: cache hit rate, connessioni attive, throughput

# Passo 4: metriche connessioni
/opt/trafficserver/bin/traffic_ctl metric get \
  proxy.process.http.current_client_connections
```

**Soluzione**:

```bash
# Pulizia cache ATS
sudo /opt/trafficserver/bin/traffic_server -C clear_cache
# Riavvia
sudo systemctl restart trafficserver

# Se RAM/CPU satura, verificare limiti systemd
systemctl show trafficserver | grep -E 'Memory|CPU'

# Ultima risorsa: riavvia ATS
sudo systemctl restart trafficserver
```

### 4.5 Plugin non caricato

**Sintomo**: il proxy funziona ma non applica nessuna policy (tutto passa).

**Cause probabili**:
1. Plugin non dichiarato in `plugin.config`
2. File `.so` mancante o permessi errati
3. Errore di compilazione (versione ATS incompatibile)
4. Modo `off` attivo

**Diagnostica**:

```bash
# Passo 1: il plugin e in plugin.config?
cat /etc/trafficserver/plugin.config
# Deve contenere: ats_proxy_filter.so /etc/trafficserver/plugin/filter.conf

# Passo 2: il file .so esiste?
ls -la /opt/trafficserver/libexec/trafficserver/ats_proxy_filter*.so

# Passo 3: errori di caricamento nei log
sudo grep -i 'plugin\|ats_proxy' /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | tail -20

# Passo 4: modo corrente
sudo ats-ctl status | grep MODE
# Se "off", il plugin e caricato ma trasparente
```

**Soluzione**:

```bash
# Aggiungere il plugin a plugin.config (se manca)
echo 'ats_proxy_filter.so /etc/trafficserver/plugin/filter.conf' | \
  sudo tee -a /etc/trafficserver/plugin.config

# Verificare permessi
sudo chmod 0755 /opt/trafficserver/libexec/trafficserver/ats_proxy_filter*.so

# Riavviare
sudo systemctl restart trafficserver

# Se ancora non caricato, verificare compatibilita ATS
/opt/trafficserver/bin/traffic_server -version
# Il plugin deve essere compilato per la stessa versione ATS
```

### 4.6 Spazio disco esaurito

**Sintomo**: proxy lento, errori nei log, richieste fallite.

**Diagnostica**:

```bash
# Spazio disco
df -h

# Cosa occupa spazio?
sudo du -sh /opt/trafficserver/var/
sudo du -sh /opt/trafficserver/var/trafficserver/log/
sudo du -sh /var/log/

# File grandi
sudo find /opt/trafficserver -type f -size +100M -exec ls -lh {} \;
```

**Soluzione**:

```bash
# Pulire log vecchi
sudo find /opt/trafficserver/var/trafficserver/log/ -name '*.log' -mtime +30 -delete

# Pulire cache ATS
sudo systemctl stop trafficserver
sudo rm -rf /opt/trafficserver/var/trafficserver/cache/*
sudo systemctl start trafficserver

# Logrotate (se non configurato)
cat <<'EOF' | sudo tee /etc/logrotate.d/ats-proxy
/opt/trafficserver/var/trafficserver/log/trafficserver/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    postrotate
        systemctl reload trafficserver >/dev/null 2>&1 || true
    endscript
}
EOF
```

### 4.7 Permessi config errati

**Sintomo**: ATS non si avvia, plugin non legge i file, errori "Permission denied"
nei log.

**Diagnostica**:

```bash
# Verifica permessi directory
ls -la /etc/trafficserver/plugin/
ls -la /opt/trafficserver/etc/trafficserver/

# Verifica proprietario e gruppo
stat /etc/trafficserver/plugin/filter.conf
```

**Soluzione**:

```bash
# Ripristinare permessi corretti
sudo chown -R root:trafficserver /etc/trafficserver/plugin/
sudo chmod 0750 /etc/trafficserver/plugin/
sudo chmod 0640 /etc/trafficserver/plugin/*
sudo chown -R root:trafficserver /opt/trafficserver/etc/trafficserver/
sudo chmod 0640 /opt/trafficserver/etc/trafficserver/*

# Reinizializzare se i file sono corrotti
sudo ats-ctl init
sudo ats-ctl reload
```

---

## 5. Configurazione client

**Dati server di esempio** (sostituire con i valori reali):
- IP proxy: `192.168.89.37`
- Porta: `8080`
- Utente: `mario.rossi`
- Password: la password assegnata

### 5.1 Windows

1. Apri **Impostazioni** → **Rete e Internet** → **Proxy**.
2. Attiva **Usa server proxy**.
3. Indirizzo: `192.168.89.37`
4. Porta: `8080`
5. Salva.
6. Se il modo e `auth_all` o `auth_nd`, la prima volta che apri il browser
   apparira una finestra di login. Inserisci username e password.

**Firefox** (se non usa le impostazioni di sistema):
1. Opzioni → Generale → **Impostazioni di rete** → **Proxy**.
2. Configurazione manuale.
3. HTTP Proxy: `192.168.89.37`, Porta: `8080`.
4. Attiva **Usa questo proxy anche per HTTPS**.

### 5.2 Linux (GNOME e riga di comando)

**GNOME**:
1. Impostazioni → Rete → Proxy.
2. Metodo: **Manuale**.
3. HTTP Proxy: `192.168.89.37`, Porta: `8080`.
4. HTTPS Proxy: `192.168.89.37`, Porta: `8080`.

**Riga di comando** (senza auth):

```bash
export http_proxy=http://192.168.89.37:8080
export https_proxy=http://192.168.89.37:8080
curl http://example.com
```

**Riga di comando** (con auth):

```bash
export http_proxy=http://utente:password@192.168.89.37:8080
export https_proxy=http://utente:password@192.168.89.37:8080
curl http://example.com
```

**Permanente** (aggiungere a `~/.bashrc` o `/etc/environment`):

```bash
# /etc/environment (senza auth, system-wide)
http_proxy=http://192.168.89.37:8080
https_proxy=http://192.168.89.37:8080
```

**APT** (se il server deve scaricare pacchetti via proxy):

```bash
# /etc/apt/apt.conf.d/95proxy
Acquire::http::Proxy "http://192.168.89.37:8080";
Acquire::https::Proxy "http://192.168.89.37:8080";
```

### 5.3 Browser (Firefox)

1. Apri Firefox.
2. Menu → Impostazioni → Generale → scorri fino a **Impostazioni di rete**.
3. Clicca **Impostazioni**.
4. Seleziona **Configurazione manuale del proxy**.
5. HTTP Proxy: `192.168.89.37`, Porta: `8080`.
6. Attiva **Usa questo proxy anche per HTTPS**.
7. OK e Salva.
8. Se richiesto, inserisci username e password al primo accesso web.

---

## 6. Backup e Restore

### Backup

```bash
# Backup completo (config ATS + config plugin + unita systemd)
sudo tar -czf ats-backup-$(date +%Y%m%d).tar.gz \
  /opt/trafficserver/etc \
  /etc/trafficserver/plugin \
  /etc/systemd/system/trafficserver.service

# Se ATS9 da pacchetto, includere anche:
sudo tar -czf ats-backup-$(date +%Y%m%d).tar.gz \
  /etc/trafficserver \
  /etc/trafficserver/plugin \
  /etc/systemd/system/trafficserver.service
```

**Copia su host remoto**:

```bash
scp ats-backup-$(date +%Y%m%d).tar.gz utente@backup-host:/backup/
```

**Backup automatico giornaliero** (cron):

```bash
# Aggiungere a crontab
sudo crontab -e
# Inserire:
# 0 3 * * * tar -czf /backup/ats-backup-$(date +\%Y\%m\%d).tar.gz /opt/trafficserver/etc /etc/trafficserver/plugin /etc/systemd/system/trafficserver.service
```

### Restore

```bash
# Fermare il servizio
sudo systemctl stop trafficserver

# Ripristinare i file
sudo tar -xzf ats-backup-YYYYMMDD.tar.gz -C /

# Verificare permessi
sudo chown -R root:trafficserver /etc/trafficserver/plugin/
sudo chmod 0750 /etc/trafficserver/plugin/
sudo chmod 0640 /etc/trafficserver/plugin/*

# Riavviare
sudo systemctl start trafficserver

# Verificare
sudo ats-ctl status
curl -x http://127.0.0.1:8080 http://example.com -I
```

**ATTENZIONE**: il backup non include il file `.so` del plugin (in
`/opt/trafficserver/libexec/trafficserver/`). Dopo un restore su hardware
nuovo, il plugin va ricompilato. Il backup copre solo la configurazione.

---

## 7. Manutenzione periodica (checklist mensile)

Eseguire una volta al mese. Tempo stimato: 10 minuti.

```bash
# === 1. Aggiornamenti di sicurezza ===
sudo apt update && sudo apt upgrade -y
# Verificare che unattended-upgrades sia attivo
systemctl status unattended-upgrades | head -3

# === 2. Hardening check ===
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080
# Deve dare: Passed: 25  Failed: 0  Warnings: 0

# === 3. Stato servizio ===
sudo systemctl status trafficserver | head -3
# Atteso: Active: active (running)

# === 4. Stato policy ===
sudo ats-ctl status
# Verificare che MODE sia quello atteso

# === 5. Spazio disco ===
df -h | grep -E 'Filesystem|/$|traffic'
# Se >80%, pianificare pulizia

# === 6. RAM disponibile ===
free -h | grep Mem

# === 7. Security audit log ===
# Errori e auth fallite nell'ultimo mese
sudo grep -i 'error\|fail' /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log \
  | grep "$(date -d '30 days ago' +%Y%m%d)" | wc -l
sudo grep 'AUTH FAIL' /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | wc -l
sudo grep 'ADMIN bypass' /opt/trafficserver/var/trafficserver/log/trafficserver/diags.log | wc -l

# === 8. Report diagnostico ===
sudo bash scripts/ats-version-report.sh > ats-report-$(date +%Y%m%d).txt

# === 9. Backup configurazione ===
sudo tar -czf ats-backup-$(date +%Y%m%d).tar.gz \
  /opt/trafficserver/etc /etc/trafficserver/plugin \
  /etc/systemd/system/trafficserver.service

# === 10. Test policy per i modi in uso ===
for mode in off deny auth_nd; do
  sudo ATS_PROXY_CONFIG_DIR=/etc/trafficserver/plugin \
    bash scripts/ats-mode-test.sh "$mode" 8080 admin '<password>'
done

# === 11. Rotazione log ===
sudo logrotate -f /etc/logrotate.d/ats-proxy 2>/dev/null || true

# === 12. CVE check ===
sudo /opt/cve-check.sh 2>/dev/null || echo "CVE helper non installato"
```

**Valori di attenzione**:
- `AUTH FAIL > 50/mese`: possibile attacco brute-force o utenti che dimenticano
  la password — verificare fail2ban
- `ADMIN bypass > 0`: normale se ci sono IP admin configurati; investigare se
  ci sono IP sconosciuti
- `error > 100/mese`: investigare i log per la causa
- Spazio disco >80%: pianificare pulizia cache e log
- Test hardening con `Failed > 0`: correggere immediatamente

---

## 8. Riferimento comandi completo

| Comando | Descrizione |
|---|---|
| `ats-ctl` | CLI gestione plugin (da `/usr/local/bin/ats-ctl`) |
| `ats-ctl admin add <ip>` | Aggiungi IP che bypassa ogni regola |
| `ats-ctl admin remove <ip>` | Rimuovi IP admin |
| `ats-ctl deny add <dominio>` | Aggiungi dominio alla deny list |
| `ats-ctl deny remove <dominio>` | Rimuovi dominio dalla deny list |
| `ats-ctl help` | Mostra help |
| `ats-ctl init` | Inizializza file config se mancanti |
| `ats-ctl mode <off\|deny\|whitelist\|auth_all\|auth_nd>` | Cambia modalita operativa |
| `ats-ctl reload` | Applica modifiche e riavvia ATS |
| `ats-ctl status` | Mostra stato policy (MODE, conteggi) |
| `ats-ctl user add <nome> [password]` | Crea utente (password chiesta se omessa) |
| `ats-ctl user remove <nome>` | Rimuovi utente |
| `ats-ctl whitelist add <dominio>` | Aggiungi dominio alla whitelist |
| `ats-ctl whitelist remove <dominio>` | Rimuovi dominio dalla whitelist |
| `bash scripts/ats-hardening-check.sh <porta>` | Verifica hardening |
| `bash scripts/ats-mode-test.sh <modo> <porta> <utente> <pass>` | Test automatico policy |
| `bash scripts/ats-version-report.sh` | Report diagnostico completo |
| `cat /etc/trafficserver/plugin/admin.list` | Mostra IP admin |
| `cat /etc/trafficserver/plugin/auth.conf` | Mostra file auth (contiene hash) |
| `cat /etc/trafficserver/plugin/deny.list` | Mostra domini bloccati |
| `cat /etc/trafficserver/plugin/filter.conf` | Mostra config principale plugin |
| `cat /etc/trafficserver/plugin/whitelist.list` | Mostra domini whitelist |
| `curl -x http://127.0.0.1:8080 http://example.com -I` | Test rapido proxy |
| `curl -x http://127.0.0.1:8080 --proxy-user u:p http://example.com -I` | Test proxy con auth |
| `df -h` | Spazio disco |
| `free -h` | RAM disponibile |
| `grep '^USER ' /etc/trafficserver/plugin/auth.conf` | Lista utenti (solo nomi) |
| `journalctl -u trafficserver -n 50 --no-pager` | Log systemd ultime 50 righe |
| `man ats-ctl` | Man page di ats-ctl |
| `man ats-proxy-filter` | Man page del plugin |
| `scp ats-backup-*.tar.gz utente@host:/backup/` | Copia backup remoto |
| `ss -tlnp \| grep 8080` | Verifica porta in ascolto |
| `sudo crontab -l \| grep ats_health` | Verifica health check automatico |
| `sudo grep AUTH\ FAIL /var/.../diags.log` | Vedi auth fallite |
| `sudo grep DENY /var/.../diags.log` | Vedi domini bloccati |
| `sudo grep ats_proxy_filter /var/.../diags.log` | Vedi log del plugin |
| `sudo systemctl enable trafficserver` | Abilita ATS al boot |
| `sudo systemctl restart trafficserver` | Riavvia ATS |
| `sudo systemctl start trafficserver` | Avvia ATS |
| `sudo systemctl status trafficserver` | Stato ATS |
| `sudo systemctl stop trafficserver` | Ferma ATS |
| `sudo tail -f /var/lib/.../diags.log` | Segui log diagnostici in tempo reale |
| `sudo tar -czf ats-backup-$(date +%Y%m%d).tar.gz ...` | Crea backup |
| `sudo tar -xzf ats-backup-YYYYMMDD.tar.gz -C /` | Ripristina backup |
| `/opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.current_client_connections` | Connessioni attive |
| `/opt/trafficserver/bin/traffic_server -C verify_config` | Verifica sintassi config |
| `/opt/trafficserver/bin/traffic_server -version` | Versione ATS |
| `/opt/trafficserver/bin/traffic_top` | Dashboard real-time |

---

## Appendice A: Percorsi rapidi

| Risorsa | Path |
|---|---|
| Config ATS | `/opt/trafficserver/etc/trafficserver/` (o `/opt/trafficserver/etc/trafficserver/`) |
| Log ATS | `/opt/trafficserver/var/trafficserver/log/trafficserver/` (o `/opt/trafficserver/var/log/trafficserver/`) |
| Config plugin | `/etc/trafficserver/plugin/` |
| Binari ATS | `/opt/trafficserver/bin/` |
| Plugin `.so` | `/opt/trafficserver/libexec/trafficserver/ats_proxy_filter*.so` |
| Unita systemd | `/etc/systemd/system/trafficserver.service` |
| Health check log | `/var/log/ats-health.log` |
| `ats-ctl` binario | `/usr/local/bin/ats-ctl` |
| `ats-ctl` source | `scripts/ats-ctl` (nella directory del repository) |
| Script hardening | `scripts/ats-hardening-check.sh` |
| Script report | `scripts/ats-version-report.sh` |
| Script test policy | `scripts/ats-mode-test.sh` |
| Man page ats-ctl | `man ats-ctl` |
| Man page plugin | `man ats-proxy-filter` |

---

## Appendice B: Interni del plugin (per riferimento)

- **Hook**: `TS_HTTP_OS_DNS_HOOK` — intercetta ogni richiesta dopo risoluzione DNS.
  Legge l'host e decide: continuare (`TS_HTTP_TXN_CLIENT_CONNECT_HOOK`),
  bloccare con `403`, o chiedere auth con `407` (`TS_HTTP_SEND_RESPONSE_HDR_HOOK`
  per impostare header `Proxy-Authenticate`).
- **Hashing password**: salt casuale 8 byte hex + SHA-256. Confronto a tempo
  costante per prevenire timing attack.
- **Admin IP**: controllato prima di ogni altra regola. Se l'IP sorgente matcha
  `admin.list`, la richiesta passa senza ulteriori verifiche.

---

## Appendice C: Upgrade plugin dopo cambio versione ATS

```bash
cd /percorso/ats-proxy
git pull

# Ricompila per la nuova versione ATS
bash scripts/compile-plugin.sh \
  --ats-src /tmp/trafficserver-10.X.Y \
  --out bin/ats_proxy_filter_v30.so --cxx

# Installa il nuovo .so
sudo cp bin/ats_proxy_filter_v30.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so

# Riavvia
sudo systemctl restart trafficserver

# Testa ogni modo usato
for mode in off deny auth_nd; do
  sudo ATS_PROXY_CONFIG_DIR=/etc/trafficserver/plugin \
    bash scripts/ats-mode-test.sh "$mode" 8080 admin '<password>'
done

# Verifica hardening
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080
```
