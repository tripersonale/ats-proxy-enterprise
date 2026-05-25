# ATS Proxy Enterprise — Plugin v2.1 (Config-Based)

## DENY + WHITELIST + AUTH + Admin bypass — tutto da file di configurazione

**Versione 2.1 — 25 Maggio 2026 — Testato su VM 130 e VM 134 con 50 richieste concorrenti**

Sostituisce `GUIDA_PLUGIN_UNIFICATO_v1.0.md` (stack 2-plugin) e `GUIDA_PLUGIN_UNIFICATO_v2.0.md` (hardcoded).

---

## 1. Cosa è cambiato dalla v2.0

| v2.0 | v2.1 |
|------|------|
| Deny list hardcoded in C | **Da config file** (`DENY dominio`) |
| Whitelist hardcoded in C | **Da config file** (`WHITELIST dominio`) |
| Utenti hardcoded in C | **Da config file** (`USER nome password`) |
| Admin IP già da config | Invariato |
| Regex deny non supportato | **Supportato** (`DENY .*\.ru$`) |
| Reason phrase 403 errata | **Corretto**: 403 = "Forbidden" |

**Nessuna ricompilazione necessaria per cambiare regole o utenti.** Basta editare `ats_proxy_filter.conf` e restart.

---

## 2. Config file (`/etc/trafficserver/ats_proxy_filter.conf`)

```conf
# Admin IP — bypassano tutte le regole. Editare e restart per applicare.
ADMIN 192.168.89.10
ADMIN 192.168.89.27

# DENY list — blocco immediato (403). Supporta regex con .*
DENY httpbin.org
DENY bad.com
DENY malware.net
DENY .*\.ru$

# WHITELIST — consentito senza autenticazione
WHITELIST google.com
WHITELIST github.com
WHITELIST ubuntu.com
WHITELIST example.com

# Utenti per autenticazione Basic Proxy
USER admin proxy2026
USER user1 pass123
USER operator op3rat0r
```

---

## 3. plugin.config

```bash
sudo tee /etc/trafficserver/plugin.config > /dev/null << 'EOF'
ats_proxy_filter.so
EOF
```

**Unico plugin.** Sostituisce completamente `header_rewrite.so` + `basic_auth.so` (stack v1.0).

---

## 4. Deploy

```bash
# Copia il plugin
sudo cp ats_proxy_filter.so /opt/trafficserver/lib/modules/
sudo chown ats:ats /opt/trafficserver/lib/modules/ats_proxy_filter.so

# Crea config
sudo tee /etc/trafficserver/ats_proxy_filter.conf > /dev/null << 'EOF'
ADMIN 192.168.89.10
DENY httpbin.org
WHITELIST google.com
USER admin proxy2026
EOF

# Attiva
sudo tee /etc/trafficserver/plugin.config > /dev/null << 'EOF'
ats_proxy_filter.so
EOF

sudo chown ats:ats /etc/trafficserver/ats_proxy_filter.conf /etc/trafficserver/plugin.config
sudo systemctl restart trafficserver
```

---

## 5. Test batteria

```bash
# DENY
curl -s -o /dev/null -w '%{http_code}\n' -x http://proxy:8080 http://httpbin.org/ip   # → 403

# WHITELIST
curl -s -o /dev/null -w '%{http_code}\n' -x http://proxy:8080 http://google.com        # → 301

# AUTH senza credenziali
curl -s -o /dev/null -w '%{http_code}\n' -x http://proxy:8080 http://reddit.com         # → 407

# AUTH valida
curl -s -o /dev/null -w '%{http_code}\n' -x http://proxy:8080 --proxy-user admin:proxy2026 http://reddit.com  # → 301

# AUTH errata
curl -s -o /dev/null -w '%{http_code}\n' -x http://proxy:8080 --proxy-user wrong:wrong http://reddit.com     # → 407

# Admin bypass (da IP in ADMIN)
curl -s -o /dev/null -w '%{http_code}\n' -x http://proxy:8080 http://httpbin.org/ip   # → 200
```

---

## 6. Compilazione del plugin

```bash
cd /tmp/trafficserver-9.2.13
gcc -fPIC -shared -I. -I./include -o ats_proxy_filter.so ats_proxy_filter_v21.c
```

Il sorgente è `ats_proxy_filter_v21.c` — ~250 righe di C.  
Hook: `TS_HTTP_OS_DNS_HOOK`.  
Thread-safe: zero malloc nel path caldo.

---

## 7. Come funziona

```
Richiesta → OS_DNS hook
  ├── IP in ADMIN? → CONTINUE (bypass tutto)
  ├── Host in DENY? → [403]
  ├── Host in WHITELIST? → CONTINUE
  └── Altrimenti:
        ├── Proxy-Authorization valida? → CONTINUE
        └── No/invalida → [407 + Proxy-Authenticate: Basic realm="ATS Proxy"]
```

---

## 8. Limitazioni note

| Limite | Dettaglio | Risoluzione |
|--------|-----------|-------------|
| DNS cache gap | Domini con DNS cached bypassano OS_DNS hook | Documentato. Impatto: finestra di ~minuti dopo prima visita |
| Richiede restart | Modifiche al config applicate solo dopo `systemctl restart` | Come header_rewrite, ip_allow.yaml |
| OS_DNS hook | Non scatta per domini già risolti | Alternativa READ_REQUEST_HDR testata ma non funzionante per error responses |

---

## 9. Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| Plugin non caricato | Permessi .so o plugin.config | `chown ats:ats /opt/trafficserver/lib/modules/ats_proxy_filter.so /etc/trafficserver/plugin.config` |
| Config non letto | Permessi ats_proxy_filter.conf | `chown ats:ats /etc/trafficserver/ats_proxy_filter.conf` |
| Admin bypass non funziona | ADMIN non nel config | Verificare `grep 'admin IPs' /var/lib/trafficserver/log/trafficserver/diags.log` |
| 403 invece di 200 | Non sei in ADMIN list | Controllare IP con `hostname -I` |
| 407 su dominio whitelist | WHITELIST non matcha (porta nel nome?) | Host deve matchare esattamente `google.com`, non `google.com:80` |

---

*Testato su VM 130 (Ubuntu 24.04) e VM 134 (Ubuntu 26.04) con ATS 9.2.13 — 25 Maggio 2026*
