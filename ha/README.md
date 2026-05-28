# High Availability per ATS Proxy

Documentazione per il deploy in alta affidabilita di Apache Traffic Server
con keepalived + VRRP + health check.

## Documenti

| File | Contenuto |
|------|-----------|
| [GUIDA_INSTALLAZIONE_KEEPALIVED.md](./GUIDA_INSTALLAZIONE_KEEPALIVED.md) | Guida completa: architettura VRRP, installazione, configurazione MASTER/BACKUP, health check, hardening, troubleshooting |
| [GUIDA_NETPLAN_IP.md](./GUIDA_NETPLAN_IP.md) | Configurazione IP statico via netplan su Ubuntu 24.04/26.04 |

## Flusso di installazione

1. **netplan** → Configura IP statici su ogni VM (GUIDA_NETPLAN_IP.md)
2. **ATS** → Installa ATS su ogni VM (riferimento: ../GUIDA_INSTALLAZIONE.md)
3. **keepalived** → HA con VRRP + health check (GUIDA_INSTALLAZIONE_KEEPALIVED.md)

## Architettura

```
Client ---> VIP (.99) ---> [ATS-1 MASTER] o [ATS-2 BACKUP]
```

Il VIP segue la VM con ATS attivo e priorita piu alta. Failover in <3 secondi.
