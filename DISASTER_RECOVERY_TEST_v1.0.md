# ATS Proxy Enterprise — Test di Disaster Recovery

## Simulazione guasti e verifica ripristino automatico

**Versione 1.0 — 25 Maggio 2026**

---

## Scenari testati

### Scenario 1 — Crash di traffic_server

**Cosa simula**: Bug nel plugin o crash interno del processo.

**Come provocarlo**:
```bash
sudo pkill -9 traffic_server
```

**Comportamento atteso**:
- `traffic_manager` rileva il crash e riavvia `traffic_server` entro 1-5 secondi
- `systemd` non interviene (il processo manager resta attivo)
- Le connessioni attive vengono perse, le nuove vengono accettate dopo il riavvio

**Verifica**:
```bash
# Dopo il kill, entro 10 secondi:
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://localhost:8080 http://httpbin.org/ip
# Atteso: 200 / 403 / 407 (proxy funzionante)
```

**Result**: ✅ Testato — traffic_server riavviato dal manager in <5 secondi.

---

### Scenario 2 — Crash di traffic_manager

**Cosa simula**: Crash del processo di supervisione.

**Come provocarlo**:
```bash
sudo pkill -9 traffic_manager
```

**Comportamento atteso**:
- `systemd` rileva il crash (il manager è il MainPID)
- `Restart=on-failure` in `trafficserver.service` riavvia entro 5 secondi
- Counter di restart incrementato

**Verifica**:
```bash
sleep 6
systemctl is-active trafficserver
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 -x http://localhost:8080 http://httpbin.org/ip
```

**Result**: ✅ Testato — systemd restart con `RestartSec=5s`.

---

### Scenario 3 — Lock file sporchi

**Cosa simula**: Riavvio brutale che lascia file `.lock` residui.

**Come provocarlo**:
```bash
sudo systemctl stop trafficserver
sudo touch /var/trafficserver/manager.lock
sudo touch /var/trafficserver/server.lock
sudo systemctl start trafficserver
```

**Comportamento atteso**:
- Il servizio NON parte (lock file bloccano l'avvio)
- Il log mostra `Can't acquire manager lockfile` o simile

**Ripristino**:
```bash
sudo systemctl stop trafficserver
sudo rm -f /var/trafficserver/manager.lock
sudo rm -f /var/trafficserver/server.lock
sudo rm -f /var/trafficserver/*.sock
sudo systemctl start trafficserver
```

**Result**: ⚠️ Lock file bloccano l'avvio — procedura cleanup documentata e funzionante.

---

### Scenario 4 — Disco cache pieno

**Cosa simula**: La cache disco raggiunge il limite configurato.

**Come si comporta ATS**:
- `storage.config` limita la cache a 10G
- `max_space_mb_for_logs` limita i log a 10000 MB
- `auto_delete_rolled_files` cancella i log più vecchi

**Verifica spazio**:
```bash
df -h /opt/trafficserver/var/trafficserver/cache
df -h /var/log/trafficserver
```

**Mitigazione**: Configurare monitoring su spazio disco (>80% = alert).

**Result**: ✅ Configurato — log rotation e cache limit impediscono il riempimento.

---

### Scenario 5 — DNS failure

**Cosa simula**: Il server DNS configurato non risponde.

**Come si comporta ATS**:
- `dns.lookup_timeout=30` (timeout dopo 30 secondi)
- `dns.nameservers=NULL` → usa `/etc/resolv.conf` di sistema
- Le richieste vanno in timeout, il proxy non crasha

**Verifica**:
```bash
# Temporaneamente rompere DNS (SOLO PER TEST)
sudo mv /etc/resolv.conf /etc/resolv.conf.bak
# Testare richiesta → timeout dopo 30s
sudo mv /etc/resolv.conf.bak /etc/resolv.conf
```

**Result**: ⚠️ Testato — timeout funziona ma il client attende 30s. Mitigazione: impostare `dns.lookup_timeout` a 10 in produzione.

---

### Scenario 6 — Health check rileva e ripara

**Cosa simula**: Il proxy smette di rispondere (porta in ascolto ma nessuna risposta HTTP).

**Automatismo**:
```bash
# /opt/ats_health.sh eseguito ogni 60 secondi via cron:
# 1. curl http://localhost:8080
# 2. Se HTTP code != 200/403/407 → systemctl restart trafficserver
```

**Test**:
```bash
# 1. Bloccare temporaneamente il proxy
sudo iptables -A OUTPUT -p tcp --dport 80 -j DROP
# 2. Attendere 60 secondi
# 3. Verificare che health check abbia riavviato
sudo grep ALERT /var/log/ats-health.log
# 4. Ripristinare
sudo iptables -D OUTPUT -p tcp --dport 80 -j DROP
```

**Result**: ✅ Testato — health check rileva il blocco e restart entro 60s.

---

### Scenario 7 — AppArmor blocca ATS (solo 26.04 con /usr/local/pcre)

**Cosa simula**: Profilo AppArmor troppo restrittivo.

**Sintomo**: `traffic_server` zombie, `traffic_manager` in loop di riavvio.

**Diagnosi**:
```bash
sudo aa-status | grep traffic
# Se il profilo è in enforce mode e causa crash

sudo dmesg | grep DENIED | grep traffic
# Mostra le operazioni bloccate
```

**Ripristino**:
```bash
sudo aa-disable /etc/apparmor.d/opt.trafficserver.bin.traffic_server
sudo systemctl restart trafficserver
```

**Result**: ✅ Documentato — procedura di rimozione profilo e riattivazione con tuning.

---

## Riepilogo

| Scenario | Impatto | Recovery automatico? | Tempo recovery |
|----------|---------|---------------------|----------------|
| Crash traffic_server | Connessioni perse | ✅ Manager riavvia | 1-5 sec |
| Crash traffic_manager | Connessioni perse | ✅ systemd riavvia | 5-10 sec |
| Lock file sporchi | Avvio bloccato | ❌ Manuale | ~1 min (procedura doc) |
| Disco cache pieno | Scritture fallite | ✅ auto-delete log + cache limit | Immediato |
| DNS failure | Timeout richieste | ⚠️ Parziale (30s timeout) | Recupero dopo timeout |
| Proxy non risponde | Servizio down | ✅ Health check restart | 60 sec max |
| AppArmor blocco | Avvio bloccato | ❌ Manuale | ~2 min (procedura doc) |

---

## Comando verifica rapida

```bash
#!/bin/bash
# Test rapido di tutti gli scenari recuperabili automaticamente
echo "=== Disaster Recovery Quick Test ==="
# Scenario 1
sudo pkill -9 traffic_server 2>/dev/null
sleep 10
curl -s -o /dev/null -w "S1 traffic_server: %{http_code}\n" -x http://localhost:8080 http://httpbin.org/ip
# Scenario 2
sudo pkill -9 traffic_manager 2>/dev/null
sleep 10
curl -s -o /dev/null -w "S2 traffic_manager: %{http_code}\n" -x http://localhost:8080 http://httpbin.org/ip
# Scenario 6
sudo tail -1 /var/log/ats-health.log
echo "Done."
```

---

*Guida basata su test reali: VM 130 (24.04) e VM 134 (26.04)*
