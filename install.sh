#!/usr/bin/env bash
set -Eeuo pipefail

# xray-tunnel-reality
# 3x-ui style front tunnel inbound -> local VLESS Reality Vision inbound.

PUBLIC_PORT=56777
INNER_PORT=4431
UUID_VALUE=""
SNI_VALUE=""
SHORT_ID=""
NAME="Tunnel-Reality"
FORCE=0
SKIP_XRAY_INSTALL=0

SNI_POOL=(
  "www.icloud.com"
  "www.apple.com"
  "developer.apple.com"
  "www.microsoft.com"
  "www.tesla.com"
  "www.cloudflare.com"
)

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
fail() { red "[ERROR] $*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  bash install.sh [options]

Options:
  --port PORT             Public tunnel listen port. Default: 56777
  --inner-port PORT       Local Reality listen port. Default: 4431
  --sni DOMAIN            Reality SNI/target domain. If omitted, choose randomly.
  --uuid UUID             VLESS UUID. If omitted, generate randomly.
  --short-id HEX          Reality shortId. If omitted, generate random 8 hex chars.
  --name NAME             Client link remark. Default: Tunnel-Reality
  --skip-xray-install     Use existing /usr/local/bin/xray.
  --force                 Overwrite even if config directory exists.
  -h, --help              Show this help.

Examples:
  bash install.sh
  bash install.sh --sni www.icloud.com --port 56777
  bash install.sh --uuid ecfb... --sni www.icloud.com
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PUBLIC_PORT="${2:-}"; shift 2 ;;
    --inner-port) INNER_PORT="${2:-}"; shift 2 ;;
    --sni) SNI_VALUE="${2:-}"; shift 2 ;;
    --uuid) UUID_VALUE="${2:-}"; shift 2 ;;
    --short-id) SHORT_ID="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
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

is_port "$PUBLIC_PORT" || fail "Invalid --port: $PUBLIC_PORT"
is_port "$INNER_PORT" || fail "Invalid --inner-port: $INNER_PORT"
[[ "$PUBLIC_PORT" != "$INNER_PORT" ]] || fail "Public port and inner port must be different."

if [[ -z "$SNI_VALUE" ]]; then
  idx=$(( RANDOM % ${#SNI_POOL[@]} ))
  SNI_VALUE="${SNI_POOL[$idx]}"
fi
is_domain "$SNI_VALUE" || fail "Invalid SNI: $SNI_VALUE"

need_root() {
  [[ "$(id -u)" == "0" ]] || fail "Please run as root."
}

install_deps() {
  local missing=()
  for c in curl unzip openssl sed awk grep systemctl ss; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
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
    command -v xray >/dev/null 2>&1 || [[ -x /usr/local/bin/xray ]] || fail "xray not found, remove --skip-xray-install."
    return
  fi
  info "Installing or updating Xray from XTLS official installer..."
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install || fail "Xray install failed."
  [[ -x /usr/local/bin/xray ]] || fail "Xray binary missing after install."
}

gen_uuid() {
  if command -v xray >/dev/null 2>&1; then
    xray uuid 2>/dev/null | head -n1 && return
  fi
  if [[ -x /usr/local/bin/xray ]]; then
    /usr/local/bin/xray uuid 2>/dev/null | head -n1 && return
  fi
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z' && return
  fi
  cat /proc/sys/kernel/random/uuid
}

gen_short_id() {
  openssl rand -hex 4
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

write_config() {
  local dir=/etc/xray-tunnel-reality
  mkdir -p "$dir"
  chmod 755 "$dir"
  cat > "$dir/config.json" <<JSON
{
  "log": {
    "access": "none",
    "error": "",
    "loglevel": "warning"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "domain": ["$SNI_VALUE"],
        "inboundTag": ["inbound-$PUBLIC_PORT"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "inboundTag": ["inbound-$PUBLIC_PORT"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "ip": ["geoip:private"]
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": ["bittorrent"]
      }
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PUBLIC_PORT,
      "protocol": "tunnel",
      "settings": {
        "address": "127.0.0.1",
        "port": $INNER_PORT,
        "portMap": {},
        "network": "tcp,udp",
        "followRedirect": false
      },
      "tag": "inbound-$PUBLIC_PORT",
      "sniffing": {
        "enabled": true,
        "destOverride": ["tls"],
        "metadataOnly": false,
        "routeOnly": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": $INNER_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID_VALUE",
            "flow": "xtls-rprx-vision",
            "email": "default@tunnel-reality"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "tcpSettings": {
          "acceptProxyProtocol": false,
          "header": {"type": "none"}
        },
        "realitySettings": {
          "show": false,
          "target": "$SNI_VALUE:443",
          "xver": 0,
          "serverNames": ["$SNI_VALUE"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      },
      "tag": "inbound-127.0.0.1:$INNER_PORT",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false,
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {"domainStrategy": "UseIPv4"}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true
    }
  },
  "stats": {}
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

main() {
  need_root
  install_deps
  install_xray

  [[ -n "$UUID_VALUE" ]] || UUID_VALUE="$(gen_uuid)"
  is_uuid "$UUID_VALUE" || fail "Invalid UUID: $UUID_VALUE"

  [[ -n "$SHORT_ID" ]] || SHORT_ID="$(gen_short_id)"
  is_short_id "$SHORT_ID" || fail "Invalid shortId: $SHORT_ID"

  gen_x25519
  check_port_free "$PUBLIC_PORT"
  check_port_free "$INNER_PORT"
  write_config

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

  local ip remark link
  ip="$(get_public_ip)"
  remark="$(urlencode_remark "$NAME")"
  link="vless://${UUID_VALUE}@${ip}:${PUBLIC_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI_VALUE}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F&type=tcp&headerType=none#${remark}"

  green "Install completed."
  cat <<EOF

================ Tunnel Reality ================
Public listen:       ${ip}:${PUBLIC_PORT}
Forward target:      ${ip}:${PUBLIC_PORT}
Local Reality:       127.0.0.1:${INNER_PORT}
UUID:                ${UUID_VALUE}
SNI:                 ${SNI_VALUE}
Public key:          ${PUBLIC_KEY}
Short ID:            ${SHORT_ID}
Service:             xray-tunnel-reality
Config:              /etc/xray-tunnel-reality/config.json

Client link:
${link}

Relay panel target should be:
${ip}:${PUBLIC_PORT}
================================================
EOF
}

main "$@"