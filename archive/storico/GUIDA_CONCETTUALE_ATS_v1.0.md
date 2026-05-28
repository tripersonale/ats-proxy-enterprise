# Apache Traffic Server — Guida Concettuale

## Per capire cosa fa e come funziona

**Versione 1.0 — 24 Maggio 2026**

---

## 1. Cos'è Apache Traffic Server

ATS e un proxy HTTP ad alte prestazioni sviluppato dalla Apache Software Foundation. Combina proxy forward/reverse con una cache disco+RAM. E usato da Facebook, Yahoo, Apple e Comcast per le loro CDN.

Non e un semplice forwarder — e un **application-level gateway** che termina le connessioni client e ne apre di nuove verso i server di origine (o risponde da cache).

### ATS vs altri proxy

| Proxy | Modello | Punti di forza | Punti deboli |
|-------|---------|---------------|--------------|
| **ATS** | Event-driven, asincrono | Performance CDN-grade, cache potente, plugin Lua | Configurazione ostica, community piccola |
| Squid | Thread/process-based | Configurazione semplice, ACL flessibili | Meno performance, meno caching, piu CVE |
| HAProxy | Event-driven | Load balancer, no cache | Non e un proxy HTTP generico |
| Nginx | Event-driven | Reverse proxy + web server | Forward proxy non nativo, richiede moduli |

---

## 2. Architettura

ATS ha due processi principali:

```
┌────────────────────────────────┐
│  traffic_manager (PID 1)       │
│  - Gestisce il ciclo di vita   │
│  - Monitora traffic_server     │
│  - Espone API di management    │
│  - Riavvia se crash            │
└──────────┬─────────────────────┘
           │ spawn
┌──────────▼─────────────────────┐
│  traffic_server (N thread)     │
│  - Event-driven, I/O asincrono │
│  - Cache RAM + disco           │
│  - DNS resolution              │
│  - Logging                     │
│  - Plugin                      │
└────────────────────────────────┘
```

**Flusso di una richiesta forward proxy:**

```
Client ──CONNECT/POST/GET──▶ ATS:8080
                              │
                              ├─ 1. ip_allow.yaml: IP autorizzato?
                              │     No → 403 Forbidden (loggato)
                              │
                              ├─ 2. Cache HIT?
                              │     Si → risponde da cache (Age: X)
                              │
                              ├─ 3. DNS lookup (via /etc/resolv.conf)
                              │     sistema → ottiene IP backend
                              │
                              ├─ 4. Connessione al backend
                              │     HTTP: richiesta trasparente
                              │     HTTPS: CONNECT tunnel (cifrato)
                              │
                              ├─ 5. Risposta → cache (se cacheable)
                              │
                              └─ 6. Logging (audit.log)
```

**Per HTTPS CONNECT:**
```
Client ──CONNECT example.com:443──▶ ATS ──TCP──▶ example.com:443
                                        │
                               tunnel cifrato end-to-end
                               ATS NON vede il contenuto
                               Logga solo: CONNECT example.com:443
```

---

## 3. Modello di ACL

### ip_allow.yaml

ATS 9.x usa YAML per le ACL. Struttura:

```yaml
ip_allow:
  - apply: in       # traffico in ingresso (client → proxy)
    ip_addrs: ...   # IP o subnet o range
    action: allow   # allow | deny
    method: ALL     # metodi HTTP permessi
```

### Regole di valutazione (scoperte dai test)

1. **L'ordine CONTA** — `ip_allow.yaml` usa **first-match** (come iptables). La prima regola che matcha determina allow/deny. Le regole successive vengono ignorate.
2. **Deny /32 deve precedere allow /24** per bloccare un IP in una subnet autorizzata. Se l'allow /24 viene prima, matcha per primo e il deny viene saltato.
3. **`traffic_ctl config reload` NON applica i deny** — per attivare un blocco serve `systemctl restart trafficserver`.
4. **Il deny blocca a livello TCP** — connessione rifiutata/resettata, non HTTP 403.

### Due layer di sicurezza

```
Richiesta ──▶ UFW (TCP) ──▶ ip_allow.yaml (HTTP) ──▶ Proxy
              │                │
              │ Block = timeout│ Block = 403 (loggato)
              │ (nessun log)   │
```

UFW blocca a livello TCP: nessuna risposta, connection timeout. ip_allow.yaml blocca a livello HTTP: risposta 403 con log.

---

## 4. Logging

ATS 9.x ha **due sistemi di logging**:

### logging.yaml (nuovo, PRIORITARIO)

Se esiste `/etc/trafficserver/logging.yaml`, **questo prende il sopravvento** su `logs_xml.config`. Si configura con YAML:

```yaml
logging:
  formats:
    - name: audit
      format: '%<chi> ... %<{Host}cqh> ... %<shn>'
      interval: 1        # secondi tra un flush e l'altro
  logs:
    - filename: audit    # nome file (relativo a log dir)
      format: audit
      mode: ascii
      rolling_enabled: 1
      rolling_interval_sec: 86400  # rotate ogni 24h
```

### logs_xml.config (vecchio, IGNORATO se esiste logging.yaml)

Formato XML, compatibile con versioni precedenti. Se esiste `logging.yaml`, questo file viene ignorato.

### Variabili di log principali

| Variabile | Significato | Validita |
|-----------|-------------|----------|
| `%<chi>` | IP del client | ✅ |
| `%<cqtx>` | Request line (include URL/FQDN) | ✅ |
| `%<pssc>` | Status code HTTP | ✅ |
| `%<pscl>` | Content-Length | ✅ |
| `%<{Host}cqh>` | Host header (FQDN richiesto) | ✅ |
| `%<shn>` | Hostname server origine | ✅ |
| `%<caun>` | Username (se autenticato) | ✅ |
| `%<cqtn>` | Timestamp | ✅ |
| `%<{SERVC}pquc>` | IP backend grezzo | ❌ Non valido in logging.yaml |

---

## 5. Sicurezza — CVE e superficie d'attacco

### Perché ATS 9.2.13 e NON 9.2.3 (da apt)

La versione nei repo Ubuntu 24.04 e 9.2.3. Queste sono le CVE **aperte** nella 9.2.3 che la 9.2.13 chiude:

| CVE | Impatto | Risolta in |
|-----|---------|------------|
| CVE-2024-38311 | Input validation → crash/DoS | 9.2.9 |
| CVE-2024-38479 | Input validation → crash | 9.2.6 |
| CVE-2024-50305 | Host header → crash | 9.2.6 |
| CVE-2024-50306 | Privilege retention | 9.2.6 |
| CVE-2024-53868 | Request smuggling (chunked) | 9.2.10 |
| CVE-2024-56195 | Access control bypass | 9.2.9 |
| CVE-2024-56202 | Expected behavior violation | 9.2.9 |
| CVE-2025-31698 | ACL bypass via PROXY protocol | 9.2.11 |
| CVE-2025-49763 | ESI memory exhaustion | 9.2.11 |
| CVE-2025-58136 | POST request → crash | 9.2.13 |
| CVE-2025-65114 | Request smuggling (chunked) | 9.2.13 |

**11 CVE, di cui 4 di tipo request smuggling e 3 di crash DoS.** Compilare la 9.2.13 e l'unica strada per avere un proxy sicuro.

### Debian sta rimuovendo ATS

Debian 13 (Trixie) non avra ATS. Il pacchetto e bloccato per `libpcre3` non piu disponibile e ha 11 CVE aperte nella versione unstable. Il maintainer ha chiesto la rimozione. **Compilare da sorgente e l'unica strada sostenibile.**

### Superficie d'attacco ridotta

ATS e compilato con:
- `--disable-tests` (niente binary di test esposti)
- `--disable-examples` (niente plugin di esempio)
- `--disable-maintainer-mode`
- Utente dedicato `ats` con shell `/usr/sbin/nologin`
- File descriptor limitati via systemd (`LimitNOFILE=65535`)
- Cache isolata in `/opt/trafficserver/var/trafficserver/cache`

---

## 6. Cache Model

ATS ha due livelli di cache:

1. **RAM cache**: 1 GB (configurabile via `ram_cache.size`). Contenuti piccoli e frequenti.
2. **Disk cache**: 10 GB su `/opt/trafficserver/var/trafficserver/cache`. Contenuti piu grandi, persistente.

Il contenuto viene servito da cache se:
- Il metodo e GET o HEAD
- La risposta ha header di caching validi (Cache-Control, Expires)
- Il contenuto non supera la soglia RAM cache cutoff
- Non ci sono header che forzano il bypass (Authorization, ecc.)

**Cache HIT vs MISS**: si vede nell'header `Age` della risposta. Se > 0, la risposta viene da cache.

---

## 7. Plugin e estendibilita

ATS supporta plugin in C++ e Lua. Esempi di uso:

| Plugin | Cosa fa |
|--------|---------|
| `header_rewrite` | Modifica header in transito (aggiungere/togliere header) |
| `rate_limit` | Limita richieste per IP o dominio |
| `auth` | Autenticazione Basic/Digest sul proxy |
| `esi` | Edge Side Includes (frammenti di pagina cachabili) |
| `ts_lua` | Script Lua per logica custom (senza ricompilare) |

I plugin vanno in `/opt/trafficserver/lib/modules/` e si attivano in `plugin.config`.

---

*Guida basata su test reali: VM 130, Ubuntu 24.04.4 LTS, ATS 9.2.13 compilato*
