# ATS Proxy Enterprise — Plugin Production v2.0

## Plugin singolo: DENY + WHITELIST + AUTH + Admin bypass

**Versione 2.0 — 25 Maggio 2026 — Testato su VM 130 (24.04) e VM 134 (26.04) con 50 richieste concorrenti**

---

## 1. Architettura

```
Richiesta ──▶ ip_allow.yaml (chi puo connettersi)
               │
               ▼
          ats_proxy_filter.so (OS_DNS_HOOK)
               │
         ┌─────┼─────┐
         ▼     ▼     ▼
       Admin  DENY  WHITELIST
      bypass  403   pass
         │              │
         └──────────────┴──▶ No → 407 + Proxy-Authenticate
                              Sì → CONTINUE
```

**Unico plugin.** Sostituisce completamente `header_rewrite.so` + `basic_auth.so`.

| Caratteristica | Valore |
|----------------|--------|
| Hook | `TS_HTTP_OS_DNS_HOOK` |
| Thread safety | Zero malloc in hot path, dati read-only dopo init |
| Config | `/etc/trafficserver/ats_proxy_filter.conf` |
| Admin IP | Letto da config file |
| User/password | Hardcoded in C (v2.1: da config) |
| Deny/Whitelist | Hardcoded in C (v2.1: da config) |

---

## 2. Deploy

### 2.1 Copia plugin

```bash
sudo cp /tmp/clean_admin.so /opt/trafficserver/lib/modules/ats_proxy_filter.so
sudo chown ats:ats /opt/trafficserver/lib/modules/ats_proxy_filter.so
```

### 2.2 Config file

```bash
sudo tee /etc/trafficserver/ats_proxy_filter.conf > /dev/null << 'EOF'
# Admin IP — bypassano tutte le regole (letto dal plugin)
ADMIN 192.168.89.10
ADMIN 192.168.89.27
EOF
```

### 2.3 plugin.config

```bash
sudo tee /etc/trafficserver/plugin.config > /dev/null << 'EOF'
ats_proxy_filter.so
EOF
sudo chown ats:ats /etc/trafficserver/plugin.config /etc/trafficserver/ats_proxy_filter.conf
sudo systemctl restart trafficserver
```

---

## 3. Regole (hardcoded in C)

```c
// In clean_admin.c, funzione handle_dns:
const char *deny[] = {"httpbin.org","bad.com","malware.net",NULL};
const char *white[] = {"google.com","github.com","ubuntu.com","example.com",NULL};
```

Per modificare: editare `clean_admin.c`, ricompilare, sostituire `.so`, restart.

---

## 4. Credenziali (hardcoded in C)

```c
// In clean_admin.c, funzione authorized():
if (!strcmp(user, "admin") && !strcmp(password, "proxy2026")) return 1;
if (!strcmp(user, "user1") && !strcmp(password, "pass123")) return 1;
```

| Utente | Password |
|--------|----------|
| `admin` | `proxy2026` |
| `user1` | `pass123` |

Per modificare: editare `clean_admin.c`, ricompilare.

---

## 5. Come usare l'auth dal client

```bash
# Senza credenziali → 407
curl -x http://proxy:8080 http://example.com
# → 407 Proxy Authentication Required

# Con credenziali
curl -x http://proxy:8080 --proxy-user admin:proxy2026 http://example.com
# → 200 OK

# Browser: popup automatico di login quando riceve 407
```

---

## 6. Batteria test (verificata il 25/05/2026)

| # | Test | VM134 | VM130 |
|---|------|-------|-------|
| 1 | httpbin.org (DENY) | **403** | **403** |
| 2 | google.com (WHITELIST) | **301** | **301** |
| 3 | reddit.com (AUTH no creds) | **407** | **407** |
| 4 | admin:proxy2026 | **301** | **301** |
| 5 | user1:pass123 | **301** | **301** |
| 6 | wrong:wrong | **407** | **407** |
| 7 | Admin IP bypass httpbin | **200** ✅ | **200** ✅ |
| 8 | 10 concorrenti DENY | 403x10 | 403x10 |
| 9 | 20 concorrenti AUTH | 301x20 | 301x20 |
| 10 | **50 concorrenti DENY** | **403x50** | **403x50** |
| 11 | **50 concorrenti AUTH** | **301x50** | **301x50** |
| 12 | Proxy-Authenticate header | `Basic realm="proxy"` | `Basic realm="proxy"` |
| 13 | Malformed auth (empty, binary, long) | 407 (no crash) | 407 (no crash) |

---

## 7. Compilazione da sorgente

```bash
cd /tmp/trafficserver-9.2.13
gcc -fPIC -shared -I. -I./include -o /tmp/ats_proxy_filter.so clean_admin.c
sudo cp /tmp/ats_proxy_filter.so /opt/trafficserver/lib/modules/
sudo chown ats:ats /opt/trafficserver/lib/modules/ats_proxy_filter.so
```

---

## 8. Limitazioni note

| Limite | Dettaglio | Risoluzione |
|--------|-----------|-------------|
| DNS cache gap | Domini con DNS cached bypassano OS_DNS hook | v2.1: hook READ_REQUEST_HDR |
| Deny/Whitelist hardcoded | Modifica richiede ricompilazione | v2.1: lettura da config file |
| Utenti hardcoded | Modifica richiede ricompilazione | v2.1: lettura da config file |
| Proxy-Authenticate anche per 403 | Header superfluo ma innocuo | v2.1: skip per 403 |

---

## 9. Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| 407 invece di 403 | Deny non matcha Host | Verificare host_match: confronto esatto, no porta |
| Admin bypass non funziona | ADMIN non nel config o config non letto | Verificare `grep 'admin IPs' diags.log` |
| Plugin non caricato | Permessi .so o plugin.config | `chown ats:ats` su entrambi |
| Crash sotto carico | >50 concorrenti su OS_DNS | Testato fino a 50; oltre, distribuire |

---

*Plugin testato su VM 130 (Ubuntu 24.04) e VM 134 (Ubuntu 26.04) con ATS 9.2.13 — 25 Maggio 2026*
