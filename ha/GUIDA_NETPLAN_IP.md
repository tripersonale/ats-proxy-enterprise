# Configurazione IP Linux via netplan — Guida Rapida

## Ubuntu 24.04 LTS e 26.04 LTS

**Versione 1.0 — 28 Maggio 2026**

---

## Perche netplan

Da Ubuntu 18.04+, la configurazione di rete si fa con **netplan** (YAML in `/etc/netplan/`).
Ha sostituito `/etc/network/interfaces`. Non usare ifupdown e netplan insieme: confliggono.

Questa guida copre gli scenari usati nel deploy ATS + keepalived:
- Da cloud image (DHCP) a IP statico
- Due VM gemelle con IP statici fissi
- VIP escluso da netplan (gestito da keepalived)

---

## 0. Prima di iniziare: scopri la rete attuale

```bash
# 1. Interfacce e IP correnti
ip -br a
# Output: lo UNKNOWN 127.0.0.1/8
#         eth0 UP 192.168.1.100/24 (DHCP) ...

# 2. Gateway corrente
ip route | grep default
# Output: default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.100

# 3. DNS correnti (systemd-resolved)
resolvectl status | grep "DNS Servers"
# Output: DNS Servers: 192.168.1.1

# 4. File netplan esistenti
ls -la /etc/netplan/
# Tipico: 50-cloud-init.yaml (se VM da cloud image)
#         Oppure: 00-installer-config.yaml (se installazione interattiva)
```

---

## 1. Scenario Base: IP Statico su Singola Interfaccia

Usato per ogni VM ATS che partecipa al cluster keepalived.

### 1.1 File netplan

```bash
# Rinomina il file cloud-init se presente (altrimenti confligge)
sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.disabled 2>/dev/null

# Crea la configurazione
sudo tee /etc/netplan/99-ats.yaml > /dev/null << 'EOF'
network:
  version: 2
  ethernets:
    eth0:                         # <-- Sostituire con l'interfaccia reale
      dhcp4: false
      addresses:
        - 192.168.1.31/24         # <-- IP statico della VM
      routes:
        - to: default
          via: 192.168.1.1        # <-- Gateway
      nameservers:
        addresses:
          - 1.1.1.1               # <-- DNS primario
          - 8.8.8.8               # <-- DNS secondario
EOF
```

### 1.2 Applica

```bash
# Testa la configurazione (rollback automatico dopo 120s se non confermi)
sudo netplan try
# Premi INVIO entro 120s per confermare

# Oppure applica direttamente (senza periodo di test)
sudo netplan apply
```

### 1.3 Verifica

```bash
ip -br a | grep eth0
# Atteso: eth0 UP 192.168.1.31/24
ping -c 2 192.168.1.1
nslookup google.com
```

---

## 2. Scenario: Due VM ATS Gemelle (MASTER + BACKUP)

Stessa configurazione netplan, IP diversi.

### VM ATS-1 (MASTER — IP .31)

```yaml
# /etc/netplan/99-ats.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.1.31/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

### VM ATS-2 (BACKUP — IP .32)

```yaml
# /etc/netplan/99-ats.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.1.32/24          # Unica differenza
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

> **⚠️ Il VIP (es. 192.168.1.99) NON va in netplan.**
> Viene aggiunto/rimosso dinamicamente da keepalived. Se lo metti in netplan,
> appare su entrambe le VM contemporaneamente → conflitto IP.

---

## 3. Scenario: Cloud Image (DHCP) → IP Statico

Le cloud image Ubuntu partono in DHCP. Per passare a IP statico:

```bash
# 1. Disabilita cloud-init per la rete (impedisce che riscriva netplan)
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg > /dev/null << 'EOF'
network: {config: disabled}
EOF

# 2. Rimuovi/rinomina il file netplan generato da cloud-init
sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.disabled

# 3. Crea il file netplan come sopra
sudo tee /etc/netplan/99-ats.yaml > /dev/null << 'EOF'
network:
  version: 2
  ethernets:
    ens18:                        # Le cloud image usano tipicamente ens18
      dhcp4: false
      addresses:
        - 192.168.1.31/24
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
EOF

# 4. Genera e applica
sudo netplan generate
sudo netplan apply
```

> **Nota**: il nome dell'interfaccia sulle cloud image Proxmox e tipicamente `ens18`.
> Verifica sempre con `ip -br a` prima di scrivere il file netplan.

---

## 4. Nomi Interfaccia — Riferimento Rapido

| Ambiente | Nome tipico | Come scoprirlo |
|----------|------------|----------------|
| VM Proxmox (cloud image) | `ens18` | `ip -br a \| grep -v lo` |
| VM Proxmox (ISO install) | `ens18` o `enp0s3` | `ip -br a \| grep -v lo` |
| VM VirtualBox | `enp0s3` | `ip -br a \| grep -v lo` |
| Bare metal | `eno1`, `enp2s0` | `ip -br a \| grep -v lo` |
| LXC container | `eth0` | `ip -br a \| grep -v lo` |
| VM VMware | `ens192` | `ip -br a \| grep -v lo` |

---

## 5. DNS: systemd-resolved vs netplan

Su Ubuntu 24.04+, il DNS e gestito da `systemd-resolved`.
Netplan popola `/run/systemd/resolve/stub-resolv.conf`.

```bash
# Verifica che systemd-resolved funzioni
resolvectl status

# Forza l'uso dei DNS configurati in netplan
sudo netplan apply

# Test DNS
resolvectl query google.com
# Atteso: google.com: 142.250.x.x ...
```

Se i DNS non funzionano dopo netplan apply:

```bash
sudo systemctl restart systemd-resolved
sudo netplan apply
```

---

## 6. Rollback e Recovery

### 6.1 Se netplan try fallisce

Se non confermi entro 120 secondi, netplan fa rollback automatico.
Se hai applicato con `netplan apply` e la VM e irraggiungibile:

```bash
# Dalla console Proxmox (o accesso fisico):
# 1. Verifica i file netplan
sudo cat /etc/netplan/99-ats.yaml

# 2. Se il file ha errori, ripristina DHCP temporaneo
sudo tee /etc/netplan/99-ats.yaml > /dev/null << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
sudo netplan apply

# 3. Verifica
ip -br a
ping -c 2 8.8.8.8
```

### 6.2 Ripristinare cloud-init (se disabilitato)

```bash
sudo rm /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo mv /etc/netplan/50-cloud-init.yaml.disabled /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

---

## 7. Troubleshooting Netplan

| Problema | Causa | Soluzione |
|----------|-------|-----------|
| `netplan apply` non cambia nulla | File duplicati in `/etc/netplan/` | Rimuovere o rinominare i file in conflitto (es. `50-cloud-init.yaml`) |
| | Errore di sintassi YAML | `sudo netplan try` mostra l'errore |
| Interfaccia sbagliata dopo apply | Nome interfaccia errato nel file | `ip -br a` per trovare il nome corretto |
| DNS non risolvono | `systemd-resolved` non aggiornato | `sudo systemctl restart systemd-resolved` |
| Gateway non raggiungibile | `routes.via` errato | `ip route \| grep default` prima di applicare |
| VM perde connettivita dopo apply | Gateway o subnet errati | Recupero via console: ripristina DHCP temporaneo (Sezione 6.1) |
| `netplan try` non fa rollback | Timeout troppo breve o comando gia confermato | Usa `--timeout 120` per 120 secondi |
| File YAML ignorato | Permessi errati | `sudo chmod 600 /etc/netplan/*.yaml` richiesto da netplan |

### 7.1 Comandi diagnostici rapidi

```bash
# Configurazione netplan corrente (come la interpreta il sistema)
sudo netplan get all

# Verifica sintassi senza applicare
sudo netplan generate --debug

# Informazioni di sistema sulle interfacce
networkctl status eth0

# File di configurazione attivi
sudo netplan ip leases eth0   # Se DHCP

# Trovare conflitti tra file netplan
sudo netplan apply --debug 2>&1 | grep -i error
```

---

## 8. Checklist Pre-Keepalived

Prima di procedere con keepalived, verifica su OGNI VM:

- [ ] `ip -br a` mostra l'IP statico corretto
- [ ] `ping -c 2 <gateway>` funziona
- [ ] `ping -c 2 <altra-vm-ats>` funziona (es. da .31 ping .32)
- [ ] `nslookup google.com` risolve
- [ ] `ip route | grep default` mostra il gateway corretto
- [ ] `/etc/netplan/` NON contiene il VIP (nessun file YAML con 192.168.1.99)
- [ ] `/etc/netplan/` ha UN solo file `.yaml` attivo (gli altri rinominati `.disabled`)
- [ ] `sudo netplan try --timeout 10` non mostra errori

---

*Riferimenti: [GUIDA_INSTALLAZIONE_KEEPALIVED.md](./GUIDA_INSTALLAZIONE_KEEPALIVED.md), [GUIDA_INSTALLAZIONE.md](../GUIDA_INSTALLAZIONE.md)*
