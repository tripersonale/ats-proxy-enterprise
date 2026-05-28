# ATS Proxy Enterprise - Guida Log E SIEM

Documento corrente ricreato in root. La versione storica completa resta in `archive/storico/`; questa versione allinea percorsi e stato alla baseline 0.13.0.

## Log Locali

| Log | Percorso | Scopo |
|-----|----------|-------|
| Audit ATS | `/opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log` | richieste proxy |
| Diagnostics ATS | `/opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log` | plugin, errori, load |
| Health | `/var/log/ats-health.log` | stato health check |
| Journal | `journalctl -u trafficserver` | servizio systemd |

## Formato Audit Validato

```text
%<chi> %<caun> [%<cqtn>] "%<cqtx>" %<pssc> %<pscl> %<{Host}cqh> %<shn>
```

Campi principali:

- IP client;
- utente autenticato se disponibile;
- timestamp;
- request line;
- status;
- byte;
- Host header;
- hostname upstream.

## Comandi Operativi

```bash
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
sudo tail -f /opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log
sudo grep ' 403 ' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
sudo grep ' 407 ' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log
sudo grep 'ats_proxy_filter' /opt/trafficserver/opt/trafficserver/var/log/trafficserver/diags.log | tail -50
```

## Forwarding Rsyslog Esempio

```bash
sudo tee /etc/rsyslog.d/40-ats-audit.conf >/dev/null <<'EOF'
module(load="imfile")
input(type="imfile"
      File="/opt/trafficserver/opt/trafficserver/var/log/trafficserver/audit.log"
      Tag="ats-audit"
      Severity="info"
      Facility="local6")
local6.* @@SIEM_IP:514
EOF
sudo systemctl restart rsyslog
```

Da validare per ogni SIEM reale: TLS syslog, certificati, parsing e retention.

## Privacy

La baseline logga host/FQDN e request line HTTP. Per ambienti GDPR/NIS2 definire retention, minimizzazione e accessi in `REGISTRO_TRATTAMENTI_v1.0.md` e `DPIA_v1.0.md`.
