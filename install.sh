#!/usr/bin/env bash
set -Eeuo pipefail

# xray-tunnel-reality
# Panel-free Xray manager:
#   1) VLESS Reality Vision with a 3x-ui-like tunnel layer
#   2) SOCKS5 inbound
#   3) Cloudflare preferred entry VLESS + WebSocket

SERVICE_NAME="xray-tunnel-reality"
CONFIG_DIR="/etc/xray-tunnel-reality"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATE_FILE="${CONFIG_DIR}/state.json"
LOCAL_SCRIPT="/usr/local/bin/xray-tunnel-reality"
SHORTCUT="/usr/local/bin/xrt"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/daohangxing12/xray-tunnel-reality/main/install.sh"
BBR_CONF="/etc/sysctl.d/99-xray-tunnel-reality-bbr.conf"

MODE=""
ACTION=""
PUBLIC_PORT=""
INNER_PORT=""
UUID_VALUE=""
SNI_VALUE="www.icloud.com"
SHORT_ID=""
NAME=""
PRIVATE_KEY=""
PUBLIC_KEY=""
SOCKS_USER=""
SOCKS_PASS=""
SOCKS_UDP="false"
CF_DOMAIN=""
CF_ENTRY=""
WS_PATH=""
REMOVE_TAG=""
FORCE=0
NON_INTERACTIVE=0
SKIP_XRAY_INSTALL=0
XRAY_VERSION="v26.6.27"
FORCE_XRAY_INSTALL=0
ENABLE_BBR=1

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
fail() { red "[ERROR] $*"; exit 1; }

usage() {
  cat <<'USAGE'
Usage:
  bash install.sh
  bash install.sh --mode reality --yes
  bash install.sh --mode socks5 --yes
  bash install.sh --mode cf-ws --cf-domain host.example.com --cf-entry cf.example.com
  xrt --show
  xrt --status
  xrt --restart
  xrt --uninstall

Install modes:
  --mode reality|socks5|cf-ws
  --port PORT              Public/origin listen port. Default: random high port.
  --inner-port PORT        Local Reality port. Default: 4431, only for reality.
  --sni DOMAIN             Reality SNI/target domain. Default: www.icloud.com
  --uuid UUID              VLESS UUID. If omitted, generate randomly.
  --short-id HEX           Reality shortId. If omitted, generate random 8 hex chars.
  --private-key KEY        Reality server private key. Omit to generate randomly.
  --public-key KEY         Optional expected public key. Must match --private-key.
  --name NAME              Client link remark. Default: COUNTRY-PROTOCOL.
  --user USER              SOCKS5 username. Omit for random.
  --pass PASS              SOCKS5 password. Omit for random.
  --udp true|false         Enable SOCKS5 UDP. Default: false.
  --cf-domain DOMAIN       Cloudflare proxied domain used as WS Host/SNI.
  --cf-entry HOST_OR_IP    Client address, usually preferred IP/domain. Default: --cf-domain.
  --path PATH              WebSocket path for cf-ws. Default: random path.

Manager actions:
  --show                   Show all saved client links.
  --status                 Show service and node status.
  --logs                   Show recent service logs.
  --start                  Start service.
  --stop                   Stop service.
  --restart                Restart service.
  --remove-node TAG        Remove one saved node by tag.
  --uninstall              Remove service/config, keep Xray binary and xrt command.
  --full-uninstall         Also remove xrt/local script. Xray binary is still kept.
  --enable-bbr             Enable BBR and fq now.

Other options:
  --xray-version VERSION   Xray version to install. Default: v26.6.27. Use "latest" for latest.
  --latest-xray            Install or update to latest Xray release.
  --force-xray-install     Force official Xray installer.
  --skip-xray-install      Use existing /usr/local/bin/xray.
  --no-bbr                 Do not enable BBR during install.
  --force                  Continue when a port appears busy.
  --yes, -y                Non-interactive, use defaults/random values.
  -h, --help               Show this help.
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
    --private-key) PRIVATE_KEY="${2:-}"; shift 2 ;;
    --public-key) PUBLIC_KEY="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --user) SOCKS_USER="${2:-}"; shift 2 ;;
    --pass) SOCKS_PASS="${2:-}"; shift 2 ;;
    --udp) SOCKS_UDP="${2:-}"; shift 2 ;;
    --cf-domain|--host) CF_DOMAIN="${2:-}"; shift 2 ;;
    --cf-entry|--address) CF_ENTRY="${2:-}"; shift 2 ;;
    --path|--ws-path) WS_PATH="${2:-}"; shift 2 ;;
    --remove-node) ACTION="remove-node"; REMOVE_TAG="${2:-}"; shift 2 ;;
    --xray-version) XRAY_VERSION="${2:-}"; shift 2 ;;
    --latest-xray) XRAY_VERSION=""; shift ;;
    --force-xray-install) FORCE_XRAY_INSTALL=1; shift ;;
    --yes|-y) NON_INTERACTIVE=1; shift ;;
    --skip-xray-install) SKIP_XRAY_INSTALL=1; shift ;;
    --no-bbr) ENABLE_BBR=0; shift ;;
    --enable-bbr) ACTION="enable-bbr"; shift ;;
    --show|--link|--links) ACTION="show"; shift ;;
    --status) ACTION="status"; shift ;;
    --logs|--log) ACTION="logs"; shift ;;
    --start) ACTION="start"; shift ;;
    --stop) ACTION="stop"; shift ;;
    --restart) ACTION="restart"; shift ;;
    --uninstall|--remove) ACTION="uninstall"; shift ;;
    --full-uninstall|--purge) ACTION="full-uninstall"; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

case "$MODE" in
  cfws|cf|cloudflare|vless-ws) MODE="cf-ws" ;;
  vless|vless-reality) MODE="reality" ;;
  socks|socks5) MODE="socks5" ;;
  uninstall|remove) ACTION="uninstall"; MODE="" ;;
  full-uninstall|purge) ACTION="full-uninstall"; MODE="" ;;
esac

is_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 )); }
is_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+$ ]] && [[ "$1" == *.* ]] && [[ "$1" != .* ]] && [[ "$1" != *. ]]; }
is_host_or_ip() { [[ "$1" =~ ^[A-Za-z0-9.:-]+$ ]] && [[ -n "$1" ]]; }
is_uuid() { [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }
is_short_id() { [[ "$1" =~ ^[0-9a-fA-F]{2,16}$ ]] && (( ${#1} % 2 == 0 )); }
is_x25519_key() { [[ "$1" =~ ^[A-Za-z0-9_-]{40,64}$ ]]; }
is_path() { [[ "$1" == /* ]] && [[ "$1" != *' '* ]]; }
random_hex() { openssl rand -hex "${1:-4}"; }
random_user() { printf 'u%s' "$(random_hex 3)"; }
random_pass() { openssl rand -base64 18 | tr -d '/+=' | cut -c1-16; }
random_ws_path() { printf '/ws%s' "$(random_hex 4)"; }

random_high_port() {
  local i hex num port
  for ((i = 0; i < 80; i++)); do
    hex="$(openssl rand -hex 2 2>/dev/null || true)"
    if [[ -n "$hex" ]]; then
      num=$((16#$hex))
    else
      num=$RANDOM
    fi
    port=$((20000 + (num % 40000)))
    if ! ss -lntup 2>/dev/null | grep -Eq "[:.]${port}[[:space:]]" && ! state_port_in_use "$port"; then
      printf '%s' "$port"
      return
    fi
  done
  printf '%s' "$((20000 + (RANDOM % 32768)))"
}

ask() {
  local prompt="$1" default="$2" value=""
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    printf '%s' "$default"
    return
  fi
  read -r -p "$prompt [$default]: " value || true
  printf '%s' "${value:-$default}"
}

ask_required() {
  local prompt="$1" value=""
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    printf '%s' ""
    return
  fi
  while [[ -z "$value" ]]; do
    read -r -p "$prompt: " value || true
  done
  printf '%s' "$value"
}

pause() {
  [[ "$NON_INTERACTIVE" == "1" ]] && return
  read -r -p "按回车继续..." _ || true
}

need_root() { [[ "$(id -u)" == "0" ]] || fail "Please run as root."; }

install_deps() {
  local missing=()
  for c in curl unzip openssl sed awk grep systemctl ss python3 sysctl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if (( ${#missing[@]} == 0 )); then return; fi
  info "Installing dependencies: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl unzip openssl iproute2 ca-certificates procps python3
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl unzip openssl iproute ca-certificates procps-ng python3
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl unzip openssl iproute ca-certificates procps-ng python3
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl unzip openssl iproute2 ca-certificates procps python3
  else
    fail "Unsupported package manager. Install curl unzip openssl iproute2 procps python3 manually."
  fi
}

normalize_xray_version() {
  local version="$1"
  case "$version" in
    ""|latest|LATEST) printf '%s' ""; return ;;
  esac
  [[ "$version" == v* ]] || version="v${version}"
  [[ "$version" =~ ^v[0-9]+(\.[0-9]+){1,2}$ ]] || fail "Invalid --xray-version: $1"
  printf '%s' "$version"
}

current_xray_version() {
  local bin=""
  if [[ -x /usr/local/bin/xray ]]; then
    bin="/usr/local/bin/xray"
  else
    bin="$(command -v xray 2>/dev/null || true)"
  fi
  [[ -n "$bin" ]] || return 0
  ("$bin" version 2>/dev/null || "$bin" -version 2>/dev/null) | awk 'NR==1 {version=$2; sub(/^v/, "", version); print "v" version; exit}'
}

xray_data_ready() {
  [[ -s /usr/local/share/xray/geoip.dat ]]
}

install_xray() {
  if [[ "$SKIP_XRAY_INSTALL" == "1" ]]; then
    [[ -x /usr/local/bin/xray ]] || command -v xray >/dev/null 2>&1 || fail "xray not found, remove --skip-xray-install."
    return
  fi
  local installer_args current_version
  installer_args=(install)
  XRAY_VERSION="$(normalize_xray_version "$XRAY_VERSION")"
  current_version="$(current_xray_version || true)"

  if [[ -n "$XRAY_VERSION" ]]; then
    info "Installing Xray ${XRAY_VERSION} from XTLS official installer..."
    installer_args+=(--version "$XRAY_VERSION")
    if [[ "$current_version" == "$XRAY_VERSION" && "$FORCE_XRAY_INSTALL" != "1" ]]; then
      if xray_data_ready; then
        info "Xray ${XRAY_VERSION} is already installed."
        [[ -x /usr/local/bin/xray ]] || fail "Xray binary missing."
        return
      fi
      yellow "Xray ${XRAY_VERSION} is installed, but geoip.dat is missing. Reinstalling to restore data files."
      installer_args+=(-f)
    fi
  else
    info "Installing or updating latest Xray from XTLS official installer..."
  fi

  if [[ "$FORCE_XRAY_INSTALL" == "1" ]]; then
    installer_args+=(-f)
  fi

  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ "${installer_args[@]}" || fail "Xray install failed."
  [[ -x /usr/local/bin/xray ]] || fail "Xray binary missing after install."
}

gen_uuid() {
  if [[ -x /usr/local/bin/xray ]]; then /usr/local/bin/xray uuid 2>/dev/null | head -n1 && return; fi
  if command -v xray >/dev/null 2>&1; then xray uuid 2>/dev/null | head -n1 && return; fi
  if command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z' && return; fi
  cat /proc/sys/kernel/random/uuid
}

gen_x25519() {
  local out priv pub derived_pub
  if [[ -n "$PRIVATE_KEY" ]]; then
    is_x25519_key "$PRIVATE_KEY" || fail "Invalid --private-key format."
    out="$(/usr/local/bin/xray x25519 -i "$PRIVATE_KEY" 2>/dev/null || xray x25519 -i "$PRIVATE_KEY" 2>/dev/null || true)"
    derived_pub="$(printf '%s\n' "$out" | awk -F': *' '/Password|Public/{print $2; exit}')"
    [[ -n "$derived_pub" ]] || fail "Failed to derive public key from --private-key. Raw output: $out"
    if [[ -n "$PUBLIC_KEY" ]]; then
      is_x25519_key "$PUBLIC_KEY" || fail "Invalid --public-key format."
      [[ "$PUBLIC_KEY" == "$derived_pub" ]] || fail "Provided --public-key does not match --private-key."
    fi
    PUBLIC_KEY="${PUBLIC_KEY:-$derived_pub}"
    return
  fi

  [[ -z "$PUBLIC_KEY" ]] || fail "--public-key requires --private-key; the server config needs the private key."
  out="$(/usr/local/bin/xray x25519 2>/dev/null || xray x25519 2>/dev/null || true)"
  priv="$(printf '%s\n' "$out" | awk -F': *' '/Private/{print $2; exit}')"
  pub="$(printf '%s\n' "$out" | awk -F': *' '/Password|Public/{print $2; exit}')"
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

get_country_code() {
  local code=""
  code="$(curl -fsS4 --max-time 5 https://ipapi.co/country/ 2>/dev/null || true)"
  [[ "$code" =~ ^[A-Za-z]{2}$ ]] || code="$(curl -fsS4 --max-time 5 https://ipinfo.io/country 2>/dev/null || true)"
  code="$(printf '%s' "$code" | tr -dc 'A-Za-z' | head -c2 | tr 'a-z' 'A-Z')"
  [[ "$code" =~ ^[A-Z]{2}$ ]] || code="XX"
  printf '%s' "$code"
}

default_name() {
  local protocol="$1"
  printf '%s-%s' "$(get_country_code)" "$protocol"
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

ensure_state() {
  mkdir -p "$CONFIG_DIR"
  chmod 755 "$CONFIG_DIR"
  if [[ ! -f "$STATE_FILE" ]]; then
    python3 - "$STATE_FILE" <<'PY'
import json, os, sys, time
path = sys.argv[1]
state = {"version": 2, "nodes": [], "meta": {"created": int(time.time()), "updated": int(time.time())}}
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
PY
  fi
  chmod 600 "$STATE_FILE"
}

state_port_in_use() {
  local port="${1:-}"
  [[ -n "$port" && -f "$STATE_FILE" ]] || return 1
  PORT_CHECK="$port" STATE_FILE_ENV="$STATE_FILE" python3 - <<'PY'
import json, os, sys
port = int(os.environ["PORT_CHECK"])
path = os.environ["STATE_FILE_ENV"]
try:
    state = json.load(open(path, encoding="utf-8"))
except Exception:
    sys.exit(1)
for node in state.get("nodes", []):
    for key in ("port", "public_port", "inner_port"):
        value = node.get(key)
        if isinstance(value, int) and value == port:
            sys.exit(0)
sys.exit(1)
PY
}

state_tag_exists() {
  local tag="${1:-}"
  [[ -n "$tag" && -f "$STATE_FILE" ]] || return 1
  TAG_CHECK="$tag" STATE_FILE_ENV="$STATE_FILE" python3 - <<'PY'
import json, os, sys
tag = os.environ["TAG_CHECK"]
path = os.environ["STATE_FILE_ENV"]
try:
    state = json.load(open(path, encoding="utf-8"))
except Exception:
    sys.exit(1)
for node in state.get("nodes", []):
    if node.get("tag") == tag:
        sys.exit(0)
sys.exit(1)
PY
}

state_node_count() {
  if [[ ! -f "$STATE_FILE" ]]; then
    printf '0'
    return
  fi
  STATE_FILE_ENV="$STATE_FILE" python3 - <<'PY'
import json, os
try:
    state = json.load(open(os.environ["STATE_FILE_ENV"], encoding="utf-8"))
    print(len(state.get("nodes", [])))
except Exception:
    print(0)
PY
}

add_node_to_state() {
  local node_json="$1"
  ensure_state
  STATE_FILE_ENV="$STATE_FILE" NODE_JSON="$node_json" python3 - <<'PY'
import json, os, sys, time
path = os.environ["STATE_FILE_ENV"]
node = json.loads(os.environ["NODE_JSON"])
with open(path, encoding="utf-8") as f:
    state = json.load(f)
state.setdefault("version", 2)
nodes = state.setdefault("nodes", [])
tag = node["tag"]
for existing in nodes:
    if existing.get("tag") == tag:
        raise SystemExit(f"node tag already exists: {tag}")
used_ports = {}
for existing in nodes:
    for key in ("port", "public_port", "inner_port"):
        value = existing.get(key)
        if isinstance(value, int):
            used_ports.setdefault(value, existing.get("tag", "unknown"))
for key in ("port", "public_port", "inner_port"):
    value = node.get(key)
    if isinstance(value, int) and value in used_ports:
        raise SystemExit(f"port {value} already used by {used_ports[value]}")
nodes.append(node)
state.setdefault("meta", {})["updated"] = int(time.time())
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
PY
  chmod 600 "$STATE_FILE"
}

remove_node_from_state() {
  local tag="$1"
  [[ -n "$tag" ]] || fail "node tag is empty"
  [[ -f "$STATE_FILE" ]] || fail "state file not found"
  STATE_FILE_ENV="$STATE_FILE" TAG_REMOVE="$tag" python3 - <<'PY'
import json, os, sys, time
path = os.environ["STATE_FILE_ENV"]
tag = os.environ["TAG_REMOVE"]
with open(path, encoding="utf-8") as f:
    state = json.load(f)
nodes = state.get("nodes", [])
new_nodes = [n for n in nodes if n.get("tag") != tag]
if len(new_nodes) == len(nodes):
    raise SystemExit(f"node not found: {tag}")
state["nodes"] = new_nodes
state.setdefault("meta", {})["updated"] = int(time.time())
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
PY
  chmod 600 "$STATE_FILE"
}

node_json_reality() {
  NODE_TYPE="reality" NODE_TAG="reality-${PUBLIC_PORT}" NODE_NAME="$NAME" NODE_PORT="$PUBLIC_PORT" NODE_INNER="$INNER_PORT" \
  NODE_UUID="$UUID_VALUE" NODE_SNI="$SNI_VALUE" NODE_SHORT_ID="$SHORT_ID" NODE_PRIVATE_KEY="$PRIVATE_KEY" NODE_PUBLIC_KEY="$PUBLIC_KEY" \
  python3 - <<'PY'
import json, os
print(json.dumps({
    "type": os.environ["NODE_TYPE"],
    "tag": os.environ["NODE_TAG"],
    "name": os.environ["NODE_NAME"],
    "public_port": int(os.environ["NODE_PORT"]),
    "inner_port": int(os.environ["NODE_INNER"]),
    "uuid": os.environ["NODE_UUID"],
    "sni": os.environ["NODE_SNI"],
    "short_id": os.environ["NODE_SHORT_ID"],
    "private_key": os.environ["NODE_PRIVATE_KEY"],
    "public_key": os.environ["NODE_PUBLIC_KEY"],
    "fingerprint": "chrome",
    "spider_x": "/"
}, ensure_ascii=False))
PY
}

node_json_socks() {
  NODE_TYPE="socks5" NODE_TAG="socks5-${PUBLIC_PORT}" NODE_NAME="$NAME" NODE_PORT="$PUBLIC_PORT" \
  NODE_USER="$SOCKS_USER" NODE_PASS="$SOCKS_PASS" NODE_UDP="$SOCKS_UDP" python3 - <<'PY'
import json, os
print(json.dumps({
    "type": os.environ["NODE_TYPE"],
    "tag": os.environ["NODE_TAG"],
    "name": os.environ["NODE_NAME"],
    "port": int(os.environ["NODE_PORT"]),
    "user": os.environ["NODE_USER"],
    "password": os.environ["NODE_PASS"],
    "udp": os.environ["NODE_UDP"].lower() == "true"
}, ensure_ascii=False))
PY
}

node_json_cf_ws() {
  NODE_TYPE="cf-ws" NODE_TAG="cf-ws-${PUBLIC_PORT}" NODE_NAME="$NAME" NODE_PORT="$PUBLIC_PORT" \
  NODE_UUID="$UUID_VALUE" NODE_CF_DOMAIN="$CF_DOMAIN" NODE_CF_ENTRY="$CF_ENTRY" NODE_WS_PATH="$WS_PATH" python3 - <<'PY'
import json, os
print(json.dumps({
    "type": os.environ["NODE_TYPE"],
    "tag": os.environ["NODE_TAG"],
    "name": os.environ["NODE_NAME"],
    "port": int(os.environ["NODE_PORT"]),
    "uuid": os.environ["NODE_UUID"],
    "cf_domain": os.environ["NODE_CF_DOMAIN"],
    "cf_entry": os.environ["NODE_CF_ENTRY"],
    "path": os.environ["NODE_WS_PATH"]
}, ensure_ascii=False))
PY
}

generate_config_from_state() {
  ensure_state
  STATE_FILE_ENV="$STATE_FILE" CONFIG_FILE_ENV="$CONFIG_FILE" python3 - <<'PY'
import json, os, sys

state_path = os.environ["STATE_FILE_ENV"]
config_path = os.environ["CONFIG_FILE_ENV"]
with open(state_path, encoding="utf-8") as f:
    state = json.load(f)
nodes = state.get("nodes", [])
if not nodes:
    raise SystemExit("no nodes in state")

inbounds = []
routing_rules = []
used_ports = {}

def add_port(port, tag):
    if port in used_ports:
        raise SystemExit(f"duplicate port {port}: {used_ports[port]} and {tag}")
    used_ports[port] = tag

for node in nodes:
    typ = node.get("type")
    tag = node.get("tag")
    if typ == "reality":
        public_port = int(node["public_port"])
        inner_port = int(node["inner_port"])
        sni = node["sni"]
        add_port(public_port, tag)
        add_port(inner_port, f"{tag}-inner")
        public_tag = f"{tag}-tunnel"
        inner_tag = f"{tag}-inner"
        routing_rules.append({"type": "field", "domain": [sni], "inboundTag": [public_tag], "outboundTag": "direct"})
        routing_rules.append({"type": "field", "inboundTag": [public_tag], "outboundTag": "blocked"})
        inbounds.append({
            "listen": "0.0.0.0",
            "port": public_port,
            "protocol": "tunnel",
            "settings": {"address": "127.0.0.1", "port": inner_port, "portMap": {}, "network": "tcp,udp", "followRedirect": False},
            "tag": public_tag,
            "sniffing": {"enabled": True, "destOverride": ["tls"], "metadataOnly": False, "routeOnly": True}
        })
        inbounds.append({
            "listen": "127.0.0.1",
            "port": inner_port,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": node["uuid"], "flow": "xtls-rprx-vision", "email": f"default@{tag}"}],
                "decryption": "none",
                "encryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "externalProxy": [],
                "tcpSettings": {"acceptProxyProtocol": False, "header": {"type": "none"}},
                "realitySettings": {
                    "show": False,
                    "target": f"{sni}:443",
                    "xver": 0,
                    "serverNames": [sni],
                    "privateKey": node["private_key"],
                    "minClientVer": "",
                    "maxClientVer": "",
                    "maxTimediff": 0,
                    "shortIds": [node["short_id"]],
                    "mldsa65Seed": "",
                    "settings": {
                        "publicKey": node["public_key"],
                        "fingerprint": node.get("fingerprint", "chrome"),
                        "serverName": "",
                        "spiderX": node.get("spider_x", "/"),
                        "mldsa65Verify": ""
                    }
                }
            },
            "tag": inner_tag,
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "metadataOnly": False, "routeOnly": True}
        })
    elif typ == "socks5":
        port = int(node["port"])
        add_port(port, tag)
        inbounds.append({
            "listen": "0.0.0.0",
            "port": port,
            "protocol": "socks",
            "settings": {
                "auth": "password",
                "accounts": [{"user": node["user"], "pass": node["password"]}],
                "udp": bool(node.get("udp", False)),
                "ip": "127.0.0.1"
            },
            "tag": tag,
            "sniffing": {"enabled": False, "destOverride": ["http", "tls", "quic", "fakedns"], "metadataOnly": False, "routeOnly": False}
        })
    elif typ == "cf-ws":
        port = int(node["port"])
        add_port(port, tag)
        inbounds.append({
            "listen": "0.0.0.0",
            "port": port,
            "protocol": "vless",
            "settings": {"clients": [{"id": node["uuid"], "email": f"default@{tag}"}], "decryption": "none"},
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {"acceptProxyProtocol": False, "path": node["path"], "host": "", "headers": {}, "heartbeatPeriod": 0}
            },
            "tag": tag,
            "sniffing": {"enabled": True, "destOverride": ["http", "tls"], "metadataOnly": False, "routeOnly": False}
        })
    else:
        raise SystemExit(f"unknown node type: {typ}")

routing_rules.extend([
    {"type": "field", "outboundTag": "blocked", "ip": ["geoip:private"]},
    {"type": "field", "outboundTag": "blocked", "protocol": ["bittorrent"]}
])

config = {
    "log": {"access": "none", "error": "", "loglevel": "warning"},
    "routing": {"domainStrategy": "AsIs", "rules": routing_rules},
    "inbounds": inbounds,
    "outbounds": [
        {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}},
        {"tag": "blocked", "protocol": "blackhole", "settings": {}}
    ],
    "policy": {"levels": {"0": {"statsUserDownlink": True, "statsUserUplink": True}}, "system": {"statsInboundDownlink": True, "statsInboundUplink": True}},
    "stats": {}
}

tmp = config_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, config_path)
PY
  chmod 600 "$CONFIG_FILE"
}

write_service() {
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICE
[Unit]
Description=Xray Tunnel Reality Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -c ${CONFIG_FILE}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null
}

open_firewall_port() {
  local port="$1"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi active; then
    ufw allow "$port"/tcp >/dev/null 2>&1 || true
    ufw allow "$port"/udp >/dev/null 2>&1 || true
  fi
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$port"/tcp >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-port="$port"/udp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
  fi
}

start_or_restart_service() {
  info "Testing Xray config..."
  /usr/local/bin/xray run -test -c "$CONFIG_FILE" >/tmp/xray-tunnel-reality-test.log 2>&1 || {
    cat /tmp/xray-tunnel-reality-test.log
    fail "Xray config test failed."
  }
  write_service
  systemctl restart "$SERVICE_NAME"
  sleep 1
  systemctl is-active --quiet "$SERVICE_NAME" || {
    systemctl status "$SERVICE_NAME" --no-pager || true
    fail "Service failed to start."
  }
}

service_start() {
  [[ -f "$CONFIG_FILE" ]] || generate_config_from_state
  write_service
  systemctl start "$SERVICE_NAME"
}

service_stop() {
  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
}

service_restart() {
  generate_config_from_state
  start_or_restart_service
}

show_status() {
  echo
  echo "================ 状态 ================"
  if systemctl list-unit-files 2>/dev/null | grep -q "^${SERVICE_NAME}.service"; then
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      green "服务: 运行中"
    else
      yellow "服务: 已停止"
    fi
  else
    yellow "服务: 未安装"
  fi
  echo "配置: ${CONFIG_FILE}"
  echo "状态: ${STATE_FILE}"
  echo "Xray: $(current_xray_version || echo unknown)"
  echo
  show_nodes
}

show_logs() {
  journalctl -u "$SERVICE_NAME" --no-pager -n 120 || true
}

show_nodes() {
  local ip
  ip="$(get_public_ip)"
  if [[ ! -f "$STATE_FILE" ]]; then
    yellow "没有找到已保存的协议。"
    return
  fi
  PUBLIC_IP="$ip" STATE_FILE_ENV="$STATE_FILE" python3 - <<'PY'
import json, os, urllib.parse
path = os.environ["STATE_FILE_ENV"]
public_ip = os.environ.get("PUBLIC_IP", "")
try:
    state = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    print(f"状态文件读取失败: {exc}")
    raise SystemExit(0)
nodes = state.get("nodes", [])
if not nodes:
    print("没有已安装协议。")
    raise SystemExit(0)
print("================ 已安装协议 ================")
for index, node in enumerate(nodes, 1):
    typ = node.get("type")
    name = node.get("name") or node.get("tag")
    remark = urllib.parse.quote(name, safe="")
    print(f"{index}) {name}")
    print(f"   tag: {node.get('tag')}")
    if typ == "reality":
        port = node["public_port"]
        link = (
            f"vless://{node['uuid']}@{public_ip}:{port}"
            f"?encryption=none&flow=xtls-rprx-vision&security=reality"
            f"&sni={node['sni']}&fp={node.get('fingerprint', 'chrome')}"
            f"&pbk={node['public_key']}&sid={node['short_id']}&spx=%2F&type=tcp&headerType=none#{remark}"
        )
        print(f"   类型: VLESS Reality")
        print(f"   中转填写: {public_ip}:{port}")
        print(f"   外层端口: {port}")
        print(f"   内层端口: 127.0.0.1:{node['inner_port']}")
        print(f"   SNI: {node['sni']}")
        print(f"   客户端链接: {link}")
    elif typ == "socks5":
        port = node["port"]
        link = f"socks://{node['user']}:{node['password']}@{public_ip}:{port}#{remark}"
        print("   类型: SOCKS5")
        print(f"   中转填写: {public_ip}:{port}")
        print(f"   用户名: {node['user']}")
        print(f"   密码: {node['password']}")
        print(f"   UDP: {str(bool(node.get('udp', False))).lower()}")
        print(f"   SOCKS 链接: {link}")
    elif typ == "cf-ws":
        enc_path = urllib.parse.quote(node["path"], safe="")
        link = (
            f"vless://{node['uuid']}@{node['cf_entry']}:443"
            f"?encryption=none&security=tls&type=ws&host={node['cf_domain']}"
            f"&sni={node['cf_domain']}&path={enc_path}#{remark}"
        )
        print("   类型: Cloudflare VLESS-WS")
        print(f"   源站监听: {public_ip}:{node['port']}")
        print(f"   CF Host/SNI: {node['cf_domain']}")
        print(f"   CF 优选入口: {node['cf_entry']}:443")
        print(f"   WS 路径: {node['path']}")
        print(f"   客户端链接: {link}")
    print()
PY
}

list_node_tags() {
  [[ -f "$STATE_FILE" ]] || return 0
  STATE_FILE_ENV="$STATE_FILE" python3 - <<'PY'
import json, os
try:
    state = json.load(open(os.environ["STATE_FILE_ENV"], encoding="utf-8"))
except Exception:
    raise SystemExit(0)
for index, node in enumerate(state.get("nodes", []), 1):
    name = node.get("name") or node.get("tag")
    print(f"{index}|{node.get('tag')}|{name}|{node.get('type')}")
PY
}

install_shortcut() {
  mkdir -p /usr/local/bin
  local source_path=""
  if [[ "${BASH_SOURCE[0]}" == /* && -r "${BASH_SOURCE[0]}" ]]; then
    source_path="${BASH_SOURCE[0]}"
  fi
  if [[ -n "$source_path" ]]; then
    cp -f "$source_path" "$LOCAL_SCRIPT" 2>/dev/null || true
  fi
  if [[ ! -s "$LOCAL_SCRIPT" ]]; then
    curl -fsSL "$RAW_SCRIPT_URL" -o "$LOCAL_SCRIPT" 2>/dev/null || {
      yellow "快捷命令脚本下载失败，不影响当前服务。"
      return 0
    }
  fi
  chmod +x "$LOCAL_SCRIPT" 2>/dev/null || true
  ln -sf "$LOCAL_SCRIPT" "$SHORTCUT" 2>/dev/null || true
}

enable_bbr() {
  if [[ ! -d /proc/sys/net/ipv4 ]]; then
    yellow "当前系统不支持 sysctl BBR 配置，已跳过。"
    return 0
  fi
  modprobe tcp_bbr >/dev/null 2>&1 || true
  cat > "$BBR_CONF" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
  sysctl -p "$BBR_CONF" >/dev/null 2>&1 || true
  local cc qdisc available
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  echo
  echo "================ BBR ================"
  echo "当前拥塞控制: ${cc:-unknown}"
  echo "当前队列算法: ${qdisc:-unknown}"
  echo "可用拥塞控制: ${available:-unknown}"
  if [[ "$cc" == "bbr" ]]; then
    green "BBR 已启用。"
  else
    yellow "BBR 未生效。可能是内核不支持，或宿主机限制。"
  fi
}

prepare_reality_values() {
  PUBLIC_PORT="${PUBLIC_PORT:-$(ask '外层公网端口，回车随机高位端口' "$(random_high_port)")}"
  INNER_PORT="${INNER_PORT:-$(ask '内层 Reality 端口' '4431')}"
  SNI_VALUE="${SNI_VALUE:-www.icloud.com}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then SNI_VALUE="$(ask 'SNI/Reality target' "$SNI_VALUE")"; fi
  NAME="${NAME:-$(default_name 'VLESS+Reality')}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then NAME="$(ask '节点名称' "$NAME")"; fi
  [[ -n "$UUID_VALUE" ]] || UUID_VALUE="$(gen_uuid)"
  [[ -n "$SHORT_ID" ]] || SHORT_ID="$(random_hex 4)"
  is_port "$PUBLIC_PORT" || fail "Invalid --port: $PUBLIC_PORT"
  is_port "$INNER_PORT" || fail "Invalid --inner-port: $INNER_PORT"
  [[ "$PUBLIC_PORT" != "$INNER_PORT" ]] || fail "Public port and inner port must be different."
  is_domain "$SNI_VALUE" || fail "Invalid SNI: $SNI_VALUE"
  is_uuid "$UUID_VALUE" || fail "Invalid UUID: $UUID_VALUE"
  is_short_id "$SHORT_ID" || fail "Invalid shortId: $SHORT_ID"
  [[ -z "$PRIVATE_KEY" ]] || is_x25519_key "$PRIVATE_KEY" || fail "Invalid --private-key format."
  [[ -z "$PUBLIC_KEY" ]] || is_x25519_key "$PUBLIC_KEY" || fail "Invalid --public-key format."
}

prepare_socks_values() {
  PUBLIC_PORT="${PUBLIC_PORT:-$(ask 'SOCKS5 端口，回车随机高位端口' "$(random_high_port)")}"
  NAME="${NAME:-$(default_name 'SOCKS5')}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then NAME="$(ask '节点名称' "$NAME")"; fi
  SOCKS_USER="${SOCKS_USER:-$(ask 'SOCKS5 用户名' "$(random_user)")}"
  SOCKS_PASS="${SOCKS_PASS:-$(ask 'SOCKS5 密码' "$(random_pass)")}"
  SOCKS_UDP="${SOCKS_UDP:-false}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then SOCKS_UDP="$(ask '启用 UDP true/false' "$SOCKS_UDP")"; fi
  [[ "$SOCKS_UDP" == "true" || "$SOCKS_UDP" == "false" ]] || fail "--udp must be true or false"
  is_port "$PUBLIC_PORT" || fail "Invalid --port: $PUBLIC_PORT"
  [[ -n "$SOCKS_USER" && -n "$SOCKS_PASS" ]] || fail "SOCKS5 username/password cannot be empty."
}

prepare_cf_ws_values() {
  PUBLIC_PORT="${PUBLIC_PORT:-$(ask '源站 VLESS-WS 端口，回车随机高位端口' "$(random_high_port)")}"
  WS_PATH="${WS_PATH:-$(ask 'WebSocket path，回车随机路径' "$(random_ws_path)")}"
  if [[ -z "$CF_DOMAIN" ]]; then
    CF_DOMAIN="$(ask_required 'Cloudflare 橙云域名/Host，例如 hostdzire.212202.xyz')"
  elif [[ "$NON_INTERACTIVE" != "1" ]]; then
    CF_DOMAIN="$(ask 'Cloudflare 橙云域名/Host' "$CF_DOMAIN")"
  fi
  if [[ -z "$CF_ENTRY" ]]; then
    CF_ENTRY="$(ask '客户端连接入口，优选 IP/域名' "$CF_DOMAIN")"
  elif [[ "$NON_INTERACTIVE" != "1" ]]; then
    CF_ENTRY="$(ask '客户端连接入口，优选 IP/域名' "$CF_ENTRY")"
  fi
  NAME="${NAME:-$(default_name 'VLESS+WS')}"
  if [[ "$NON_INTERACTIVE" != "1" ]]; then NAME="$(ask '节点名称' "$NAME")"; fi
  [[ -n "$UUID_VALUE" ]] || UUID_VALUE="$(gen_uuid)"

  is_port "$PUBLIC_PORT" || fail "Invalid --port: $PUBLIC_PORT"
  is_path "$WS_PATH" || fail "Invalid WebSocket path: $WS_PATH. It must start with / and contain no spaces."
  is_domain "$CF_DOMAIN" || fail "Invalid --cf-domain: $CF_DOMAIN"
  is_host_or_ip "$CF_ENTRY" || fail "Invalid --cf-entry: $CF_ENTRY"
  is_uuid "$UUID_VALUE" || fail "Invalid UUID: $UUID_VALUE"
}

install_reality_node() {
  prepare_reality_values
  gen_x25519
  state_port_in_use "$PUBLIC_PORT" && fail "Port $PUBLIC_PORT is already saved in state."
  state_port_in_use "$INNER_PORT" && fail "Inner port $INNER_PORT is already saved in state. Use another --inner-port."
  check_port_free "$PUBLIC_PORT"
  check_port_free "$INNER_PORT"
  local node_json
  node_json="$(node_json_reality)"
  add_node_to_state "$node_json"
  generate_config_from_state
  open_firewall_port "$PUBLIC_PORT"
  start_or_restart_service
  green "VLESS Reality 已添加。"
  show_nodes
}

install_socks_node() {
  prepare_socks_values
  state_port_in_use "$PUBLIC_PORT" && fail "Port $PUBLIC_PORT is already saved in state."
  check_port_free "$PUBLIC_PORT"
  local node_json
  node_json="$(node_json_socks)"
  add_node_to_state "$node_json"
  generate_config_from_state
  open_firewall_port "$PUBLIC_PORT"
  start_or_restart_service
  green "SOCKS5 已添加。"
  show_nodes
}

install_cf_ws_node() {
  prepare_cf_ws_values
  state_port_in_use "$PUBLIC_PORT" && fail "Port $PUBLIC_PORT is already saved in state."
  check_port_free "$PUBLIC_PORT"
  local node_json
  node_json="$(node_json_cf_ws)"
  add_node_to_state "$node_json"
  generate_config_from_state
  open_firewall_port "$PUBLIC_PORT"
  start_or_restart_service
  green "Cloudflare VLESS-WS 已添加。"
  show_nodes
}

install_node() {
  install_deps
  install_xray
  [[ "$ENABLE_BBR" == "1" ]] && enable_bbr || true
  install_shortcut
  case "$MODE" in
    reality) install_reality_node ;;
    socks5) install_socks_node ;;
    cf-ws) install_cf_ws_node ;;
    *) fail "--mode must be reality, socks5, or cf-ws" ;;
  esac
}

remove_node() {
  ensure_state
  remove_node_from_state "$REMOVE_TAG"
  if [[ "$(state_node_count)" == "0" ]]; then
    service_stop
    rm -f "$CONFIG_FILE"
    green "节点已删除；没有剩余节点，服务已停止。"
  else
    generate_config_from_state
    start_or_restart_service
    green "节点已删除，服务已重启。"
  fi
  show_nodes
}

remove_node_menu() {
  ensure_state
  local count
  count="$(state_node_count)"
  if [[ "$count" == "0" ]]; then
    yellow "没有可卸载的协议。"
    return
  fi
  echo
  echo "已安装节点："
  list_node_tags | awk -F'|' '{printf "  %s) %s [%s] tag=%s\n", $1, $3, $4, $2}'
  local choice line
  read -r -p "选择要卸载的序号 [0返回]: " choice || true
  [[ -z "$choice" || "$choice" == "0" ]] && return
  line="$(list_node_tags | awk -F'|' -v c="$choice" '$1 == c {print}')"
  [[ -n "$line" ]] || { yellow "无效选择。"; return; }
  REMOVE_TAG="$(printf '%s' "$line" | awk -F'|' '{print $2}')"
  read -r -p "确认卸载 tag=${REMOVE_TAG}? [y/N]: " confirm || true
  [[ "$confirm" =~ ^[yY]$ ]] || return
  remove_node
}

uninstall_service_config() {
  local confirm="${1:-}"
  if [[ "$NON_INTERACTIVE" != "1" && "$confirm" != "yes" ]]; then
    read -r -p "确认卸载 ${SERVICE_NAME} 服务和配置？不会删除 /usr/local/bin/xray [y/N]: " confirm || true
    [[ "$confirm" =~ ^[yY]$ ]] || return
  fi
  info "Stopping ${SERVICE_NAME}..."
  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload >/dev/null 2>&1 || true
  rm -rf "$CONFIG_DIR"
  green "${SERVICE_NAME} 已卸载。保留：/usr/local/bin/xray 和 xrt 快捷命令。"
}

full_uninstall() {
  uninstall_service_config yes
  rm -f "$SHORTCUT" "$LOCAL_SCRIPT"
  green "xrt 快捷命令和本地脚本已删除。"
  yellow "未删除 /usr/local/bin/xray，避免影响其它面板或节点。"
}

reset_node_vars() {
  PUBLIC_PORT=""
  INNER_PORT=""
  UUID_VALUE=""
  SHORT_ID=""
  NAME=""
  PRIVATE_KEY=""
  PUBLIC_KEY=""
  SOCKS_USER=""
  SOCKS_PASS=""
  SOCKS_UDP="false"
  CF_DOMAIN=""
  CF_ENTRY=""
  WS_PATH=""
}

manager_menu() {
  install_deps
  install_shortcut
  while true; do
    echo
    echo "========== xray-tunnel-reality 无面板管理 =========="
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      echo "状态: 运行中"
    elif [[ -f "$STATE_FILE" ]]; then
      echo "状态: 已安装但服务未运行"
    else
      echo "状态: 未安装"
    fi
    echo "快捷命令: xrt"
    echo
    echo "1) 添加 VLESS Reality"
    echo "2) 添加 SOCKS5"
    echo "3) 添加 Cloudflare VLESS-WS"
    echo "4) 查看所有协议链接"
    echo "5) 卸载指定协议"
    echo "6) 重启服务"
    echo "7) 查看状态"
    echo "8) 查看日志"
    echo "9) BBR 状态/开启"
    echo "10) 完整卸载"
    echo "0) 退出"
    echo "=================================================="
    local choice
    read -r -p "请选择: " choice || exit 0
    case "$choice" in
      1) reset_node_vars; MODE="reality"; install_node; pause ;;
      2) reset_node_vars; MODE="socks5"; install_node; pause ;;
      3) reset_node_vars; MODE="cf-ws"; install_node; pause ;;
      4) show_nodes; pause ;;
      5) remove_node_menu; pause ;;
      6) service_restart; green "服务已重启。"; pause ;;
      7) show_status; pause ;;
      8) show_logs; pause ;;
      9) enable_bbr; pause ;;
      10) full_uninstall; pause ;;
      0) exit 0 ;;
      *) yellow "无效选择。"; pause ;;
    esac
  done
}

main() {
  need_root
  if [[ -n "$MODE" ]]; then
    install_node
    return
  fi

  case "$ACTION" in
    show) show_nodes ;;
    status) show_status ;;
    logs) show_logs ;;
    start) service_start; green "服务已启动。" ;;
    stop) service_stop; green "服务已停止。" ;;
    restart) service_restart; green "服务已重启。" ;;
    remove-node) remove_node ;;
    uninstall) uninstall_service_config ;;
    full-uninstall) full_uninstall ;;
    enable-bbr) enable_bbr ;;
    "")
      if [[ "$NON_INTERACTIVE" == "1" ]]; then
        MODE="reality"
        install_node
      else
        manager_menu
      fi
      ;;
    *) fail "Unknown action: $ACTION" ;;
  esac
}

main "$@"
