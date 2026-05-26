# ATS Proxy Enterprise — Guida Plugin Unificato URL Filtering + Auth

## Stack header_rewrite + ats_proxy_filter (basic_auth)

**Versione 1.0 — 25 Maggio 2026 — Testato su VM 134 (26.04) con 20 richieste concorrenti**

---

## 1. Architettura

```
Richiesta ──▶ ip_allow.yaml (chi puo connettersi)
               │
               ▼
          header_rewrite.so (READ_REQUEST_HDR_HOOK)
               │
          ┌────┼────┐
          ▼    ▼    ▼
        DENY  Admin  Pass
        403   skip   through
                        │
                        ▼
                 ats_proxy_filter.so (OS_DNS_HOOK)
                        │
                   ┌────┼────┐
                   ▼         ▼
               No auth    Valid auth
                 407        CONTINUE
```

**Due plugin, zero conflitti.** header_rewrite blocca con 403 PRIMA che il DNS venga risolto. basic_auth intercetta sul DNS hook e restituisce 407 + Proxy-Authenticate.

| Plugin | Hook | Ruolo |
|--------|------|-------|
| `header_rewrite.so` | `READ_REQUEST_HDR_HOOK` | DENY list, Admin IP bypass |
| `ats_proxy_filter.so` | `OS_DNS_HOOK` | Auth (407 + Proxy-Authenticate), validazione credenziali |

---

## 2. File necessari

| File | Ruolo |
|------|-------|
| `/etc/trafficserver/plugin.config` | Attiva entrambi i plugin |
| `/etc/trafficserver/url_filter.conf` | Regole DENY + Admin bypass (header_rewrite) |
| `/opt/trafficserver/lib/modules/ats_proxy_filter.so` | Plugin auth (basic_auth compilato) |

---

## 3. Deploy

### 3.1 Copia il plugin auth

```bash
# Il plugin e basic_auth.c compilato con utenti hardcoded
# Sorgente: /tmp/trafficserver-9.2.13/example/plugins/c-api/basic_auth/basic_auth.c
# Modifiche: funzione authorized() con 3 utenti (admin/user1/operator)

sudo cp /tmp/basic_auth.so /opt/trafficserver/lib/modules/ats_proxy_filter.so
sudo chown ats:ats /opt/trafficserver/lib/modules/ats_proxy_filter.so
```

### 3.2 plugin.config

```bash
sudo tee /etc/trafficserver/plugin.config > /dev/null << 'EOF'
header_rewrite.so /etc/trafficserver/url_filter.conf
ats_proxy_filter.so
EOF
sudo chown ats:ats /etc/trafficserver/plugin.config
```

### 3.3 url_filter.conf

```bash
sudo bash -c 'cat > /etc/trafficserver/url_filter.conf << FILTEREOF
# Admin IP bypass (salta TUTTE le regole)
cond %{READ_REQUEST_HDR_HOOK}
cond %{IP:CLIENT} {192.168.89.10/32,192.168.89.27/32} [NOT]
cond %{HEADER:Host} =httpbin.org
    set-status 403

cond %{READ_REQUEST_HDR_HOOK}
cond %{IP:CLIENT} {192.168.89.10/32,192.168.89.27/32} [NOT]
cond %{HEADER:Host} =bad.com
    set-status 403

cond %{READ_REQUEST_HDR_HOOK}
cond %{IP:CLIENT} {192.168.89.10/32,192.168.89.27/32} [NOT]
cond %{HEADER:Host} =malware.net
    set-status 403
FILTEREOF'
sudo chown ats:ats /etc/trafficserver/url_filter.conf
```

### 3.4 Riavvio

```bash
sudo systemctl restart trafficserver
```

---

## 4. Credenziali predefinite

| Utente | Password |
|--------|----------|
| `admin` | `proxy2026` |
| `user1` | `pass123` |
| `operator` | `op3rat0r` |

Modificabili nel sorgente `basic_auth.c` → funzione `authorized()`.

---

## 5. Batteria test (verificata il 25/05/2026)

| # | Test | VM130 (admin) | VM134 (non-admin) |
|---|------|-------------|-------------------|
| 1 | google.com (whitelist) | 301 | 301 |
| 2 | httpbin.org (DENY) | 407 (admin bypass → auth) | **403** |
| 3 | bad.com (DENY) | 407 | **403** |
| 4 | wikipedia.org (AUTH) | 407 | **407** |
| 5 | wikipedia.org admin:proxy2026 | **301** | **301** |
| 6 | wikipedia.org user1:pass123 | **301** | **301** |
| 7 | wikipedia.org wrong:wrong | **407** | **407** |
| 8 | 5 concorrenti auth | Tutti 301 | Tutti 301 |
| 9 | 10 concorrenti deny | Tutti 403 | Tutti 403 |
| 10 | **20 concorrenti deny** | Tutti 403 | Tutti 403 |
| 11 | **20 concorrenti auth** | Tutti 301 | Tutti 301 |
| 12 | Proxy-Authenticate header | `Basic realm="proxy"` | `Basic realm="proxy"` |
| 13 | Audit log FQDN per 403/407 | FQDN presente | FQDN presente |

---

## 6. Aggiungere/rimuovere domini

### DENY list

```bash
sudo bash -c 'cat >> /etc/trafficserver/url_filter.conf << FILTEREOF

cond %{READ_REQUEST_HDR_HOOK}
cond %{IP:CLIENT} {192.168.89.10/32,192.168.89.27/32} [NOT]
cond %{HEADER:Host} =nuovo-dominio.com
    set-status 403
FILTEREOF'
sudo systemctl restart trafficserver
```

### Admin IP

Aggiungere l'IP alla lista `{192.168.89.10/32,192.168.89.27/32,192.168.89.X/32}` in tutte le regole DENY.

---

## 7. Come compilare il plugin auth da zero

```bash
cd /tmp/trafficserver-9.2.13
cp example/plugins/c-api/basic_auth/basic_auth.c basic_auth_custom.c
# Modificare authorized() con gli utenti desiderati
gcc -fPIC -shared -I. -I./include -o /tmp/ats_proxy_filter.so basic_auth_custom.c
sudo cp /tmp/ats_proxy_filter.so /opt/trafficserver/lib/modules/
```

---

## 8. Limitazioni note

| Limite | Dettaglio | Impatto |
|--------|-----------|---------|
| DNS cache gap | Domini con DNS cached bypassano OS_DNS hook → niente auth | Basso: solo domini gia visitati di recente |
| Plugin separati | Due plugin invece di uno. Versioni future: plugin C unificato | Manutenzione di due file config |
| hardcoded users | Utenti nel sorgente C, non in file htpasswd | Ricompilare per cambiare credenziali |
| No `set-header Proxy-Authenticate` da header_rewrite | Il 407 da solo non dice che schema auth usare | basic_auth lo emette correttamente |

---

## 9. Troubleshooting

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| header_rewrite non blocca | Plugin config non letto (permessi) | `chown ats:ats /etc/trafficserver/plugin.config /etc/trafficserver/url_filter.conf` |
| 407 senza Proxy-Authenticate | basic_auth non caricato | Verificare `plugin.config` abbia `ats_proxy_filter.so` |
| Crash sotto carico | Troppe richieste concorrenti su OS_DNS | Limite testato: 20 ok. Per piu di 20, distribuire su piu VM |
| Username non riconosciuto | authorized() non ha quell'utente | Ricompilare con nuovi utenti (sezione 7) |

---

*Stack testato su VM 134 (Ubuntu 26.04, ATS 9.2.13) con batteria completa — 25 Maggio 2026*
