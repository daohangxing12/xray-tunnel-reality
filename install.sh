#!/usr/bin/env bash
set -Eeuo pipefail

# xray-tunnel-reality
# Interactive installer for:
#   1) 3x-ui style tunnel -> local VLESS Reality Vision
#   2) SOCKS5 inbound

MODE=""
PUBLIC_PORT=""
INNER_PORT=""
UUID_VALUE=""
SNI_VALUE="www.tesla.com"
SHORT_ID=""
NAME=""
SOCKS_USER=""
SOCKS_PASS=""
SOCKS_UDP="false"
FORCE=0
NON_INTERACTIVE=0
SKIP_XRAY_INSTALL=0

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
fail() { red "[ERROR] $*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  bash install.sh
  bash install.sh --mode reality --port 56777 --inner-port 4431 --sni www.tesla.com
  bash install.sh --mode socks5 --port 21109 --user nt --pass nt888888

Options:
  --mode reality|socks5     Protocol to install. Omit for interactive menu.
  --port PORT               Public listen port. Defaults: reality=56777, socks5=21109
  --inner-port PORT         Local Reality port. Default: 4431, only for reality mode.
  --sni DOMAIN              Reality SNI/target domain. Default: www.tesla.com
  --uuid UUID               VLESS UUID. If omitted, generate randomly.
  --short-id HEX            Reality shortId. If omitted, generate random 8 hex chars.
  --name NAME               Client link remark.
  --user USER               SOCKS5 username. Omit for interactive/random.
  --pass PASS               SOCKS5 password. Omit for interactive/random.
  --udp true|false          Enable SOCKS5 UDP. Default: false.
  --yes                     Non-interactive, use defaults/random values.
  --skip-xray-install       Use existing /usr/local/bin/xray.
  --force                   Continue if target port appears busy.
  -h, --help                Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --port) PUBLIC_PORT="${2:-}"; shift 2 ;;
    --inner-port) INNER_PORT="${2:-}"; shift 2 ;;
    --sni) SNI_VALUE="${2:-}"; shift 2 ;;
    --uuid) UUID_VALUE="${2:-}"; shift 2 ;;
    --short-id) SHORT_ID="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --user) SOCKS_USER="${2:-}"; shift 2 ;;
    --pass) SOCKS_PASS="${2:-}"; shift 2 ;;
    --udp) SOCKS_UDP="${2:-}"; shift 2 ;;
    --yes|-y) NON_INTERACTIVE=1; shift ;;
    --skip-xray-install) SKIP_XRAY_INSTALL=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

is_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 )); }
is_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]] && [[ "$1" != .* ]] && [[ "$1" != *. ]]; }
is_uuid() { [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }
is_short_id() { [[ "$1" =~ ^[0-9a-fA-F]{2,16}$ ]] && (( ${#1} % 2 == 0 )); }
random_hex() { openssl rand -hex "${1:-4}"; }
random_user() { printf 'u%s' "$(random_hex 3)"; }
random_pass() { openssl rand -base64 18 | tr -d '/+=' | cut -c1-16; }

ask() {
  local prompt="$1" default="$2" value=""
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    printf '%s' "$default"
    return
  fi
  read -r -p "$prompt [$default]: " value || true
  printf '%s' "${value:-$default}"
}

choose_mode() {
  if [[ -n "$MODE" ]]; then return; fi
  if [[ "$NON_INTERACTIVE" == "1" ]]; then MODE="reality"; return; fi
  echo "请选择安装协议:"
  echo "  1) VLESS Reality Vision（3x-ui tunnel结构）"
  echo "  2) SOCKS5"
  local choice
  read -r -p "输入 1 或 2 [1]: " choice || true
  case "${choice:-1}" in
    1) MODE="reality" ;;
    2) MODE="socks5" ;;
    *) fail "Invalid choice: $choice" ;;
  esac
}

need_root() { [[ "$(id -u)" == "0" ]] || fail "Please run as root."; }

install_deps() {
  local missing=()
  for c in curl unzip openssl sed awk grep systemctl ss; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if (( ${#missing[@]} == 0 )); then return; fi
  info "Installing dependencies: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl unzip openssl iproute2 ca-certificates procps
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl unzip openssl iproute ca-certificates procps-ng
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip openssl iproute ca-certificates procps-ng
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl unzip openssl iproute2 ca-certificates procps
  else
    fail "Unsupported package manager. Install curl unzip openssl iproute2 manually."
  fi
}

install_xray() {
  if [[ "$SKIP_XRAY_INSTALL" == "1" ]]; then
    [[ -x /usr/local/bin/xray ]] || command -v xray >/dev/null 2>&1 || fail "xray not found, remove --skip-xray-install."
    return
  fi
  info "Installing or updating Xray from XTLS official installer..."
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install || fail "Xray install failed."
  [[ -x /usr/local/bin/xray ]] || fail "Xray binary missing after install."
}

gen_uuid() {
  if [[ -x /usr/local/bin/xray ]]; then /usr/local/bin/xray uuid 2>/dev/null | head -n1 && return; fi
  if command -v xray >/dev/null 2>&1; then xray uuid 2>/dev/null | head -n1 && return; fi
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z' && return; fi
  cat /proc/sys/kernel/random/uuid
}

gen_x25519() {
  local out priv pub
  out="$(/usr/local/bin/xray x25519 2>/dev/null || xray x25519 2>/dev/null || true)"
  priv="$(printf '%s\n' "$out" | awk -F': ' '/Private/{print $2; exit}')"
  pub="$(printf '%s\n' "$out" | awk -F': ' '/Password|Public/{print $2; exit}')"
  [[ -n "$priv" && -n "$pub" ]] || fail "Failed to generate X25519 key pair. Raw output: $out"
  PRIVATE_KEY="$priv"
  PUBLIC_KEY="$pub"
}

get_public_ip() {
  local ip=""
  ip="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(curl -fsS4 --max-time 5 https://ip.sb 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$ip"
}

urlencode_remark() {
  local raw="$1"
  python3 - <<PY 2>/dev/null || printf '%s' "$raw"
import urllib.parse
print(urllib.parse.quote('''$raw'''))
PY
}

check_port_free() {
  local port="$1"
  if ss -lntup 2>/dev/null | grep -Eq "[:.]${port}[[:space:]]"; then
    if [[ "$FORCE" != "1" ]]; then
      ss -lntup 2>/dev/null | grep -E "[:.]${port}[[:space:]]" || true
      fail "Port $port is already listening. Use another --port or stop the existing service."
    fi
    yellow "Port $port appears busy, continuing because --force was set."
  fi
}

prepare_reality_values() {
  PUBLIC_PORT="${PUBLIC_PORT:-$(ask '公网 tunnel 端口' '56777')}"
  INNER_PORT="${INNER_PORT:-$(ask '本机 Reality 端口' '4431')}"
  SNI_VALUE="${SNI_VALUE:-www.tesla.com}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then SNI_VALUE="$(ask 'SNI/Reality target' "$SNI_VALUE")"; fi
  NAME="${NAME:-Tunnel-Reality}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then NAME="$(ask '节点名称' "$NAME")"; fi
  [[ -n "$UUID_VALUE" ]] || UUID_VALUE="$(gen_uuid)"
  [[ -n "$SHORT_ID" ]] || SHORT_ID="$(random_hex 4)"
  is_port "$PUBLIC_PORT" || fail "Invalid --port: $PUBLIC_PORT"
  is_port "$INNER_PORT" || fail "Invalid --inner-port: $INNER_PORT"
  [[ "$PUBLIC_PORT" != "$INNER_PORT" ]] || fail "Public port and inner port must be different."
  is_domain "$SNI_VALUE" || fail "Invalid SNI: $SNI_VALUE"
  is_uuid "$UUID_VALUE" || fail "Invalid UUID: $UUID_VALUE"
  is_short_id "$SHORT_ID" || fail "Invalid shortId: $SHORT_ID"
}

prepare_socks_values() {
  PUBLIC_PORT="${PUBLIC_PORT:-$(ask 'SOCKS5 端口' '21109')}"
  NAME="${NAME:-SOCKS5}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then NAME="$(ask '节点名称' "$NAME")"; fi
  SOCKS_USER="${SOCKS_USER:-$(ask 'SOCKS5 用户名' "$(random_user)")}"
  SOCKS_PASS="${SOCKS_PASS:-$(ask 'SOCKS5 密码' "$(random_pass)")}"
  SOCKS_UDP="${SOCKS_UDP:-false}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then SOCKS_UDP="$(ask '是否启用 UDP true/false' "$SOCKS_UDP")"; fi
  [[ "$SOCKS_UDP" == "true" || "$SOCKS_UDP" == "false" ]] || fail "--udp must be true or false"
  is_port "$PUBLIC_PORT" || fail "Invalid --port: $PUBLIC_PORT"
  [[ -n "$SOCKS_USER" && -n "$SOCKS_PASS" ]] || fail "SOCKS5 username/password cannot be empty."
}

write_reality_config() {
  local dir=/etc/xray-tunnel-reality
  mkdir -p "$dir"
  chmod 755 "$dir"
  cat > "$dir/config.json" <<JSON
{
  "log": {"access": "none", "error": "", "loglevel": "warning"},
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {"type": "field", "domain": ["$SNI_VALUE"], "inboundTag": ["inbound-$PUBLIC_PORT"], "outboundTag": "direct"},
      {"type": "field", "inboundTag": ["inbound-$PUBLIC_PORT"], "outboundTag": "blocked"},
      {"type": "field", "outboundTag": "blocked", "ip": ["geoip:private"]},
      {"type": "field", "outboundTag": "blocked", "protocol": ["bittorrent"]}
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PUBLIC_PORT,
      "protocol": "tunnel",
      "settings": {"address": "127.0.0.1", "port": $INNER_PORT, "portMap": {}, "network": "tcp,udp", "followRedirect": false},
      "tag": "inbound-$PUBLIC_PORT",
      "sniffing": {"enabled": true, "destOverride": ["tls"], "metadataOnly": false, "routeOnly": true}
    },
    {
      "listen": "127.0.0.1",
      "port": $INNER_PORT,
      "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID_VALUE", "flow": "xtls-rprx-vision", "email": "default@tunnel-reality"}], "decryption": "none"},
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "tcpSettings": {"acceptProxyProtocol": false, "header": {"type": "none"}},
        "realitySettings": {"show": false, "target": "$SNI_VALUE:443", "xver": 0, "serverNames": ["$SNI_VALUE"], "privateKey": "$PRIVATE_KEY", "shortIds": ["$SHORT_ID"]}
      },
      "tag": "inbound-127.0.0.1:$INNER_PORT",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "metadataOnly": false, "routeOnly": true}
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}},
    {"tag": "blocked", "protocol": "blackhole", "settings": {}}
  ],
  "policy": {"levels": {"0": {"statsUserDownlink": true, "statsUserUplink": true}}, "system": {"statsInboundDownlink": true, "statsInboundUplink": true}},
  "stats": {}
}
JSON
  chmod 600 "$dir/config.json"
}

write_socks_config() {
  local dir=/etc/xray-tunnel-reality
  mkdir -p "$dir"
  chmod 755 "$dir"
  cat > "$dir/config.json" <<JSON
{
  "log": {"access": "none", "error": "", "loglevel": "warning"},
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {"type": "field", "outboundTag": "blocked", "ip": ["geoip:private"]},
      {"type": "field", "outboundTag": "blocked", "protocol": ["bittorrent"]}
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PUBLIC_PORT,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [{"user": "$SOCKS_USER", "pass": "$SOCKS_PASS"}],
        "udp": $SOCKS_UDP,
        "ip": "127.0.0.1"
      },
      "tag": "socks-$PUBLIC_PORT",
      "sniffing": {"enabled": false, "destOverride": ["http", "tls", "quic", "fakedns"], "metadataOnly": false, "routeOnly": false}
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}},
    {"tag": "blocked", "protocol": "blackhole", "settings": {}}
  ]
}
JSON
  chmod 600 "$dir/config.json"
}

write_service() {
  cat > /etc/systemd/system/xray-tunnel-reality.service <<'SERVICE'
[Unit]
Description=Xray Tunnel Reality Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -c /etc/xray-tunnel-reality/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable xray-tunnel-reality >/dev/null
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
    ufw allow "$PUBLIC_PORT"/tcp >/dev/null 2>&1 || true
    ufw allow "$PUBLIC_PORT"/udp >/dev/null 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$PUBLIC_PORT"/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port="$PUBLIC_PORT"/udp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}

start_service() {
  info "Testing Xray config..."
  /usr/local/bin/xray run -test -c /etc/xray-tunnel-reality/config.json >/tmp/xray-tunnel-reality-test.log 2>&1 || {
    cat /tmp/xray-tunnel-reality-test.log
    fail "Xray config test failed."
  }
  write_service
  open_firewall
  systemctl restart xray-tunnel-reality
  sleep 1
  systemctl is-active --quiet xray-tunnel-reality || {
    systemctl status xray-tunnel-reality --no-pager || true
    fail "Service failed to start."
  }
}

print_reality_result() {
  local ip remark link
  ip="$(get_public_ip)"
  remark="$(urlencode_remark "$NAME")"
  link="vless://${UUID_VALUE}@${ip}:${PUBLIC_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI_VALUE}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F&type=tcp&headerType=none#${remark}"
  green "Reality install completed."
  cat <<EOF

================ VLESS Reality ================
Public listen:       ${ip}:${PUBLIC_PORT}
Relay target:        ${ip}:${PUBLIC_PORT}
Local Reality:       127.0.0.1:${INNER_PORT}
UUID:                ${UUID_VALUE}
SNI:                 ${SNI_VALUE}
Public key:          ${PUBLIC_KEY}
Short ID:            ${SHORT_ID}
Service:             xray-tunnel-reality
Config:              /etc/xray-tunnel-reality/config.json

Client link:
${link}
================================================
EOF
}

print_socks_result() {
  local ip link remark
  ip="$(get_public_ip)"
  remark="$(urlencode_remark "$NAME")"
  link="socks://${SOCKS_USER}:${SOCKS_PASS}@${ip}:${PUBLIC_PORT}#${remark}"
  green "SOCKS5 install completed."
  cat <<EOF

================ SOCKS5 ================
Public listen:       ${ip}:${PUBLIC_PORT}
Relay target:        ${ip}:${PUBLIC_PORT}
Username:            ${SOCKS_USER}
Password:            ${SOCKS_PASS}
UDP:                 ${SOCKS_UDP}
Service:             xray-tunnel-reality
Config:              /etc/xray-tunnel-reality/config.json

SOCKS5 URL:
${link}
========================================
EOF
}

main() {
  need_root
  choose_mode
  [[ "$MODE" == "reality" || "$MODE" == "socks5" ]] || fail "--mode must be reality or socks5"
  install_deps
  install_xray

  if [[ "$MODE" == "reality" ]]; then
    prepare_reality_values
    gen_x25519
    check_port_free "$PUBLIC_PORT"
    check_port_free "$INNER_PORT"
    write_reality_config
    start_service
    print_reality_result
  else
    prepare_socks_values
    check_port_free "$PUBLIC_PORT"
    write_socks_config
    start_service
    print_socks_result
  fi
}

main "$@"