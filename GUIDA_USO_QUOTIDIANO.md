# Guida Uso Quotidiano — ATS Proxy Enterprise v3.0

## Checklist giornaliera (2 minuti)

```bash
# 1. Il servizio e attivo?
systemctl status trafficserver | head -3

# 2. L'ultima richiesta e stata processata?
sudo tail -1 /var/log/trafficserver/diags.log

# 3. Hardening ancora integro? (eseguire una volta a settimana)
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash /opt/ats-proxy/scripts/ats-hardening-check.sh 8080
# Deve dare: Passed: 25  Failed: 0  Warnings: 0
```

## Gestione domini bloccati

```bash
# Bloccare un dominio (es. social network)
sudo ats-ctl deny add facebook.com
sudo ats-ctl deny add instagram.com
sudo ats-ctl reload

# Bloccare tutti i domini di un paese (es. .ru)
sudo ats-ctl deny add '.*\.ru$'
sudo ats-ctl reload

# Rimuovere un blocco
sudo ats-ctl deny remove facebook.com
sudo ats-ctl reload

# Vedere la lista corrente
cat /etc/ats-proxy/deny.list
```

## Gestione domini consentiti (whitelist)

```bash
# Consentire un dominio senza autenticazione
sudo ats-ctl whitelist add github.com
sudo ats-ctl whitelist add ubuntu.com
sudo ats-ctl reload

# Rimuovere
sudo ats-ctl whitelist remove github.com
sudo ats-ctl reload

# Lista corrente
cat /etc/ats-proxy/whitelist.list
```

## Gestione utenti

```bash
# Aggiungere un utente (la password viene chiesta, non salvarla in chiaro)
sudo ats-ctl user add mario.rossi
# Password: ******

# Rimuovere un utente
sudo ats-ctl user remove mario.rossi
sudo ats-ctl reload

# Lista utenti (mostra solo i nomi, non le password)
grep '^USER ' /etc/ats-proxy/auth.conf
```

> **Nota**: le password sono salvate come `salt$sha256(salt+password)`.
> Anche con accesso root al server, un attaccante non legge la password in chiaro.

## Gestione IP admin (bypass totale)

```bash
# Aggiungere un IP che bypassa tutte le regole
sudo ats-ctl admin add 192.168.89.10
sudo ats-ctl reload

# Rimuovere
sudo ats-ctl admin remove 192.168.89.10
sudo ats-ctl reload
```

> **Attenzione**: un IP admin puo navigare ovunque senza autenticazione.
> Usare solo per postazioni amministrative fidate.

## Cambiare modalita operativa

```bash
# Modalita consigliata: deny blocca, whitelist passa, il resto chiede auth
sudo ats-ctl mode auth_nd

# Solo blocco, nessuna auth
sudo ats-ctl mode deny

# Solo whitelist, tutto il resto bloccato
sudo ats-ctl mode whitelist

# Auth obbligatoria per tutto
sudo ats-ctl mode auth_all

# Plugin spento (debug/manutenzione)
sudo ats-ctl mode off

sudo ats-ctl reload
```

## Vedere lo stato attuale

```bash
sudo ats-ctl status
```

Output esempio:
```
Config dir: /etc/ats-proxy
MODE auth_nd
deny: 12
whitelist: 5
admin: 2
users: 8
```

## Cosa fare quando...

### Un utente dice "Internet non funziona"

```bash
# Passo 1: il proxy risponde?
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
# Atteso: 200

# Passo 2: il dominio e bloccato?
grep -i "dominio-segnalato" /etc/ats-proxy/deny.list
# Se presente, rimuovilo con: sudo ats-ctl deny remove dominio

# Passo 3: l'utente ha credenziali?
grep "^USER utente" /etc/ats-proxy/auth.conf
# Se assente, crealo: sudo ats-ctl user add utente

# Passo 4: controlla i log per l'IP del cliente
sudo grep "192.168.89.XX" /var/log/trafficserver/diags.log | tail -20
# Cerca "AUTH FAIL" (password sbagliata), "DENY" (dominio bloccato), "407" (auth mancante)
```

### Il proxy e lento

```bash
# Guarda metriche in tempo reale
/opt/trafficserver/bin/traffic_top

# Controlla spazio disco (cache piena?)
df -h /opt/trafficserver

# Controlla RAM
free -h

# Riavvia (ultima risorsa)
sudo systemctl restart trafficserver
```

### Devo aggiornare il plugin

```bash
cd /percorso/ats-proxy
git pull

# Ricompila
bash scripts/compile-plugin.sh \
  --ats-src /tmp/trafficserver-10.1.2 \
  --out bin/ats_proxy_filter_v30.so --cxx

# Sostituisci e riavvia
sudo cp bin/ats_proxy_filter_v30.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so
sudo systemctl restart trafficserver

# Verifica
for mode in off deny auth_nd; do
  sudo ATS_PROXY_CONFIG_DIR=/etc/ats-proxy \
    ATS_PROXY_TEMPLATE_DIR=$(pwd)/config \
    bash scripts/ats-mode-test.sh "$mode" 8080 admin testpass
done
```

### Devo aggiornare ATS

Vedi `GUIDA_INSTALLAZIONE_ATS_LTS.md`, sezione "Upgrade futuro".

## Backup e restore

### Backup

```bash
# Backup completo
sudo tar -czf ats-backup-$(date +%Y%m%d).tar.gz \
  /opt/trafficserver/etc \
  /etc/ats-proxy \
  /etc/systemd/system/trafficserver.service

# Copia su un altro host
scp ats-backup-$(date +%Y%m%d).tar.gz utente@backup-host:/backup/
```

### Restore

```bash
sudo systemctl stop trafficserver
sudo tar -xzf ats-backup-YYYYMMDD.tar.gz -C /
sudo systemctl start trafficserver
```

## Log: cosa cercare

```bash
# Errori recenti
sudo grep -i 'error\|fail\|alert' \
  /var/log/trafficserver/diags.log | tail -20

# Tentativi di auth falliti
sudo grep 'AUTH FAIL' \
  /var/log/trafficserver/diags.log | tail -20

# Domini bloccati oggi
sudo grep 'DENY' \
  /var/log/trafficserver/diags.log | tail -20

# Richieste processate (audit log)
sudo tail -50 /var/log/trafficserver/audit.log

# Chi ha usato il bypass admin
sudo grep 'ADMIN bypass' \
  /var/log/trafficserver/diags.log | tail -10
```

## Configurare i client

### Windows

1. Impostazioni → Rete e Internet → Proxy.
2. Attiva "Usa server proxy".
3. Indirizzo: `192.168.89.37` (IP del server proxy).
4. Porta: `8080`.
5. Se usi `auth_all` o `auth_nd`, il browser chiedera username e password.

### Linux (GNOME)

1. Impostazioni → Rete → Proxy.
2. Metodo: Manuale.
3. HTTP Proxy: `192.168.89.37`, Porta: `8080`.

### Linux (riga di comando)

```bash
export http_proxy=http://utente:password@192.168.89.37:8080
export https_proxy=http://utente:password@192.168.89.37:8080
curl http://example.com
```

### Browser (Firefox)

1. Impostazioni → Generale → Impostazioni di rete → Proxy.
2. Configurazione manuale.
3. HTTP Proxy: `192.168.89.37`, Porta: `8080`.
4. Attiva "Usa questo proxy anche per HTTPS".

## Report diagnostico rapido

```bash
# Pronto per inviare al supporto
sudo bash ats-proxy/scripts/ats-version-report.sh
```

## Riferimenti rapidi

| Comando | Cosa fa |
|---|---|
| `sudo systemctl restart trafficserver` | Riavvia ATS |
| `sudo ats-ctl deny add dominio` | Blocca un dominio |
| `sudo ats-ctl whitelist add dominio` | Consenti senza auth |
| `sudo ats-ctl user add nome` | Crea utente |
| `sudo ats-ctl mode auth_nd` | Attiva modo consigliato |
| `sudo ats-ctl status` | Mostra stato policy |
| `sudo ats-ctl reload` | Applica modifiche e riavvia ATS |
| `sudo grep DENY /opt/...diags.log` | Vedi domini bloccati |
| `sudo grep AUTH.FAIL /opt/...diags.log` | Vedi auth fallite |
| `/opt/trafficserver/bin/traffic_top` | Metriche in tempo reale |
