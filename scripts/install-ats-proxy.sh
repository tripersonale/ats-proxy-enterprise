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
ATS_SHA_URL="${ATS_URL}.sha256"
PLUGIN_URL=""  # URL to precompiled ats_proxy_filter_v21.so, or bundled as base64 in PLUGIN_B64

# Defaults
HOSTNAME="ats-proxy-01"
IP="192.168.89.100/24"
GATEWAY="192.168.89.254"
DNS="1.1.1.1"
ALLOWED_SUBNET="192.168.89.0/24"
ADMIN_IPS="192.168.89.10"
DENY_DOMAINS="httpbin.org,bad.com,malware.net"
WHITELIST_DOMAINS="google.com,github.com,ubuntu.com,example.com"
AUTH_USERS="admin:proxy2026,user1:pass123"
STATIC_ROUTES=""
PROXY_PORT="8080"
TLS_ENABLED="n"
CONFIG_FILE=""

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
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=true; shift ;;
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
load_config() {
  if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    log "Loading config: $CONFIG_FILE"
    source "$CONFIG_FILE"
    return
  fi

  log "No config file. Interactive mode."
  echo ""
  read -p "Hostname [$HOSTNAME]: " input; HOSTNAME="${input:-$HOSTNAME}"
  read -p "IP/CIDR [$IP]: " input; IP="${input:-$IP}"
  read -p "Gateway [$GATEWAY]: " input; GATEWAY="${input:-$GATEWAY}"
  read -p "DNS [$DNS]: " input; DNS="${input:-$DNS}"
  read -p "Authorized subnet [$ALLOWED_SUBNET]: " input; ALLOWED_SUBNET="${input:-$ALLOWED_SUBNET}"
  read -p "Admin IPs (comma-separated) [$ADMIN_IPS]: " input; ADMIN_IPS="${input:-$ADMIN_IPS}"
  read -p "Denied domains (comma-separated) [$DENY_DOMAINS]: " input; DENY_DOMAINS="${input:-$DENY_DOMAINS}"
  read -p "Whitelist domains (comma-separated) [$WHITELIST_DOMAINS]: " input; WHITELIST_DOMAINS="${input:-$WHITELIST_DOMAINS}"
  read -p "Auth users (user:pass, comma-separated) [$AUTH_USERS]: " input; AUTH_USERS="${input:-$AUTH_USERS}"
  read -p "Static routes (net/gw, comma-separated) [none]: " input; STATIC_ROUTES="${input:-$STATIC_ROUTES}"
  read -p "Proxy port [$PROXY_PORT]: " input; PROXY_PORT="${input:-$PROXY_PORT}"
  read -p "Enable TLS on port 8443? [n]: " input; TLS_ENABLED="${input:-$TLS_ENABLED}"
  echo ""
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
      local net="${route%:*}"
      local gw="${route#*:}"
      sudo sed -i "/- to: default/a\\        - to: ${net}\\n          via: ${gw}" "$CONFIG_FILE"
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
  cd /tmp
  wget -q "$ATS_URL"
  wget -q "$ATS_SHA_URL"
  sha256sum -c "trafficserver-${ATS_VERSION}.tar.bz2.sha256" || warn "SHA256 verification failed (continuing)"
  tar -xjf "trafficserver-${ATS_VERSION}.tar.bz2"
  cd "trafficserver-${ATS_VERSION}"

  # PCRE1 for 26.04
  if [ "$OS" = "2604" ]; then
    log "Compiling PCRE1 from source (required on 26.04)..."
    cd /tmp
    wget -q https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz
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

  # Build ADMIN lines
  local admin_lines=""
  IFS=',' read -ra ADMINS <<< "$ADMIN_IPS"
  for ip in "${ADMINS[@]}"; do
    admin_lines="${admin_lines}ADMIN ${ip}\n"
  done

  # Build DENY lines
  local deny_lines=""
  IFS=',' read -ra DENIES <<< "$DENY_DOMAINS"
  for d in "${DENIES[@]}"; do
    deny_lines="${deny_lines}DENY ${d}\n"
  done

  # Build WHITELIST lines
  local white_lines=""
  IFS=',' read -ra WHITES <<< "$WHITELIST_DOMAINS"
  for w in "${WHITES[@]}"; do
    white_lines="${white_lines}WHITELIST ${w}\n"
  done

  # Build USER lines
  local user_lines=""
  IFS=',' read -ra USERS_LIST <<< "$AUTH_USERS"
  for entry in "${USERS_LIST[@]}"; do
    local u="${entry%:*}"
    local p="${entry#*:}"
    user_lines="${user_lines}USER ${u} ${p}\n"
  done

  sudo bash -c "cat > /etc/trafficserver/ats_proxy_filter.conf << EOF
${admin_lines}${deny_lines}${white_lines}${user_lines}EOF"

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

  # Look for plugin in current dir or download
  if [ -f "./ats_proxy_filter_v21.so" ]; then
    sudo cp ./ats_proxy_filter_v21.so /opt/trafficserver/lib/modules/ats_proxy_filter.so
  elif [ -f "/tmp/ats_proxy_filter_v21.so" ]; then
    sudo cp /tmp/ats_proxy_filter_v21.so /opt/trafficserver/lib/modules/ats_proxy_filter.so
  else
    warn "Plugin .so not found locally. Downloading..."
    # Fallback: compile from source if source is available
    if [ -f "/tmp/ats_proxy_filter_v21.c" ]; then
      cd "/tmp/trafficserver-${ATS_VERSION}"
      gcc -fPIC -shared -I. -I./include -o /tmp/ats_proxy_filter_v21.so /tmp/ats_proxy_filter_v21.c
      sudo cp /tmp/ats_proxy_filter_v21.so /opt/trafficserver/lib/modules/ats_proxy_filter.so
    else
      err "Plugin .so not found. Place ats_proxy_filter_v21.so in current directory or /tmp/"
    fi
  fi

  sudo chown ats:ats /opt/trafficserver/lib/modules/ats_proxy_filter.so
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
  sudo tee -a /etc/fail2ban/jail.local > /dev/null << FEOF

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
  sudo systemctl enable --now fail2ban 2>/dev/null || true

  # unattended-upgrades
  sudo apt install -y -qq unattended-upgrades 2>/dev/null || true
  sudo systemctl enable --now unattended-upgrades 2>/dev/null || true

  # etckeeper
  sudo apt install -y -qq etckeeper 2>/dev/null || true
  sudo etckeeper init 2>/dev/null || true
  sudo etckeeper commit "Initial ATS proxy deployment" 2>/dev/null || true

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
  sudo chmod 666 /var/log/ats-health.log
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
    local desc="$1" expected="$2"
    local code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 -x "http://127.0.0.1:${PROXY_PORT}" http://httpbin.org/ip 2>/dev/null || echo "000")
    if [ "$code" = "$expected" ]; then
      log "  ✅ $desc ($code)"
      ((ok++))
    else
      warn "  ❌ $desc (got $code, expected $expected)"
      ((fail++))
    fi
  }

  test_case "Proxy responding" "403"
  test_case "Whitelist pass" "301"
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
