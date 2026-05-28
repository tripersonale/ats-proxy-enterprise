# Guida Aggiornamento Futuro — ATS Proxy Enterprise v3.0

## 1. Premessa

ATS evolve, il plugin evolve, le distribuzioni Linux cambiano. Questa guida
esiste per dare un percorso verificato di upgrade tra versioni, basato su fatti
reali e non su speculazioni.

**Ambito**: aggiornamento di ATS 9.x → 10.x e ricompilazione del plugin v3.0.

**Versione**: 1.0 — 2026-05-28.

**Fonti dei fatti verificati**:
- VM137 `ats-lab-26-ats10` (Ubuntu 26.04): ATS 10.1.2 build da CMake, plugin v3 build C++17, hardening full 25/25 OK, mode test 11/11 OK.
- VM136 (Ubuntu 26.04): ATS 9.2.13 build da autotools, plugin v3 build C, hardening full 25/25 OK, regression 9/9 OK.
- VM135 (Ubuntu 24.04): ATS 9.2.13 build da autotools, plugin v2.1, hardening full 25/25 OK.

---

## 2. Librerie e dipendenze

| Libreria | Versione testata | Path | ATS 9 | ATS 10 | Note |
|---|---|---|---|---|---|
| PCRE1 | 8.45 | `/usr/local/pcre/lib/libpcre.so`, `/usr/local/pcre/include/pcre.h` | Richiesto | Richiesto | Su Ubuntu 26.04 `libpcre2-dev` NON basta. Compilare da sorgente. Su 24.04 `libpcre3-dev` da apt (8.39) e sufficiente. |
| OpenSSL | 3.x | `/usr/lib/x86_64-linux-gnu/libssl.so` | Usato da ATS | Usato da ATS | Plugin v3 lo usa per SHA-256 (`-lcrypto`). |
| SWOC | Interna ATS | `$ATS_SRC/lib/swoc/include` | Versione ATS 9 | Versione ATS 10 | Cambia tra versioni ATS. E il motivo per cui il plugin va ricompilato a ogni upgrade ATS. |
| libhwloc | Da sistema | `/usr/lib/x86_64-linux-gnu/libhwloc.so` | Richiesto | Richiesto | Pacchetto `libhwloc-dev`. |
| libunwind | Da sistema | `/usr/lib/x86_64-linux-gnu/libunwind.so` | Richiesto | Richiesto | Pacchetto `libunwind-dev`. |

---

## 3. Upgrade ATS (9.x → 10.x)

### 3.1 Cosa cambia

| Area | ATS 9.x | ATS 10.x |
|---|---|---|
| Build system | autotools (`autoreconf -if`, `./configure`, `make`) | CMake (`cmake -S . -B build`, `cmake --build build`, `cmake --install`) |
| Configurazione | `records.config` (formato `key=VALUE`) | `records.yaml` (formato YAML) |
| Header plugin | Installati da `make install` in `/opt/trafficserver/include` | Generati da CMake in `build/include/` + header `ts/apidefs.h` |
| Compilatore plugin | C (`cc`) | C++17 (`c++ -std=c++17`) |
| Forward proxy | `proxy.config.reverse_proxy.enabled 0` + `proxy.config.url_remap.remap_required 0` | `reverse_proxy.enabled: 0` + `url_remap.remap_required: 0` |

### 3.2 Procedura passo-passo

#### Passo 0: Backup

```bash
# Ferma ATS
sudo systemctl stop trafficserver

# Backup completo con data
sudo cp -a /opt/trafficserver /opt/trafficserver.bak-$(date +%Y%m%d)

# Backup config plugin
sudo cp -a /etc/ats-proxy /etc/ats-proxy.bak-$(date +%Y%m%d)

# Salva il plugin corrente
cp /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so \
  ~/ats_proxy_filter_v30.so.bak-$(date +%Y%m%d)
sha256sum ~/ats_proxy_filter_v30.so.bak-$(date +%Y%m%d)
```

#### Passo 1: Installa dipendenze build ATS 10

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake ninja-build pkg-config \
  libssl-dev zlib1g-dev libcap-dev libhwloc-dev \
  libunwind-dev libcurl4-openssl-dev tcl-dev
```

#### Passo 2: Compila PCRE1 (se non gia presente)

```bash
# Verifica se gia installato
ls /usr/local/pcre/lib/libpcre.so 2>/dev/null || {
  cd /tmp
  wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.bz2/download \
    -O pcre-8.45.tar.bz2
  tar -xjf pcre-8.45.tar.bz2
  cd pcre-8.45
  ./configure --prefix=/usr/local/pcre --enable-utf --enable-unicode-properties
  make -j"$(nproc)"
  sudo make install
  sudo ldconfig
}
```

#### Passo 3: Scarica e compila nuova ATS 10

```bash
cd /tmp
wget https://downloads.apache.org/trafficserver/trafficserver-10.1.2.tar.bz2
tar -xjf trafficserver-10.1.2.tar.bz2
cd trafficserver-10.1.2

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/trafficserver \
  -DPCRE_LIBRARY=/usr/local/pcre/lib/libpcre.so \
  -DPCRE_INCLUDE_DIR=/usr/local/pcre/include

cmake --build build -j"$(nproc)"
```

> **Nota**: Se alcuni unit test falliscono (es. `test_PluginFactory`) non e un
> problema: `traffic_server` e gia compilato e funzionante. Procedere
> comunque con l'installazione.

```bash
sudo cmake --install build
```

Verifica:

```bash
/opt/trafficserver/bin/traffic_server -V
# Deve stampare la versione (es. 10.1.2)
```

#### Passo 4: Migra configurazione da ATS 9 a ATS 10

ATS 9 usava `records.config`, ATS 10 usa `records.yaml`. La conversione
automatica completa non e testata. E testata la configurazione manuale
per forward proxy:

```bash
# Backup del file YAML di default
sudo cp /opt/trafficserver/etc/trafficserver/records.yaml \
  /opt/trafficserver/etc/trafficserver/records.yaml.original

# Applica forward proxy: disabilita reverse_proxy e remap_required
sudo python3 -c "
from pathlib import Path
p = Path('/opt/trafficserver/etc/trafficserver/records.yaml')
s = p.read_text()
s = s.replace('  reverse_proxy:\n    enabled: 1', '  reverse_proxy:\n    enabled: 0')
s = s.replace('    remap_required: 1', '    remap_required: 0')
p.write_text(s)
print('Forward proxy config applied')
"
```

> [DA VERIFICARE] Configurazione YAML completa (cache, RAM, thread, DNS,
> logging). La procedura sopra copre solo i due valori essenziali per forward
> proxy. Per valori aggiuntivi consultare la documentazione ATS 10 e tradurre
> manualmente da `records.config` al formato YAML.

#### Passo 5: Verifica L0 e avvio

```bash
# Verifica validita configurazione
sudo /opt/trafficserver/bin/traffic_server -C verify_config

# Avvia ATS
sudo /opt/trafficserver/bin/trafficserver start
sleep 4

# Test base: proxy deve rispondere 200
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
```

Risultato atteso: `200`. Se `404` la config forward proxy non e applicata.
Se `000` ATS non e partito.

#### Passo 6: Ricompila il plugin (vedi Sezione 4)

Il plugin va ricompilato contro gli header della nuova ATS. Procedura alla
Sezione 4.

#### Passo 7: Test e hardening

```bash
# Testa tutti i mode
for mode in off deny whitelist auth_all auth_nd; do
  sudo ATS_PROXY_CONFIG_DIR=/etc/ats-proxy \
    ATS_PROXY_TEMPLATE_DIR=/home/ubuntu/ats-proxy/config \
    bash scripts/ats-mode-test.sh "$mode" 8080 admin testpass
done

# Ri-applica hardening (con adattamenti se necessario)
sudo bash scripts/apply-ats-hardening-v3.sh
sudo ATS_HARDENING_PROFILE=v3 ATS_HARDENING_STAGE=full \
  bash scripts/ats-hardening-check.sh 8080
```

#### Passo 8: Aggiorna documentazione

```bash
# Nella repo ats-proxy:
# - Aggiorna ARTIFACTS.md con hash del nuovo .so
# - Aggiorna TEST_MATRIX.md con risultati test
# - Aggiorna CHANGELOG.md con versione e data
# - Commit e push
```

### 3.3 Rollback se fallisce

```bash
# Ferma ATS
sudo systemctl stop trafficserver

# Ripristina installazione precedente
sudo rm -rf /opt/trafficserver
sudo cp -a /opt/trafficserver.bak-YYYYMMDD /opt/trafficserver

# Ripristina plugin
sudo cp ~/ats_proxy_filter_v30.so.bak-YYYYMMDD \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so

# Ri-avvia
sudo systemctl start trafficserver

# Verifica L0
curl -s -o /dev/null -w '%{http_code}\n' --connect-timeout 5 \
  -x http://127.0.0.1:8080 http://example.com
```

---

## 4. Ricompilazione plugin dopo upgrade ATS

### 4.1 Perche va ricompilato

SWOC (Safe With Object Cache) e una libreria interna di ATS. I suoi header
e simboli cambiano tra versioni. Il plugin v3 include `ts/ts.h` e altri
header ATS che transitivamente includono SWOC — anche se il plugin non
usa direttamente SWOC, la risoluzione dei simboli la richiede.

Risultato: un `.so` compilato per ATS 9.x **non** viene caricato da ATS 10.x
(e viceversa). Va ricompilato ogni volta che ATS cambia versione.

### 4.2 Procedura

```bash
# Clona/aggiorna la repo ats-proxy
git clone https://github.com/tripersonale/ats-proxy-enterprise.git
cd ats-proxy-enterprise

# Compila per ATS 10 (C++17)
bash scripts/compile-plugin.sh \
  --ats-src /tmp/trafficserver-10.1.2 \
  --out bin/ats_proxy_filter_v30.so --cxx

# Compila per ATS 9 (C)
bash scripts/compile-plugin.sh \
  --ats-src /tmp/trafficserver-9.2.13 \
  --out bin/ats_proxy_filter_v30.so --c
```

Lo script `compile-plugin.sh` rileva automaticamente il build system:
- Se `CMakeLists.txt` esiste nella source → modalita `cxx` (ATS 10+).
- Altrimenti → modalita `c` (ATS 9.x).

Se vuoi controllo esplicito, usa `--c` o `--cxx`.

Dopo la compilazione:

```bash
# Installa il plugin
sudo cp bin/ats_proxy_filter_v30.so \
  /opt/trafficserver/libexec/trafficserver/ats_proxy_filter_v30.so

# Registra in plugin.config (se non gia presente)
echo ats_proxy_filter_v30.so | sudo tee \
  /opt/trafficserver/etc/trafficserver/plugin.config > /dev/null

# Riavvia ATS
sudo /opt/trafficserver/bin/trafficserver restart
sleep 4
```

> **Nota**: su ATS 10, `plugin.config` si trova in
> `/opt/trafficserver/etc/trafficserver/plugin.config` (uguale a ATS 9).

### 4.3 Test post-ricompilazione

```bash
# Verifica che il plugin sia caricato
sudo grep "ats_proxy_filter_v30.*plugin loaded" \
  /opt/trafficserver/var/log/trafficserver/diags.log | tail -1

# Testa tutti i mode
for mode in off deny whitelist auth_all auth_nd; do
  echo "=== $mode ==="
  sudo ATS_PROXY_CONFIG_DIR=/etc/ats-proxy \
    ATS_PROXY_TEMPLATE_DIR=$(pwd)/config \
    bash scripts/ats-mode-test.sh "$mode" 8080 admin testpass
done
```

Ogni mode deve mostrare `Passed: N  Failed: 0`.

---

## 5. Upgrade PCRE1

### 5.1 Quando serve

- **Ubuntu 24.04**: `libpcre3-dev` (PCRE1 8.39) e nei repo. Nessuna azione.
- **Ubuntu 26.04**: PCRE1 non e nei repo. Va compilato da sorgente.
- **Ubuntu futura (>26.04)**: se PCRE1 non e nei repo, va ricompilato.

La versione attuale testata e **PCRE 8.45** in `/usr/local/pcre`.

### 5.2 Procedura

```bash
cd /tmp
wget https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.bz2/download \
  -O pcre-8.45.tar.bz2
tar -xjf pcre-8.45.tar.bz2
cd pcre-8.45
./configure --prefix=/usr/local/pcre --enable-utf --enable-unicode-properties
make -j"$(nproc)"
sudo make install
sudo ldconfig
```

Verifica:

```bash
ls /usr/local/pcre/lib/libpcre.so
# Deve esistere
```

Dopo l'upgrade PCRE1, sia ATS che il plugin vanno ricompilati contro
i nuovi header PCRE (ATS) e i nuovi header ATS (plugin).

> [DA VERIFICARE] Nuove major di ATS (11.x, 12.x) potrebbero usare PCRE2
> nativamente. In quel caso PCRE1 non sarebbe piu necessario. Verificare
> nella documentazione di build della versione target.

---

## 6. Cosa e stato testato vs cosa e speculativo

### Testato (fatti verificati su VM reali)

| Cosa | Dove | Quando | Esito |
|---|---|---|---|
| ATS 9.2.13 build (autotools) | VM135 (24.04), VM136 (26.04) | 2026-05-26 | OK |
| ATS 9.2.13 forward proxy | VM135, VM136 | 2026-05-26 | OK |
| ATS 10.1.2 build (CMake) | VM137 (26.04) | 2026-05-27/28 | OK |
| CMake senza PCRE1 → `Could NOT find PCRE` | VM137 | 2026-05-28 | Fallito come previsto |
| PCRE1 8.45 compilato in `/usr/local/pcre` | VM137 | 2026-05-28 | OK |
| ATS 10.1.2 forward proxy (records.yaml) | VM137 | 2026-05-28 | OK, solo `reverse_proxy` e `remap_required` modificati |
| Plugin v3 build C contro ATS 9.2.13 | VM136 | 2026-05-28 | OK |
| Plugin v3 build C++17 contro ATS 10.1.2 | VM137 | 2026-05-27 | OK |
| Plugin v3 5 mode test (`off`, `deny`, `whitelist`, `auth_all`, `auth_nd`) | VM137 | 2026-05-28 | 11/11 OK |
| Hardening core (systemd sandbox, permessi, health check) | VM137 | 2026-05-28 | 19/19 OK |
| Hardening full (UFW, fail2ban, etckeeper) | VM137 | 2026-05-28 | 25/25 OK |
| Plugin v3 5 mode post-hardening | VM137 | 2026-05-28 | 5/5 OK |
| Regression test (9 check) | VM135, VM136 | 2026-05-26 | 9/9 OK |
| Carico 50 richieste concorrenti | VM135, VM136 | 2026-05-26 | 50/50 OK |

### Non testato (speculativo — [DA VERIFICARE])

| Cosa | Note |
|---|---|
| Conversione completa `records.config` → `records.yaml` | Testata solo la modifica di `reverse_proxy.enabled` e `remap_required`. Altri valori (cache, RAM, thread, DNS, logging) vanno tradotti manualmente e testati. |
| TLS frontend su ATS 10 | Il plugin supporta `ATS_TLS_ENABLED=y` su ATS 9. Su ATS 10 la configurazione TLS in `records.yaml` non e stata testata. |
| Plugin v3 build C contro una futura ATS 9.2.14+ | Non ci sono minor successive a 9.2.13 pubblicate su `downloads.apache.org` al 2026-05-26. La build dovrebbe funzionare senza modifiche ma non e testata. |
| Plugin v3 build C++17 contro ATS 10.2+ o 11.x | La build dovrebbe funzionare con gli header generati, ma non e testata. Potrebbero cambiare API interne SWOC. |
| Carico oltre 50 richieste concorrenti | Non validato. |
| Penetration test indipendente | Non eseguito. |

---

## Riferimenti

- `GUIDA_INSTALLAZIONE_ATS_LTS.md` — installazione fresh ATS 10.1.2 (comandi copia-incolla testati su VM137).
- `TEST_MATRIX.md` — matrice completa test VM135/136/137.
- `ARTIFACTS.md` — manifest degli artefatti e hash SHA256.
- `ARCHITETTURA_ATS_PROXY_V3.md` — architettura a livelli e ordine decisionale plugin.
- `scripts/compile-plugin.sh` — script di build plugin (C o C++17, auto-rilevazione).
- `scripts/ats-mode-test.sh` — test 5 mode plugin.
- `scripts/ats-hardening-check.sh` — verifica hardening.
