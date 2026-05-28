# Keepalived HA per ATS Proxy — Guida di Installazione

## Ubuntu 24.04 LTS (Noble) e 26.04 LTS (Resolute Raccoon)

**Versione 1.1 — 28 Maggio 2026**

---

## Prima di iniziare

- Due (o piu) VM ATS funzionanti. Riferimento: [GUIDA_INSTALLAZIONE.md](../GUIDA_INSTALLAZIONE.md) o [GUIDA_INSTALLAZIONE_ATS_LTS.md](../GUIDA_INSTALLAZIONE_ATS_LTS.md).
- IP statici configurati su entrambe le VM via **netplan**. Vedi [GUIDA_NETPLAN_IP.md](./GUIDA_NETPLAN_IP.md) per la procedura dettagliata.
- Un IP virtuale (VIP) libero nella stessa subnet delle VM ATS.
- Accesso **sudo** su tutte le VM.
- Firewall configurato con il VIP come eccezione (se UFW attivo).

**Tempo stimato**: 15-20 minuti per nodo (esclusa configurazione IP/netplan).

---

## 0. Architettura

```
                    Client (192.168.1.0/24)
                           │
                    ┌──────┴──────┐
                    │   VIP: .99  │  ← IP virtuale gestito da keepalived
                    └──────┬──────┘
              ┌────────────┴────────────┐
              │ VRRP (MASTER/BACKUP)    │
              │                         │
     ┌────────▼────────┐     ┌─────────▼────────┐
     │  VM ATS-1 (.31) │     │  VM ATS-2 (.32)  │
     │  MASTER         │     │  BACKUP          │
     │  priority 100   │     │  priority 50     │
     └─────────────────┘     └──────────────────┘
```

| Componente | Ruolo |
|-----------|-------|
| **VIP** | IP condiviso. I client puntano sempre a questo. |
| **keepalived** | Gestisce VRRP: elegge MASTER, sposta il VIP. |
| **vrrp_script** | Health check: se ATS muore, keepalived rilascia il VIP. |
| **VRRP** | Protocollo L2 (multicast 224.0.0.18): priorita + heartbeat. |
| **netplan** | Configurazione IP statica su ogni VM (prerequisito). |

**Regola**: il VIP segue la VM con priorita piu alta che ha ATS attivo.
Se il MASTER perde ATS, il VIP migra sul BACKUP in <3 secondi.

---

## — Preparazione IP Linux (netplan)

Prima di installare keepalived, ogni VM ATS deve avere un **IP statico**.
Su Ubuntu 24.04+ la configurazione di rete si fa con **netplan** (YAML in `/etc/netplan/`).

### Esempio netplan — VM ATS-1 (MASTER, IP .31)

```bash
# Scopri il nome file corrente
ls /etc/netplan/
# Tipicamente: 00-installer-config.yaml, 50-cloud-init.yaml, oppure 01-netcfg.yaml

# Crea/modifica il file (ESEMPIO — adatta alla tua rete)
sudo tee /etc/netplan/99-ats.yaml > /dev/null << 'EOF'
network:
  version: 2
  ethernets:
    eth0:                         # Sostituire con il nome dell'interfaccia reale
      dhcp4: false
      addresses:
        - 192.168.1.31/24         # IP statico della VM
      routes:
        - to: default
          via: 192.168.1.1        # Gateway della rete
      nameservers:
        addresses:
          - 1.1.1.1               # DNS primario
          - 8.8.8.8               # DNS secondario
EOF
```

### Esempio netplan — VM ATS-2 (BACKUP, IP .32)

Identico al MASTER, cambia solo `addresses`:

```bash
sudo tee /etc/netplan/99-ats.yaml > /dev/null << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.1.32/24         # IP statico del BACKUP
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
EOF
```

### ⚠️ IMPORTANTE — Prima di applicare netplan

```bash
# 1. Rimuovi eventuali file netplan in conflitto (es. quello di cloud-init)
ls /etc/netplan/
# Se esiste 50-cloud-init.yaml e NON lo usi, rinominalo:
sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.disabled

# 2. Verifica il nome dell'interfaccia
ip -br a | grep -v lo | awk '{print $1}'
# Output tipico: eth0, ens18, enp0s3, enX0, ...

# 3. Se il nome NON e eth0, correggi il file YAML sopra
sudo sed -i 's/eth0/ens18/g' /etc/netplan/99-ats.yaml   # esempio

# 4. Verifica la sintassi netplan (SENZA applicare)
sudo netplan try
# Premi INVIO se tutto ok, altrimenti aspetta 120s per il rollback automatico

# 5. Applica
sudo netplan apply
```

### ✅ Verifica IP dopo netplan

```bash
# L'IP statico deve comparire
ip addr show eth0 | grep "inet "
# Atteso: inet 192.168.1.31/24 ...

# Il gateway deve essere raggiungibile
ping -c 2 192.168.1.1

# DNS funziona
nslookup google.com 1.1.1.1
```

> **Nota**: il VIP (`192.168.1.99` nell'esempio) **non** va configurato in netplan.
> Viene gestito esclusivamente da keepalived. La VM lo aggiunge/rimuove dinamicamente.

Per una guida netplan completa con scenari multipli (cloud image, DHCP→statico, VLAN, bond),
vedi [GUIDA_NETPLAN_IP.md](./GUIDA_NETPLAN_IP.md).

---

## 1. Installazione Keepalived

Keepalived e nei repo ufficiali su entrambi gli OS.

```bash
sudo apt update
sudo apt install -y keepalived
```

**Verifica**: `keepalived --version` stampa `Keepalived v2.2.x` (o superiore).

> **Nota**: la versione da apt su 26.04 e piu recente (~2.3.x) ma l'API di configurazione e la stessa.
> Nessuna differenza nei file di configurazione tra 🔵 24.04 e 🟢 26.04.

---

## 2. Configurazione Health Check ATS

Keepalived deve sapere se ATS e vivo. Creiamo uno script di check.

### 2.1 Script `check_ats.sh`

```bash
sudo mkdir -p /etc/keepalived/scripts
sudo tee /etc/keepalived/scripts/check_ats.sh > /dev/null << 'SCRIPT'
#!/bin/bash
# keepalived health check per ATS proxy
# Restituisce 0 se ATS risponde sulla porta configurata, 1 altrimenti.

ATS_PORT="${ATS_PORT:-8080}"
ATS_HOST="${ATS_HOST:-127.0.0.1}"

# Verifica che traffic_server sia in esecuzione
if ! pgrep -x traffic_server > /dev/null; then
    exit 1
fi

# Verifica che ATS accetti connessioni TCP (forward proxy)
# curl con proxy e il modo piu affidabile per testare un forward proxy
if curl -x "http://${ATS_HOST}:${ATS_PORT}" --max-time 3 -s -o /dev/null -w "%{http_code}" \
    http://localhost:80 2>/dev/null | grep -q "200\|301\|302\|404"; then
    exit 0
else
    # Fallback: verifica che la porta sia in ascolto e che il processo sia attivo
    # (un forward proxy non risponde con 200 a una richiesta senza target)
    if ss -tlnp "sport = :${ATS_PORT}" | grep -q LISTEN; then
        exit 0
    fi
    exit 1
fi
SCRIPT
sudo chmod 755 /etc/keepalived/scripts/check_ats.sh
```

> **⚠️ Un forward proxy non risponde con 200 a `curl -x`.**
> Lo script usa una doppia verifica: prima tenta una richiesta via proxy,
> poi come fallback controlla che la porta sia in ascolto e `traffic_server` sia attivo.
> In produzione, adattare `ATS_PORT` alla porta effettiva del proxy (default 8080).

Variabili d'ambiente supportate dallo script:

| Variabile | Default | Scopo |
|-----------|---------|-------|
| `ATS_PORT` | `8080` | Porta su cui ATS accetta connessioni proxy |
| `ATS_HOST` | `127.0.0.1` | IP da contattare per il check locale |

---

## 3. Configurazione Keepalived

### 3.1 File `/etc/keepalived/keepalived.conf` — Nodo MASTER

```bash
sudo tee /etc/keepalived/keepalived.conf > /dev/null << 'EOF'
global_defs {
    router_id ATS-PROXY-01          # Unico per ogni nodo
    vrrp_skip_check_adv_addr        # Non verificare l'indirizzo di advertisement
    vrrp_garp_master_refresh 60     # Refresh gratuito ARP ogni 60s
    enable_script_security          # Protezione da injection negli script
}

# Health check: verifica che ATS sia vivo
vrrp_script chk_ats {
    script "/etc/keepalived/scripts/check_ats.sh"
    interval 3      # Controlla ogni 3 secondi
    weight -50      # Se fallisce, riduce priorita di 50
    fall 3          # Dichiarato DOWN dopo 3 check falliti
    rise 2          # Dichiarato UP dopo 2 check riusciti
}

vrrp_instance ATS_VIP {
    state MASTER                    # MASTER su questo nodo
    interface eth0                  # Sostituire con l'interfaccia reale
    virtual_router_id 51            # 0-255, unico per ogni VIP nella subnet
    priority 100                    # 100 = MASTER; il BACKUP avra 50
    advert_int 1                    # Heartbeat ogni 1 secondo

    # Autenticazione VRRP (opzionale ma raccomandata)
    authentication {
        auth_type PASS
        auth_pass ats_vrrp_secret   # Cambiare con una password propria
    }

    # VIP da gestire
    virtual_ipaddress {
        192.168.1.99/24 dev eth0    # Sostituire con IP/netmask e interfaccia reali
    }

    # Script di health check associato
    track_script {
        chk_ats
    }

    # Notifica cambio stato (opzionale ma utile per logging)
    notify_master "/usr/bin/logger -t keepalived 'ATS-01 promosso MASTER'"
    notify_backup "/usr/bin/logger -t keepalived 'ATS-01 degradato BACKUP'"
    notify_fault  "/usr/bin/logger -t keepalived 'ATS-01 in FAULT'"
}
EOF
```

### 3.2 File `/etc/keepalived/keepalived.conf` — Nodo BACKUP

Identico al MASTER, con **3 differenze chiave**:

```bash
sudo tee /etc/keepalived/keepalived.conf > /dev/null << 'EOF'
global_defs {
    router_id ATS-PROXY-02          # Diverso dal MASTER
    vrrp_skip_check_adv_addr
    vrrp_garp_master_refresh 60
    enable_script_security
}

vrrp_script chk_ats {
    script "/etc/keepalived/scripts/check_ats.sh"
    interval 3
    weight -50
    fall 3
    rise 2
}

vrrp_instance ATS_VIP {
    state BACKUP                    # BACKUP su questo nodo
    interface eth0
    virtual_router_id 51            # Stesso ID del MASTER — stessa famiglia VRRP
    priority 50                     # Piu bassa del MASTER
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass ats_vrrp_secret   # Stessa password del MASTER
    }

    virtual_ipaddress {
        192.168.1.99/24 dev eth0    # Stesso VIP
    }

    track_script {
        chk_ats
    }

    notify_master "/usr/bin/logger -t keepalived 'ATS-02 promosso MASTER'"
    notify_backup "/usr/bin/logger -t keepalived 'ATS-02 degradato BACKUP'"
    notify_fault  "/usr/bin/logger -t keepalived 'ATS-02 in FAULT'"
}
EOF
```

### 3.3 Differenze MASTER vs BACKUP — Riepilogo

| Parametro | MASTER | BACKUP |
|-----------|--------|--------|
| `router_id` | `ATS-PROXY-01` | `ATS-PROXY-02` |
| `state` | `MASTER` | `BACKUP` |
| `priority` | `100` | `50` |
| Notify log | riferimento a `ATS-01` | riferimento a `ATS-02` |

Tutti gli altri parametri (`virtual_router_id`, `auth_pass`, `virtual_ipaddress`, `track_script`) devono essere identici.

### 3.4 Parametri da Personalizzare

| Parametro | Default nella guida | Dove modificare |
|-----------|-------------------|-----------------|
| `interface` | `eth0` | Sostituire con `ip -br a` -> nome interfaccia reale |
| `virtual_ipaddress` | `192.168.1.99/24` | Sostituire con il VIP scelto |
| `auth_pass` | `ats_vrrp_secret` | Sostituire con una password forte (max 8 char VRRPv2) |
| `virtual_router_id` | `51` | Scegliere un ID libero nella subnet (0-255) |

```bash
# Scoprire l'interfaccia di rete
ip -br a | grep -v lo | awk '{print $1}'
# Output tipico: eth0 oppure ens18, enp0s3, ...
```

---

## 4. Avvio e Abilitazione

### 4.1 Su entrambi i nodi

```bash
# Verifica sintassi configurazione
sudo keepalived --dont-fork --log-console --check-config
# Atteso: "Configuration check completed" — poi Ctrl+C

# Riavvia e abilita all'avvio
sudo systemctl restart keepalived
sudo systemctl enable keepalived
```

### 4.2 Verifica immediata

```bash
# Stato del servizio
sudo systemctl status keepalived

# Verifica che il VIP sia assegnato sulla VM MASTER
ip addr show eth0 | grep 192.168.1.99
# Atteso: 192.168.1.99/24 scope global eth0

# Sulla VM BACKUP
ip addr show eth0 | grep 192.168.1.99
# Atteso: nessun output (il VIP non e assegnato)
```

> **✅ Se il VIP compare sul MASTER e non sul BACKUP, keepalived funziona.**

---

## 5. Test di Failover

### 5.1 Test 1 — Spegnimento ATS sul MASTER

```bash
# Sul MASTER: ferma ATS
sudo systemctl stop trafficserver

# Aspetta 3-5 secondi, poi sul BACKUP verifica
ip addr show eth0 | grep 192.168.1.99
# Atteso: il VIP deve essere migrato sul BACKUP
```

### 5.2 Test 2 — Riavvio ATS sul MASTER

```bash
# Sul MASTER: riavvia ATS
sudo systemctl start trafficserver

# Aspetta 3-5 secondi, poi sul MASTER verifica
ip addr show eth0 | grep 192.168.1.99
# Atteso: il VIP torna sul MASTER (priorita piu alta)
```

### 5.3 Test 3 — Spegnimento completo VM MASTER

```bash
# Sul MASTER: spegni
sudo shutdown -h now

# Sul BACKUP verifica
ip addr show eth0 | grep 192.168.1.99
# Atteso: VIP sul BACKUP in <5 secondi
```

### 5.4 Test 4 — Connessione client via VIP

```bash
# Da un client nella stessa subnet
curl -x http://192.168.1.99:8080 http://checkip.amazonaws.com
# Atteso: risposta con l'IP pubblico (proxy funzionante via VIP)
```

### 5.5 Riepilogo Test

| Test | Azione | Atteso | Tempo failover |
|------|--------|--------|---------------|
| Stop ATS su MASTER | `systemctl stop trafficserver` | VIP su BACKUP | ~9s (fall*interval) |
| Riavvio ATS su MASTER | `systemctl start trafficserver` | VIP torna su MASTER | ~6s (rise*interval) |
| Spegni VM MASTER | `shutdown -h now` | VIP su BACKUP | ~5s |
| Client via VIP | `curl -x VIP:8080` | Risposta proxy | N/A |

---

## 6. Log e Monitoraggio

### 6.1 Log keepalived

```bash
# Log in tempo reale
sudo journalctl -u keepalived -f

# Eventi di failover
sudo journalctl -u keepalived | grep -E "MASTER|BACKUP|FAULT|VRRP_Instance"
```

### 6.2 Log con notify

Con i comandi `notify_master`/`notify_backup`/`notify_fault` in configurazione,
gli eventi finiscono in syslog:

```bash
sudo grep keepalived /var/log/syslog | tail -20
# Atteso: "ATS-01 promosso MASTER", "ATS-02 degradato BACKUP", ...
```

### 6.3 Verifica stato VRRP in tempo reale

```bash
# Su entrambi i nodi
watch -n 2 'ip addr show eth0 | grep -E "inet.*99|link"; echo "---"; systemctl is-active trafficserver keepalived'
```

---

## 7. Hardening Keepalived

### 7.1 UFW — Aprire solo VRRP (multicast)

```bash
# Su entrambi i nodi
sudo ufw allow in on eth0 to 224.0.0.18 proto vrrp comment 'VRRP keepalived'
sudo ufw allow in on eth0 from 192.168.1.0/24 proto vrrp comment 'VRRP from LAN'
sudo ufw reload
```

> **⚠️ VRRP usa il protocollo IP 112 e multicast 224.0.0.18.**
> Se c'e un firewall di rete tra i nodi ATS, aprire anche li.

### 7.2 Protezione script

`enable_script_security` (gia attivo nella configurazione) blocca:
- Script scrivibili da utenti non-root
- Variabili d'ambiente iniettate da keepalived a script come root

### 7.3 Sysctl — Ottimizzazioni VRRP

```bash
sudo tee /etc/sysctl.d/99-keepalived.conf > /dev/null << 'EOF'
# Ottimizzazioni keepalived/VRRP
net.ipv4.ip_nonlocal_bind = 1      # Permette bind a IP non locali (VIP)
net.ipv4.conf.all.arp_ignore = 1   # Risponde ARP solo su interfacce con IP locale
net.ipv4.conf.all.arp_announce = 2 # Annuncia sempre l'IP migliore
EOF
sudo sysctl --system
```

| Parametro | Scopo |
|-----------|-------|
| `ip_nonlocal_bind` | ATS puo fare bind al VIP anche quando non e sull'interfaccia locale (utile per pre-bind) |
| `arp_ignore=1` | Evita risposte ARP spurie da entrambi i nodi |
| `arp_announce=2` | Il VIP viene annunciato solo dall'interfaccia che lo possiede |

### 7.4 Limiti di sicurezza

- **`auth_pass` VRRP**: massimo 8 caratteri per RFC 5798. Non e cifratura forte — e solo protezione da errori di configurazione accidentali. Per sicurezza reale usare VRRP via tunnel IPSec (fuori scope).
- **Non esporre il VIP su Internet**: il VIP e un IP locale. Usare un reverse proxy/firewall dedicato per l'accesso pubblico.

---

## 8. Piu di Due Nodi (N+1)

Per N nodi ATS, keepalived supporta priorita scalare:

| Nodo | `state` | `priority` | Note |
|------|---------|------------|------|
| ATS-1 | MASTER | 100 | Primario |
| ATS-2 | BACKUP | 50 | Fallback 1 |
| ATS-3 | BACKUP | 30 | Fallback 2 |

Il VIP segue sempre il nodo con priorita piu alta e health check OK.
Aggiungere un terzo nodo richiede solo:
1. Copiare la configurazione del BACKUP
2. Cambiare `router_id` e `priority`

---

## 9. Troubleshooting

| Problema | Causa probabile | Soluzione |
|----------|----------------|-----------|
| VIP non compare su nessun nodo | Interfaccia errata in `keepalived.conf` | Verificare con `ip -br a` e correggere `interface` |
| | `virtual_router_id` diverso tra i nodi | Allineare `virtual_router_id` su tutte le VM |
| | Firewall blocca VRRP (protocollo 112) | Aprire `proto vrrp` su UFW |
| | `keepalived.conf` ha errori di sintassi | `keepalived --dont-fork --log-console --check-config` |
| VIP su entrambi i nodi (split-brain) | `auth_pass` diversa tra MASTER e BACKUP | Allineare `auth_pass` |
| | Multicast bloccato sulla rete (switch/cloud) | Verificare che la rete permetta 224.0.0.18 |
| | `advert_int` >=2 secondi -> heartbeat persi | Ridurre a `1` |
| | Netplan assegna il VIP staticamente a una VM | Il VIP NON deve comparire in `/etc/netplan/*.yaml`. Solo keepalived lo gestisce |
| Failover non avviene quando ATS muore | Script `check_ats.sh` non eseguibile | `chmod 755 /etc/keepalived/scripts/check_ats.sh` |
| | `ATS_PORT` errata nello script | Verificare con `ss -tlnp \| grep traffic_server` |
| | `weight -50` non basta (priorita BACKUP resta piu alta) | Aumentare `fall` o diminuire `priority` BACKUP |
| `notify` non scrive in syslog | `logger` non nel PATH | Usare percorso assoluto: `/usr/bin/logger` |
| keepalived non parte | Portaudio/SNMP installato male | `sudo apt install --reinstall keepalived` |
| Host irraggiungibile dopo netplan apply | Gateway errato o file duplicati in `/etc/netplan/` | Rimuovere file cloud-init duplicati, verificare gateway con `ip route` |

### 9.1 Debug rapido

```bash
# 1. keepalived e in esecuzione?
sudo systemctl status keepalived --no-pager -l

# 2. Ci sono errori nei log?
sudo journalctl -u keepalived --since "5 min ago" --no-pager

# 3. Le interfacce sono corrette?
ip -br a

# 4. La porta ATS e in ascolto?
sudo ss -tlnp | grep traffic_server

# 5. Lo script di check funziona?
sudo /etc/keepalived/scripts/check_ats.sh && echo "OK" || echo "FAIL"

# 6. VRRP traffic arriva?
sudo tcpdump -i eth0 -c 5 proto 112
# Atteso: pacchetti VRRP in arrivo dal peer

# 7. Configurazione netplan e valida?
sudo netplan try --timeout 10
# Premi INVIO se ok, altrimenti rollback automatico

# 8. Tabella di routing corretta?
ip route show
# Deve mostrare default via <gateway>
```

---

## 10. Integrazione con Plugin ATS

### 10.1 Client che puntano al VIP

I client devono essere configurati con il VIP (non con l'IP reale della singola VM):

```
# Configurazione client:
Proxy: 192.168.1.99:8080
```

Il plugin ATS (`ats_proxy_filter_v21.so`) continua a funzionare normalmente:
l'autenticazione, il filtering dominio e gli ACL sono gestiti da ATS,
indipendentemente da quale nodo possiede il VIP.

### 10.2 Considerazioni Plugin

| Aspetto | Impatto |
|---------|---------|
| Autenticazione Basic Auth | Trasparente: il client autentica sempre contro il VIP |
| ACL per IP amministratore | Se usi `ATS_ADMIN_IPS`, assicurati che includa gli IP di tutte le VM ATS (non solo il VIP) |
| File di configurazione plugin | Identici su entrambi i nodi. Usare `scp` per sincronizzarli |
| Log di audit | Ogni nodo scrive i propri log. Per vista unificata: rsyslog centralizzato (vedi GUIDA_OPERATIVA.md S9) |

```bash
# Sincronizzare la configurazione plugin da MASTER a BACKUP
scp /etc/trafficserver/ats_proxy_filter.conf root@192.168.1.32:/etc/trafficserver/
scp /etc/trafficserver/plugin.config root@192.168.1.32:/etc/trafficserver/
```

---

## 11. Rimozione

```bash
# Su entrambi i nodi
sudo systemctl stop keepalived
sudo systemctl disable keepalived
sudo apt purge keepalived -y
sudo rm -rf /etc/keepalived

# Rimuovere sysctl (opzionale: se nessun altro servizio li usa)
sudo rm /etc/sysctl.d/99-keepalived.conf
sudo sysctl --system

# Rimuovere regole UFW (opzionale)
sudo ufw delete allow in on eth0 to 224.0.0.18 proto vrrp
```

---

## 12. Riepilogo File Creati/Modificati

| File | Nodo | Scopo |
|------|------|-------|
| `/etc/netplan/99-ats.yaml` | Entrambi | IP statico (diverso per ogni VM) |
| `/etc/keepalived/keepalived.conf` | Entrambi | Configurazione VRRP (diverso per MASTER/BACKUP) |
| `/etc/keepalived/scripts/check_ats.sh` | Entrambi | Health check ATS |
| `/etc/sysctl.d/99-keepalived.conf` | Entrambi | Ottimizzazioni kernel per VRRP |
| UFW rules (proto vrrp) | Entrambi | Firewall: permette multicast VRRP |

---

## 13. Comandi di Manutenzione Rapida

```bash
# Stato keepalived
sudo systemctl status keepalived

# Log failover
sudo journalctl -u keepalived --since today | grep -E "MASTER|BACKUP|FAULT"

# Chi ha il VIP?
ip addr show | grep -E "inet.*99"

# Forza MASTER su questo nodo (debug)
sudo kill -HUP $(cat /var/run/keepalived.pid)

# Riavvia only keepalived (ATS non viene toccato)
sudo systemctl restart keepalived

# Health check manuale
sudo /etc/keepalived/scripts/check_ats.sh && echo "ATS OK" || echo "ATS DOWN"

# Test connessione via VIP
curl -x http://192.168.1.99:8080 --max-time 5 -s -o /dev/null -w "%{http_code}\n" http://checkip.amazonaws.com

# Verifica sincronia config tra MASTER e BACKUP
diff <(ssh root@192.168.1.31 cat /etc/trafficserver/plugin.config) \
     <(ssh root@192.168.1.32 cat /etc/trafficserver/plugin.config)
```

---

## Riferimenti

- [GUIDA_INSTALLAZIONE.md](../GUIDA_INSTALLAZIONE.md) — Installazione ATS completa
- [GUIDA_INSTALLAZIONE_ATS_LTS.md](../GUIDA_INSTALLAZIONE_ATS_LTS.md) — Installazione rapida ATS
- [GUIDA_NETPLAN_IP.md](./GUIDA_NETPLAN_IP.md) — Configurazione IP Linux via netplan
- [GUIDA_OPERATIVA.md](../GUIDA_OPERATIVA.md) — Operativita quotidiana ATS

---

*Guida da validare su due VM ATS affiancate. Riferimento principale: [GUIDA_INSTALLAZIONE.md](../GUIDA_INSTALLAZIONE.md).*
