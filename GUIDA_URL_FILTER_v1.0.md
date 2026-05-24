# ATS Proxy Enterprise — Guida URL Filtering a 3 Livelli

## Deny, Whitelist, Auth-Gated + Bypass Admin

**Versione 1.0 — 24 Maggio 2026 — Testata su VM 130 (24.04) e VM 134 (26.04)**

---

## 1. Architettura

```
Richiesta ──▶ ip_allow.yaml (chi può parlare col proxy)
               │
               ▼
          header_rewrite.so (url_filter.conf)
               │
         ┌─────┼─────┐
         ▼     ▼     ▼
       DENY  WHITE  AUTH-GATED
       403    OK     407 (richiede Proxy-Authorization)
                       │
                  Admin IP bypass (salta tutto)
```

**Tecnologia**: `header_rewrite.so` — già compilato in ATS 9.2.13, zero installazioni aggiuntive.

---

## 2. File necessari

| File | Ruolo |
|------|-------|
| `/etc/trafficserver/plugin.config` | Attiva header_rewrite in modalità globale |
| `/etc/trafficserver/url_filter.conf` | Regole deny/whitelist/auth |

---

## 3. Configurazione

### 3.1 plugin.config

```bash
sudo tee /etc/trafficserver/plugin.config > /dev/null << 'EOF'
header_rewrite.so /etc/trafficserver/url_filter.conf
EOF
sudo chown ats:ats /etc/trafficserver/plugin.config
```

### 3.2 url_filter.conf — Template

```bash
sudo bash -c 'cat > /etc/trafficserver/url_filter.conf << '"'"'FILTEREOF'"'"'
# === DENY — Bloccati sempre (admin IP esclusi) ===
cond %{READ_REQUEST_HDR_HOOK}
cond %{IP:CLIENT} {192.168.89.10/32,192.168.89.27/32} [NOT]
cond %{HEADER:Host} =dominio-da-bloccare.com
    set-status 403

# === AUTH-GATED — Richiede Proxy-Authorization (admin e whitelist esclusi) ===
cond %{READ_REQUEST_HDR_HOOK}
cond %{IP:CLIENT} {192.168.89.10/32,192.168.89.27/32} [NOT]
cond %{HEADER:Host} =dominio-da-bloccare.com [NOT]
cond %{HEADER:Host} =google.com [NOT]
cond %{HEADER:Host} =github.com [NOT]
cond %{HEADER:Host} =ubuntu.com [NOT]
    set-status 407
    set-header Proxy-Authenticate "Basic realm=ATS"
FILTEREOF
sudo chown ats:ats /etc/trafficserver/url_filter.conf
sudo systemctl restart trafficserver
```

### 3.3 Spiegazione regole

| Sezione | Logica |
|---------|--------|
| **DENY** | Se Host matcha dominio bloccato E IP non è admin → 403 |
| **WHITELIST** | Nessuna regola: i domini elencati nei `[NOT]` dell'AUTH-GATED passano liberamente |
| **AUTH-GATED** | Se Host NON è in deny, NON è in whitelist, E IP non è admin → 407 Proxy Authentication Required |
| **Admin bypass** | IP in lista `{192.168.89.10/32,192.168.89.27/32}` saltano tutte le regole |

### 3.4 Aggiungere/rimuovere domini

```bash
# Aggiungere un dominio alla deny list: duplicare il blocco DENY con il nuovo host
cond %{READ_REQUEST_HDR_HOOK}
cond %{IP:CLIENT} {192.168.89.10/32,192.168.89.27/32} [NOT]
cond %{HEADER:Host} =nuovo-dominio.com
    set-status 403
```

```bash
# Aggiungere un dominio alla whitelist: aggiungere un [NOT] nella sezione AUTH-GATED
cond %{HEADER:Host} =nuovo-whitelist.com [NOT]
```

### 3.5 Regex e wildcard

```bash
# Bloccare intero TLD con regex
cond %{HEADER:Host} /\.ru$/
    set-status 403

# Bloccare sottodomini con regex
cond %{HEADER:Host} /(ads\.|tracker\.|spam\.)/
    set-status 403
```

---

## 4. Test

### 4.1 Batteria test

```bash
# Da IP NON admin (es. 192.168.89.28)
echo "=== DENY ===" && curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 -x http://PROXY:8080 http://dominio-bloccare.com/
# Atteso: 403

echo "=== WHITELIST ===" && curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 -x http://PROXY:8080 http://google.com/
# Atteso: 301

echo "=== AUTH-GATED ===" && curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 -x http://PROXY:8080 http://wikipedia.org/
# Atteso: 407

# Da IP admin (es. 192.168.89.27)
echo "=== ADMIN BYPASS ===" && curl -sI -o /dev/null -w "%{http_code}" --connect-timeout 5 -x http://PROXY:8080 http://dominio-bloccare.com/
# Atteso: 200
```

### 4.2 Verifica log

```bash
sudo tail -5 /var/lib/trafficserver/log/trafficserver/audit.log
# I 403 e 407 appaiono nel log con FQDN
```

---

## 5. Limitazioni note

| Limite | Dettaglio | Workaround |
|--------|-----------|------------|
| **Validazione credenziali** | Il 407 richiede auth, ma header_rewrite non valida password | Usare AuthProxy con server auth esterno (vedi Appendice A) |
| **Ordine regole** | Le regole sono valutate in ordine; DENY deve venire prima di AUTH-GATED | Seguire il template |
| **Numero condizioni** | Molte condizioni `[NOT]` possono rallentare il parsing | Raggruppare con regex dove possibile |
| **Log 403/407** | I blocchi appaiono nell'audit log | ✅ già funzionante |

---

## 6. Ripristino (disattivare filtro)

```bash
sudo rm /etc/trafficserver/plugin.config
sudo rm /etc/trafficserver/url_filter.conf
sudo systemctl restart trafficserver
```

---

## APPENDICE A — AuthProxy con server esterno

Per validare le credenziali (non solo richiederle), usare `authproxy.so`:

```bash
# plugin.config
header_rewrite.so /etc/trafficserver/url_filter.conf
authproxy.so --auth-transform=redirect --auth-host=127.0.0.1 --auth-port=9000
```

**Attenzione**: In forward proxy mode, AuthProxy redirect NON inoltra l'Host originale al server auth. Il server auth riceve `Host: 127.0.0.1:9000` e non sa quale sito l'utente vuole visitare. Questo richiede un workaround (plugin Lua o header custom).

---

*Testato su VM 130 (Ubuntu 24.04) e VM 134 (Ubuntu 26.04) con ATS 9.2.13*
