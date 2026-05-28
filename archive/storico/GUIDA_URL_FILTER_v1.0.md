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
sudo tail -5 /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
# I 403 e 407 appaiono nel log con FQDN
```

---

## 5. Limitazioni note

| Limite | Dettaglio | Soluzione |
|--------|-----------|------------|
| **Validazione credenziali** | header_rewrite da solo può solo rispondere 407, non verificare password | basic_auth plugin (Appendice A) |
| **Proxy-Authenticate header** | `set-header Proxy-Authenticate` NON viene emesso sulle risposte 407 sintetiche di header_rewrite | basic_auth plugin lo emette correttamente |
| **DNS cache gap** | basic_auth su OS_DNS_HOOK non scatta per domini con DNS cached | Accettabile per la maggior parte dei domini |
| **Concorrenza >5** | Il plugin basic_auth di esempio ha race condition sotto carico elevato | Riscrivere plugin thread-safe per produzione |
| **Ordine regole** | DENY deve venire prima di AUTH-GATED nel file | Seguire il template |
| **Regex** | Supportate con sintassi `/pattern/` | ✅ funzionante |

---

## 6. Ripristino (disattivare filtro)

```bash
sudo rm /etc/trafficserver/plugin.config
sudo rm /etc/trafficserver/url_filter.conf
sudo systemctl restart trafficserver
```

---

## APPENDICE A — Basic Auth con plugin compilato

### Strada A — Plugin basic_auth (verificato funzionante il 24/05/2026)

ATS 9.2.13 include un plugin di esempio `basic_auth.c` in `example/plugins/c-api/basic_auth/`. Compilato e testato su VM134:

```bash
cd /tmp/trafficserver-9.2.13
# Modificare authorized() con utenti reali
# es: if (strcmp(user, "admin") == 0 && strcmp(password, "proxy2026") == 0) return 1;

gcc -fPIC -shared -I. -I./include -o /tmp/basic_auth.so example/plugins/c-api/basic_auth/basic_auth.c
sudo cp /tmp/basic_auth.so /opt/trafficserver/lib/modules/
```

```bash
# plugin.config — header_rewrite PRIMA (deny), basic_auth DOPO (auth)
cat > /etc/trafficserver/plugin.config << 'EOF'
header_rewrite.so /etc/trafficserver/url_filter.conf
basic_auth.so
EOF
```

**Risultati testati**:
- ✅ 407 + Proxy-Authenticate header corretto
- ✅ 3 utenti validi (admin, user1, operator)
- ✅ Credenziali errate → 407
- ✅ DENY list blocca PRIMA dell'auth (403)
- ✅ 5 richieste concorrenti ok
- ⚠️ DNS cache gap: OS_DNS hook non scatta per domini con DNS cached
- ⚠️ 10+ concorrenti: race condition (plugin example, non production-grade)

### Strada B — AuthProxy con server esterno

Alternativa: `authproxy.so` (già compilato). Delega auth a un server HTTP esterno. In forward proxy mode, la redirect non forwarda l'Host originale — richiede workaround.

### Raccomandazione

Per ambienti dove basta URL filtering (deny + whitelist), usare solo header_rewrite.
Per ambienti che richiedono autenticazione reale, usare Strada A con basic_auth su OS_DNS hook, accettando il gap DNS cache.

---

*Testato su VM 130 (Ubuntu 24.04) e VM 134 (Ubuntu 26.04) con ATS 9.2.13*

**Batteria test completa (24-25 Maggio 2026):**
- ✅ Deny 403 da IP non-admin (cross-VM e locale)
- ✅ Whitelist pass-through (google.com, github.com, ubuntu.com)
- ✅ Auth-gated 407 con basic_auth plugin (3 utenti)
- ✅ Proxy-Authenticate header emesso da basic_auth
- ✅ Admin IP bypass
- ✅ Regex deny (`/httpbin/`, `/google/`)
- ✅ 5 richieste concorrenti con auth attivo
- ✅ Log audit contiene FQDN per 403 e 407
- ⚠️ DNS cache gap: OS_DNS hook non scatta per domini cached
- ⚠️ basic_auth di esempio: race condition sopra 5 concorrenti
