# Manuale ATS Minimo per Forward Proxy

## Cos'e ATS

Apache Traffic Server e un proxy/cache ad alte prestazioni. In questo progetto viene usato come forward proxy: un client configura ATS come proxy HTTP e ATS inoltra richieste verso Internet.

## Componenti

| Componente | Scopo |
|---|---|
| `traffic_server` | Processo dati: accetta richieste e applica plugin/config. |
| `traffic_manager` | Supervisione e restart. |
| `traffic_ctl` | CLI amministrativa. |
| `plugin.config` | Lista plugin caricati. |
| `records.config` / `records.yaml` | Parametri runtime. |
| `ip_allow.yaml` | ACL sorgenti abilitate. |
| `remap.config` | Mappature reverse proxy; nel forward proxy resta minima. |

## Comandi base

```bash
sudo systemctl status trafficserver
sudo systemctl restart trafficserver
/opt/trafficserver/bin/traffic_server -C verify_config
/opt/trafficserver/bin/traffic_ctl metric get proxy.process.http.current_client_connections
/opt/trafficserver/bin/traffic_top
```

## Log

```bash
sudo tail -f /var/lib/trafficserver/log/trafficserver/diags.log
sudo tail -f /var/lib/trafficserver/log/trafficserver/squid.blog
```

## Debug plugin

```bash
sudo grep ats_proxy_filter /var/lib/trafficserver/log/trafficserver/diags.log
sudo bash scripts/ats-version-report.sh
```

## Regola operativa

ATS core deve funzionare prima del plugin. Se un test fallisce:

1. Disabilita plugin o `MODE off`.
2. Verifica ATS core.
3. Riabilita plugin in `deny`.
4. Solo dopo abilita auth/hardening.
