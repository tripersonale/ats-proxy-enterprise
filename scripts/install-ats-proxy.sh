#!/bin/bash
set -euo pipefail
# ============================================================================
# install-ats-proxy.sh — Automated ATS Proxy Enterprise installer
# Supports Ubuntu 24.04 LTS and 26.04 LTS
# Two modes:
#   1. Config file:  ./install-ats-proxy.sh --config ats-proxy.conf
#   2. Interactive:  ./install-ats-proxy.sh
# ============================================================================

VERSION="1.0"
ATS_VERSION="9.2.13"
ATS_URL="https://downloads.apache.org/trafficserver/trafficserver-${ATS_VERSION}.tar.bz2"
ATS_SHA_URL="${ATS_URL}.sha512"
ATS_SHA512="46c291bc08cf3a73d5d2dd70f006c654c8f91ff5f6d7b28fa539ef2f10147fe27d6fac714b4cec06b3930945db6717b8f4714f990a3b77c1699e11fc218e7766"
ATS_TARBALL="/tmp/trafficserver-${ATS_VERSION}.tar.bz2"
ATS_SHA_FILE="/tmp/trafficserver-${ATS_VERSION}.tar.bz2.sha512"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
HOSTNAME="ats-proxy-01"
IP="192.168.89.100/24"
GATEWAY="192.168.89.254"
DNS="1.1.1.1"
ALLOWED_SUBNET="192.168.89.0/24"
ADMIN_IPS="192.168.89.10"
DENY_DOMAINS="httpbin.org,bad.com,malware.net"
WHITELIST_DOMAINS="google.com,github.com,ubuntu.com,example.com"
AUTH_USERS=""
STATIC_ROUTES=""
PROXY_PORT="8080"
TLS_ENABLED="n"
APPLY_NETPLAN="n"
CONFIG_FILE=""
ENV_FILE=""
PLUGIN_PATH=""
CLI_PLUGIN_PATH=""
NON_INTERACTIVE=false
VALIDATE_ONLY=false

usage() {
  cat << 'EOF'
Usage:
  sudo bash scripts/install-ats-proxy.sh [options]

Options:
  --env FILE            Load ATS_* environment config file
  --config FILE         Load legacy config file
  --plugin FILE         Plugin binary path; overrides ATS_PLUGIN_PATH
  --non-interactive     Do not prompt; fail if required values are missing
  --validate-only       Validate OS, config and plugin path without installing
  -h, --help            Show help
EOF
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ============================================================================
# Parse args
# ============================================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_FILE="$2"; shift 2 ;;
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
    --plugin) PLUGIN_PATH="$2"; CLI_PLUGIN_PATH="$2"; shift 2 ;;
    --validate-only) VALIDATE_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1" ;;
  esac
done

# ============================================================================
# OS Detection
# ============================================================================
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_CODENAME="${UBUNTU_CODENAME:-}"
    OS_VERSION="${VERSION_ID:-}"
  fi
  if [ "$OS_CODENAME" = "noble" ]; then
    OS="2404"
    log "Detected: Ubuntu 24.04 LTS (Noble)"
  elif [ "$OS_CODENAME" = "resolute" ]; then
    OS="2604"
    log "Detected: Ubuntu 26.04 LTS (Resolute)"
  else
    warn "Unknown OS: $OS_CODENAME $OS_VERSION. Assuming 24.04"
    OS="2404"
  fi
}

# ============================================================================
# Load config file or ask interactive
# ============================================================================
load_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    err "Config file not found: $file"
  fi
  log "Loading config: $file"
  # shellcheck source=/dev/null
  source "$file"
}

apply_env_aliases() {
  HOSTNAME="${ATS_HOSTNAME:-$HOSTNAME}"
  IP="${ATS_IP_CIDR:-$IP}"
  GATEWAY="${ATS_GATEWAY:-$GATEWAY}"
  DNS="${ATS_DNS:-$DNS}"
  ALLOWED_SUBNET="${ATS_ALLOWED_SUBNET:-$ALLOWED_SUBNET}"
  ADMIN_IPS="${ATS_ADMIN_IPS:-$ADMIN_IPS}"
  DENY_DOMAINS="${ATS_DENY_DOMAINS:-$DENY_DOMAINS}"
  WHITELIST_DOMAINS="${ATS_WHITELIST_DOMAINS:-$WHITELIST_DOMAINS}"
  AUTH_USERS="${ATS_AUTH_USERS:-$AUTH_USERS}"
  STATIC_ROUTES="${ATS_STATIC_ROUTES:-$STATIC_ROUTES}"
  PROXY_PORT="${ATS_PROXY_PORT:-$PROXY_PORT}"
  APPLY_NETPLAN="${ATS_APPLY_NETPLAN:-$APPLY_NETPLAN}"
  TLS_ENABLED="${ATS_TLS_ENABLED:-$TLS_ENABLED}"
  PLUGIN_PATH="${ATS_PLUGIN_PATH:-$PLUGIN_PATH}"
  PLUGIN_PATH="${CLI_PLUGIN_PATH:-$PLUGIN_PATH}"
}

load_config() {
  local loaded_config=false
  if [ -n "$ENV_FILE" ]; then
    load_file "$ENV_FILE"
    loaded_config=true
  elif [ -f "$REPO_ROOT/ats-proxy.env" ]; then
    load_file "$REPO_ROOT/ats-proxy.env"
    loaded_config=true
  fi

  if [ -n "$CONFIG_FILE" ]; then
    load_file "$CONFIG_FILE"
    loaded_config=true
  fi

  apply_env_aliases

  if [ "$NON_INTERACTIVE" = true ]; then
    return
  fi

  if [ "$loaded_config" = true ]; then
    log "Config loaded. Interactive fallback for missing or placeholder values."
  else
    log "No config file. Interactive mode."
  fi

  echo ""
  prompt_value "HOSTNAME" "Hostname" "$HOSTNAME"
  prompt_value "IP" "IP/CIDR" "$IP"
  prompt_value "GATEWAY" "Gateway" "$GATEWAY"
  prompt_value "DNS" "DNS" "$DNS"
  prompt_value "ALLOWED_SUBNET" "Authorized subnet" "$ALLOWED_SUBNET"
  prompt_value "ADMIN_IPS" "Admin IPs (comma-separated)" "$ADMIN_IPS"
  prompt_value "DENY_DOMAINS" "Denied domains (comma-separated)" "$DENY_DOMAINS"
  prompt_value "WHITELIST_DOMAINS" "Whitelist domains (comma-separated)" "$WHITELIST_DOMAINS"
  prompt_value "AUTH_USERS" "Auth users (user:pass, comma-separated)" "$AUTH_USERS"
  prompt_value "STATIC_ROUTES" "Static routes (net:gw, comma-separated; optional)" "$STATIC_ROUTES" true
  prompt_value "PROXY_PORT" "Proxy port" "$PROXY_PORT"
  prompt_value "APPLY_NETPLAN" "Apply static netplan config?" "$APPLY_NETPLAN"
  prompt_value "TLS_ENABLED" "Enable TLS on port 8443?" "$TLS_ENABLED"
  prompt_value "PLUGIN_PATH" "Plugin path" "$PLUGIN_PATH" true
  echo ""
}

prompt_value() {
  local var_name="$1" label="$2" current="$3" optional="${4:-false}" input
  if [ "$optional" = true ] && [ -n "$current" ] && [[ "$current" != *CHANGE_ME* ]]; then
    return
  fi
  if [ -n "$current" ] && [[ "$current" != *CHANGE_ME* ]]; then
    read -r -p "$label [$current]: " input
    printf -v "$var_name" '%s' "${input:-$current}"
  else
    while true; do
      read -r -p "$label: " input
      if [ -n "$input" ] || [ "$optional" = true ]; then
        printf -v "$var_name" '%s' "$input"
        break
      fi
      warn "$label is required"
    done
  fi
}

download_if_needed() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    log "Using cached $(basename "$dest")"
    return
  fi

  rm -f "$dest" "$dest".*
  if command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -o "$dest" "$url"
  else
    wget --timeout=30 --tries=3 -O "$dest" "$url"
  fi
}

verify_ats_tarball() {
  download_if_needed "$ATS_SHA_URL" "$ATS_SHA_FILE" || printf '%s *trafficserver-%s.tar.bz2\n' "$ATS_SHA512" "$ATS_VERSION" > "$ATS_SHA_FILE"
  if (cd /tmp && sha512sum -c "$(basename "$ATS_SHA_FILE")"); then
    return
  fi

  warn "Cached ATS tarball failed SHA512 verification. Re-downloading once."
  rm -f "$ATS_TARBALL" "$ATS_TARBALL".*
  download_if_needed "$ATS_URL" "$ATS_TARBALL"
  printf '%s *trafficserver-%s.tar.bz2\n' "$ATS_SHA512" "$ATS_VERSION" > "$ATS_SHA_FILE"
  (cd /tmp && sha512sum -c "$(basename "$ATS_SHA_FILE")") || err "ATS tarball SHA512 verification failed"
}

validate_config() {
  local missing=0
  for name in HOSTNAME IP GATEWAY DNS ALLOWED_SUBNET ADMIN_IPS DENY_DOMAINS WHITELIST_DOMAINS AUTH_USERS PROXY_PORT APPLY_NETPLAN TLS_ENABLED; do
    if [ -z "${!name:-}" ]; then
      warn "Missing required value: $name"
      missing=1
    fi
  done

  if [[ "$AUTH_USERS" == *CHANGE_ME* ]]; then
    warn "AUTH_USERS contains CHANGE_ME placeholders"
    missing=1
  fi

  if [[ "$IP" != */* ]]; then
    warn "IP must be CIDR notation, example: 192.168.89.100/24"
    missing=1
  fi

  if [ -z "$PLUGIN_PATH" ]; then
    if [ -f "$REPO_ROOT/ats_proxy_filter_v21.so" ]; then
      PLUGIN_PATH="$REPO_ROOT/ats_proxy_filter_v21.so"
    elif [ -f "$REPO_ROOT/bin/ats_proxy_filter_v21.so" ]; then
      PLUGIN_PATH="$REPO_ROOT/bin/ats_proxy_filter_v21.so"
    fi
  fi

  if [ -z "$PLUGIN_PATH" ] || [ ! -f "$PLUGIN_PATH" ]; then
    warn "Plugin binary not found. Set ATS_PLUGIN_PATH or pass --plugin /path/to/ats_proxy_filter_v21.so"
    missing=1
  fi

  if [ "$missing" -ne 0 ]; then
    err "Configuration validation failed. Fix values before installing. No system changes were made by installer steps."
  fi
}

# ============================================================================
# System preparation
# ============================================================================
prepare_system() {
  log "Setting hostname..."
  sudo hostnamectl set-hostname "$HOSTNAME"

  log "Updating system..."
  sudo apt update -qq && sudo apt upgrade -y -qq

  log "Installing dependencies..."
  local common="build-essential gcc g++ make libtool autoconf automake pkg-config python3-dev libssl-dev libpcre2-dev zlib1g-dev libcap-dev libhwloc-dev libxml2-dev libjson-c-dev libcurl4-openssl-dev libunwind-dev git wget curl tar gzip bzip2"

  if [ "$OS" = "2404" ]; then
    sudo apt install -y -qq $common libpcre3-dev libncurses5-dev
  else
    sudo apt install -y -qq $common libncurses-dev
  fi
  log "Dependencies installed"
}

# ============================================================================
# Network configuration
# ============================================================================
configure_network() {
  if [ "$APPLY_NETPLAN" != "y" ] && [ "$APPLY_NETPLAN" != "Y" ] && [ "$APPLY_NETPLAN" != "s" ] && [ "$APPLY_NETPLAN" != "S" ]; then
    log "Netplan static configuration skipped"
    return
  fi

  local ip_addr="${IP%/*}"
  local cidr="${IP#*/}"

  log "Configuring network: $IP, gateway $GATEWAY, DNS $DNS"
  local CONFIG_FILE="/etc/netplan/01-ats-config.yaml"
  sudo tee "$CONFIG_FILE" > /dev/null << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $(ip -o link show | grep -v lo | head -1 | awk '{print $2}' | sed 's/:$//'):
      dhcp4: no
      addresses:
        - ${IP}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS}]
EOF

  # Static routes
  if [ -n "$STATIC_ROUTES" ]; then
    log "Adding static routes..."
    IFS=',' read -ra ROUTES <<< "$STATIC_ROUTES"
    for route in "${ROUTES[@]}"; do
      if [[ "$route" != *:* ]]; then
        warn "Skipping invalid static route '$route' (expected net:gw)"
        continue
      fi
      local net="${route%:*}"
      local gw="${route#*:}"
      sudo perl -0pi -e "s/(        - to: default\n          via: ${GATEWAY}\n)/\$1        - to: ${net}\n          via: ${gw}\n/" "$CONFIG_FILE"
    done
  fi

  sudo netplan apply 2>/dev/null || warn "netplan apply failed (may need reboot)"
  log "Network configured"
}

# ============================================================================
# Create ats user
# ============================================================================
create_ats_user() {
  log "Creating ats user..."
  sudo groupadd --system ats 2>/dev/null || true
  sudo useradd --system --gid ats --home-dir /opt/trafficserver --shell /usr/sbin/nologin ats 2>/dev/null || true
}

# ============================================================================
# Compile ATS
# ============================================================================
compile_ats() {
  log "Downloading ATS ${ATS_VERSION}..."
  download_if_needed "$ATS_URL" "$ATS_TARBALL"
  verify_ats_tarball

  cd /tmp
  rm -rf "trafficserver-${ATS_VERSION}"
  tar -xjf "$ATS_TARBALL"
  cd "trafficserver-${ATS_VERSION}"

  # PCRE1 for 26.04
  if [ "$OS" = "2604" ]; then
    log "Compiling PCRE1 from source (required on 26.04)..."
    cd /tmp
    download_if_needed https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz /tmp/pcre-8.45.tar.gz
    rm -rf pcre-8.45
    tar xzf pcre-8.45.tar.gz && cd pcre-8.45
    ./configure --prefix=/usr/local/pcre --enable-utf8 --enable-unicode-properties -q
    make -j$(nproc) -s && sudo make install -s
    echo '/usr/local/pcre/lib' | sudo tee /etc/ld.so.conf.d/pcre.conf > /dev/null
    sudo ldconfig
    cd "/tmp/trafficserver-${ATS_VERSION}"
  fi

  log "Configuring ATS..."
  autoreconf -if -q 2>/dev/null || true

  local configure_opts="--prefix=/opt/trafficserver --sysconfdir=/etc/trafficserver --localstatedir=/var/lib/trafficserver --runstatedir=/run/trafficserver --with-user=ats --with-group=ats --disable-tests --disable-examples --disable-maintainer-mode"

  if [ "$OS" = "2404" ]; then
    ./configure $configure_opts --enable-pcre -q
  else
    export PKG_CONFIG_PATH='/usr/local/pcre/lib/pkgconfig'
    ./configure $configure_opts --with-pcre=/usr/local/pcre -q
  fi

  log "Compiling ATS (5-15 minutes)..."
  make -j$(nproc) -s
  sudo make install -s

  echo "/opt/trafficserver/lib" | sudo tee /etc/ld.so.conf.d/trafficserver.conf > /dev/null
  sudo ldconfig
  log "ATS compiled and installed"
}

# ============================================================================
# Configure ATS
# ============================================================================
configure_ats() {
  log "Creating directories..."
  sudo mkdir -p /run/trafficserver /var/log/trafficserver /var/lib/trafficserver/cache
  sudo mkdir -p /var/lib/trafficserver/log/trafficserver
  sudo chown -R ats:ats /opt/trafficserver /etc/trafficserver /var/lib/trafficserver
  sudo chown ats:ats /run/trafficserver /var/log/trafficserver

  log "Writing records.config..."
  sudo tee /etc/trafficserver/records.config > /dev/null << EOF
CONFIG proxy.config.http.server_ports STRING ${PROXY_PORT}
CONFIG proxy.config.proxy_name STRING ${HOSTNAME}
CONFIG proxy.config.task_threads INT -1
CONFIG proxy.config.net.connections_throttle INT 30000
CONFIG proxy.config.net.max_connections_in INT 30000
CONFIG proxy.config.log.logging_enabled INT 3
CONFIG proxy.config.log.max_space_mb_for_logs INT 10000
CONFIG proxy.config.log.rolling_enabled INT 1
CONFIG proxy.config.log.rolling_interval_sec INT 86400
CONFIG proxy.config.log.auto_delete_rolled_files INT 1
CONFIG proxy.config.dns.nameservers STRING NULL
CONFIG proxy.config.dns.resolv_conf STRING /etc/resolv.conf
CONFIG proxy.config.dns.lookup_timeout INT 30
CONFIG proxy.config.http.insert_client_ip INT 1
CONFIG proxy.config.cache.ram_cache.size INT 1073741824
CONFIG proxy.config.http.push_method_enabled INT 0
CONFIG proxy.config.diags.debug.enabled INT 0
CONFIG proxy.config.url_remap.remap_required INT 0
CONFIG proxy.config.reverse_proxy.enabled INT 0
CONFIG proxy.config.http.flow_control.enabled INT 1
CONFIG proxy.config.http.per_server.connection.max INT 100
EOF

  log "Writing ip_allow.yaml..."
  sudo tee /etc/trafficserver/ip_allow.yaml > /dev/null << EOF
---
ip_allow:
  - apply: in
    ip_addrs: 127.0.0.1
    action: allow
    method: ALL
  - apply: in
    ip_addrs: ::1
    action: allow
    method: ALL
  - apply: in
    ip_addrs: ${ALLOWED_SUBNET}
    action: allow
    method: GET|POST|CONNECT|HEAD|PUT|DELETE|OPTIONS
  - apply: in
    ip_addrs: 0.0.0.0-255.255.255.255
    action: deny
    method: ALL
EOF

  log "Writing logging.yaml..."
  sudo tee /etc/trafficserver/logging.yaml > /dev/null << EOF
---
logging:
  formats:
    - name: audit
      format: '%<chi> %<caun> [%<cqtn>] "%<cqtx>" %<pssc> %<pscl> %<{Host}cqh> %<shn>'
      interval: 1
  logs:
    - filename: audit
      format: audit
      mode: ascii
      rolling_enabled: 1
      rolling_interval_sec: 86400
EOF

  sudo touch /etc/trafficserver/remap.config
  echo '/var/lib/trafficserver/cache 10G' | sudo tee /etc/trafficserver/storage.config > /dev/null

  sudo chown ats:ats /etc/trafficserver/*
  sudo chmod 640 /etc/trafficserver/*.config /etc/trafficserver/*.yaml
  log "ATS configuration written"
}

# ============================================================================
# Plugin v2.1 config
# ============================================================================
configure_plugin() {
  log "Writing plugin config..."

  local tmp_conf
  tmp_conf=$(mktemp)

  # Build ADMIN lines
  IFS=',' read -ra ADMINS <<< "$ADMIN_IPS"
  for ip in "${ADMINS[@]}"; do
    [ -n "$ip" ] && printf 'ADMIN %s\n' "$ip" >> "$tmp_conf"
  done

  # Build DENY lines
  IFS=',' read -ra DENIES <<< "$DENY_DOMAINS"
  for d in "${DENIES[@]}"; do
    [ -n "$d" ] && printf 'DENY %s\n' "$d" >> "$tmp_conf"
  done

  # Build WHITELIST lines
  IFS=',' read -ra WHITES <<< "$WHITELIST_DOMAINS"
  for w in "${WHITES[@]}"; do
    [ -n "$w" ] && printf 'WHITELIST %s\n' "$w" >> "$tmp_conf"
  done

  # Build USER lines
  IFS=',' read -ra USERS_LIST <<< "$AUTH_USERS"
  for entry in "${USERS_LIST[@]}"; do
    [ -n "$entry" ] || continue
    if [[ "$entry" != *:* ]]; then
      warn "Skipping invalid auth user '$entry' (expected user:password)"
      continue
    fi
    local u="${entry%:*}"
    local p="${entry#*:}"
    printf 'USER %s %s\n' "$u" "$p" >> "$tmp_conf"
  done

  sudo install -o ats -g ats -m 640 "$tmp_conf" /etc/trafficserver/ats_proxy_filter.conf
  rm -f "$tmp_conf"

  sudo tee /etc/trafficserver/plugin.config > /dev/null << EOF
ats_proxy_filter.so
EOF

  sudo chown ats:ats /etc/trafficserver/ats_proxy_filter.conf /etc/trafficserver/plugin.config
  log "Plugin config written"
}

# ============================================================================
# Deploy plugin binary
# ============================================================================
deploy_plugin() {
  log "Deploying plugin..."
  sudo mkdir -p /opt/trafficserver/libexec/trafficserver
  sudo install -o ats -g ats -m 755 "$PLUGIN_PATH" /opt/trafficserver/libexec/trafficserver/ats_proxy_filter.so

  log "Plugin deployed"
}

# ============================================================================
# Systemd service
# ============================================================================
configure_systemd() {
  log "Creating systemd service..."
  sudo tee /etc/systemd/system/trafficserver.service > /dev/null << EOF
[Unit]
Description=Apache Traffic Server
Documentation=https://trafficserver.apache.org/
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
User=ats
Group=ats
RuntimeDirectory=trafficserver
ExecStart=/opt/trafficserver/bin/trafficserver start
ExecStop=/opt/trafficserver/bin/trafficserver stop
ExecReload=/opt/trafficserver/bin/trafficserver restart
KillMode=control-group
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
LimitNPROC=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=trafficserver
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/trafficserver /var/lib/trafficserver /var/log/trafficserver
ReadOnlyPaths=/opt/trafficserver
PrivateTmp=true
PrivateDevices=true
NoNewPrivileges=true
MemoryHigh=2G
MemoryMax=3G
CPUQuota=400%

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable trafficserver
  sudo systemctl start trafficserver
  sleep 3
  log "Systemd service created and started"
}

# ============================================================================
# Hardening
# ============================================================================
apply_hardening() {
  log "Applying hardening..."

  # UFW
  sudo ufw default deny incoming 2>/dev/null || true
  sudo ufw default allow outgoing 2>/dev/null || true
  sudo ufw allow 22/tcp comment 'SSH' 2>/dev/null || true
  sudo ufw allow from ${ALLOWED_SUBNET} to any port ${PROXY_PORT} proto tcp comment 'ATS-proxy' 2>/dev/null || true
  echo 'y' | sudo ufw enable 2>/dev/null || true

  # SSH
  sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
MaxAuthTries 3
MaxSessions 10
EOF
  sudo systemctl restart ssh 2>/dev/null || true

  # fail2ban
  sudo apt install -y -qq fail2ban 2>/dev/null || true
  sudo tee /etc/fail2ban/filter.d/ats-proxy.conf > /dev/null << 'EOF'
[Definition]
failregex = \[ats_proxy_filter\] AUTH FAIL .* from <HOST>
ignoreregex =
EOF
  sudo mkdir -p /etc/fail2ban/jail.d
  sudo tee /etc/fail2ban/jail.d/ats-proxy.local > /dev/null << FEOF
[sshd]
enabled = true
port = ssh
maxretry = 3
bantime = 86400

[ats-proxy]
enabled = true
port = ${PROXY_PORT}
filter = ats-proxy
logpath = /var/lib/trafficserver/log/trafficserver/diags.log
maxretry = 5
findtime = 300
bantime = 3600
FEOF
  sudo systemctl enable fail2ban 2>/dev/null || true
  sudo systemctl restart fail2ban 2>/dev/null || true

  # unattended-upgrades
  sudo apt install -y -qq unattended-upgrades 2>/dev/null || true
  sudo systemctl enable --now unattended-upgrades 2>/dev/null || true

  # etckeeper
  sudo apt install -y -qq etckeeper 2>/dev/null || true
  sudo etckeeper init 2>/dev/null || true
  sudo etckeeper commit "Initial ATS proxy deployment" 2>/dev/null || true

  # sysctl network hardening
  sudo tee /etc/sysctl.d/99-ats-hardening.conf > /dev/null << 'EOF'
net.ipv4.ip_forward=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.log_martians=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_rfc1337=1
kernel.sysrq=0
kernel.core_pattern=|/bin/false
EOF
  sudo sysctl -p /etc/sysctl.d/99-ats-hardening.conf >/dev/null 2>&1 || true

  # CVE monitor helper
  if [ -f "$REPO_ROOT/scripts/cve-check.sh" ]; then
    sudo install -o root -g root -m 750 "$REPO_ROOT/scripts/cve-check.sh" /opt/cve-check.sh
  fi

  log "Hardening applied"
}

# ============================================================================
# Health check
# ============================================================================
configure_health_check() {
  log "Configuring health check..."
  sudo tee /opt/ats_health.sh > /dev/null << HEOF
#!/bin/bash
HTTP=\$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x http://127.0.0.1:${PROXY_PORT} http://httpbin.org/ip 2>/dev/null)
STATUS=\$(systemctl is-active trafficserver)
echo "[\$(date -Is)] ATS=\$STATUS HTTP=\$HTTP" >> /var/log/ats-health.log
if [ "\$HTTP" != "200" ] && [ "\$HTTP" != "403" ] && [ "\$HTTP" != "407" ]; then
  echo "[\$(date -Is)] ALERT: proxy unhealthy HTTP=\$HTTP, restarting" >> /var/log/ats-health.log
  /bin/systemctl restart trafficserver
fi
HEOF
  sudo chmod +x /opt/ats_health.sh
  sudo touch /var/log/ats-health.log
  sudo chown root:adm /var/log/ats-health.log 2>/dev/null || sudo chown root:root /var/log/ats-health.log
  sudo chmod 640 /var/log/ats-health.log
  (sudo crontab -l 2>/dev/null; echo '* * * * * /opt/ats_health.sh') | sudo crontab - 2>/dev/null || true
  log "Health check configured (every 60s)"
}

# ============================================================================
# TLS (optional)
# ============================================================================
configure_tls() {
  if [ "$TLS_ENABLED" != "y" ] && [ "$TLS_ENABLED" != "Y" ] && [ "$TLS_ENABLED" != "s" ] && [ "$TLS_ENABLED" != "S" ]; then
    log "TLS skipped"
    return
  fi

  log "Configuring TLS on port 8443..."
  sudo mkdir -p /etc/trafficserver/certs
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/trafficserver/certs/proxy.key \
    -out /etc/trafficserver/certs/proxy.crt \
    -subj "/CN=${HOSTNAME}" 2>/dev/null
  sudo chown -R ats:ats /etc/trafficserver/certs

  sudo tee /etc/trafficserver/ssl_multicert.config > /dev/null << EOF
dest_ip=* ssl_cert_name=/etc/trafficserver/certs/proxy.crt ssl_key_name=/etc/trafficserver/certs/proxy.key
EOF

  sudo sed -i "s/server_ports STRING ${PROXY_PORT}/server_ports STRING ${PROXY_PORT} 8443:ssl/" /etc/trafficserver/records.config
  sudo ufw allow from ${ALLOWED_SUBNET} to any port 8443 proto tcp comment 'ATS-TLS-proxy' 2>/dev/null || true
  sudo systemctl restart trafficserver
  sleep 3
  log "TLS configured on port 8443 (self-signed). Replace certs in /etc/trafficserver/certs/ for production."
}

# ============================================================================
# Verification
# ============================================================================
verify() {
  log "Running verification tests..."

  local ok=0 fail=0
  test_case() {
    local desc="$1" expected="$2" url="$3" extra_args="${4:-}"
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x "http://127.0.0.1:${PROXY_PORT}" ${extra_args} "$url" 2>/dev/null || echo "000")
    if [ "$code" = "$expected" ]; then
      log "  OK $desc ($code)"
      ok=$((ok + 1))
    else
      warn "  FAIL $desc (got $code, expected $expected)"
      fail=$((fail + 1))
    fi
  }

  test_case "DENY rule" "403" "http://httpbin.org/ip"
  test_case "Whitelist pass" "301" "http://google.com"
  test_case "Auth required" "407" "http://wikipedia.org"
  log "Verification complete: $ok passed, $fail failed"
}

# ============================================================================
# Main
# ============================================================================
main() {
  echo "============================================"
  echo " ATS Proxy Enterprise Installer v${VERSION}"
  echo "============================================"
  echo ""

  detect_os
  load_config
  validate_config

  if [ "$VALIDATE_ONLY" = true ]; then
    log "Validation complete. No installation performed."
    exit 0
  fi

  log "Starting installation on ${OS_CODENAME}..."
  log "Host: ${HOSTNAME} | IP: ${IP} | Port: ${PROXY_PORT}"

  prepare_system
  configure_network
  create_ats_user
  compile_ats
  configure_ats
  configure_plugin
  deploy_plugin
  configure_systemd
  apply_hardening
  configure_health_check
  configure_tls
  verify

  echo ""
  echo "============================================"
  log "Installation complete!"
  log "Proxy:  http://${IP%/*}:${PROXY_PORT}"
  log "Config: /etc/trafficserver/ats_proxy_filter.conf"
  log "Logs:   /var/lib/trafficserver/log/trafficserver/audit.log"
  log "Health: /var/log/ats-health.log"
  echo "============================================"
}

main "$@"
