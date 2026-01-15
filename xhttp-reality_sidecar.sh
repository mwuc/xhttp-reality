#!/usr/bin/env bash
set -e

# ================= 元信息 =================
SCRIPT_NAME="xhttp-reality-sidecar"
SCRIPT_VERSION="1.1.1"

# ================= 全局路径 =================
XRAY_BIN=""
XRAY_BASE="/usr/local/etc/xray"
XRAY_OWNERSHIP_MARKER="$XRAY_BASE/.xhttp-reality-owned"

CONFIG_FILE=""
IDENTITY_FILE=""
SERVICE_NAME=""
SERVICE_FILE=""

# ================= 默认参数 =================
ACTION=""
MODE="random"
CF_DOMAIN=""
UUID_XHTTP=""
UUID_REALITY=""
PORT_XHTTP=80
PORT_REALITY=443
DOMAIN_SNI=""
YOUXUAN_DOMAIN="www.visa.com.hk"
NODE_NAME="xhttp-reality"

# ================= Fixed Identity Defaults =================
DEFAULT_UUID_XHTTP="64c4dd3f-5c99-46dc-b6b8-1bde9cb98edd"
DEFAULT_UUID_REALITY="bff34330-9f5f-4efc-90f1-1fc73d9fb12b"
DEFAULT_XHTTP_PATH="/fc73d9fb12b"
DEFAULT_PRIVATE_KEY="8O9iwbAbCAFg4fMWgTTaTpyFsboKSFD__VGFEb8RiHU"
DEFAULT_PUBLIC_KEY="bKtUFakQNVC3onraxo0Z3_nu6DRuCB70_9djSpRJkyM"
DEFAULT_SHORT_ID="adba013e"
DEFAULT_DOMAIN_SNI="www.icloud.com"

# ================= 工具函数 =================
require_root() {
  [[ $(id -u) -eq 0 ]] || { echo "请使用 root 运行"; exit 1; }
}

log() {
  echo "[${SCRIPT_NAME}] $*"
}

# ================= 参数解析 =================
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--install) ACTION="install"; shift ;;
    -u|--uninstall) ACTION="uninstall"; shift ;;
    -s|--status) ACTION="status"; shift ;;
    -l|--link) ACTION="link"; shift ;;
    -d|--domain) CF_DOMAIN="$2"; shift 2 ;;
    -m|--mode) MODE="$2"; shift 2 ;;
    -n|--nodename) NODE_NAME="$2"; shift 2 ;;
    --uuid-xhttp) UUID_XHTTP="$2"; shift 2 ;;
    --uuid-reality) UUID_REALITY="$2"; shift 2 ;;
    --domain-sni) DOMAIN_SNI="$2"; shift 2 ;;
    version) echo "$SCRIPT_NAME $SCRIPT_VERSION"; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# ================= 部署模式检测 =================
DEPLOY_MODE=""

detect_deploy_mode() {
  if ! command -v xray >/dev/null 2>&1; then
    DEPLOY_MODE="primary"
    return
  fi

  if systemctl list-unit-files | grep -q '^xray.service'; then
    DEPLOY_MODE="sidecar"
  else
    DEPLOY_MODE="primary"
  fi
}

# ================= xray 二进制处理 =================
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "64" ;;
    aarch64|arm64) echo "arm64-v8a" ;;
    *) log "不支持的架构"; exit 1 ;;
  esac
}

ensure_xray_bin() {
  if command -v xray >/dev/null 2>&1; then
    XRAY_BIN="$(command -v xray)"
    log "✔ 使用系统已有 xray: $XRAY_BIN"
    return
  fi

  if [[ "$DEPLOY_MODE" == "sidecar" ]]; then
    log "✘ sidecar 模式下未检测到 xray，请先自行安装 xray core"
    exit 1
  fi

  log "未检测到 xray，开始安装（primary 模式）"
  ARCH=$(detect_arch)

  apt -o Acquire::http::Timeout=5 update
  apt install -y curl unzip

  curl -fsSL https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH}.zip -o /tmp/xray.zip
  unzip -qo /tmp/xray.zip -d /tmp/xray
  install -m 755 /tmp/xray/xray /usr/local/bin/xray
  XRAY_BIN="/usr/local/bin/xray"
}

# ================= Identity 管理 =================
read_identity() {
  UUID_XHTTP=$(jq -r .uuid_xhttp "$IDENTITY_FILE")
  UUID_REALITY=$(jq -r .uuid_reality "$IDENTITY_FILE")
  XHTTP_PATH=$(jq -r .xhttp_path "$IDENTITY_FILE")
  PRIVATE_KEY=$(jq -r .private_key "$IDENTITY_FILE")
  PUBLIC_KEY=$(jq -r .public_key "$IDENTITY_FILE")
  SHORT_ID=$(jq -r .short_id "$IDENTITY_FILE")
  DOMAIN_SNI=$(jq -r .domain_sni "$IDENTITY_FILE")
}

validate_identity() {
  [[ "$UUID_XHTTP" =~ ^[0-9a-fA-F-]{36}$ ]] || return 1
  [[ "$UUID_REALITY" =~ ^[0-9a-fA-F-]{36}$ ]] || return 1
  [[ "$XHTTP_PATH" =~ ^/[0-9a-zA-Z._-]+$ ]] || return 1
  [[ -n "$PRIVATE_KEY" && -n "$PUBLIC_KEY" ]] || return 1
  [[ "$SHORT_ID" =~ ^[0-9a-fA-F]{2,16}$ ]] || return 1
  return 0
}

load_fixed_identity() {
  mkdir -p "$(dirname "$IDENTITY_FILE")"

  if [[ -f "$IDENTITY_FILE" ]]; then
    read_identity
    validate_identity || { log "identity.json 无效"; exit 1; }
    return
  fi

  UUID_XHTTP=${UUID_XHTTP:-"$DEFAULT_UUID_XHTTP"}
  UUID_REALITY=${UUID_REALITY:-"$DEFAULT_UUID_REALITY"}
  XHTTP_PATH="$DEFAULT_XHTTP_PATH"
  PRIVATE_KEY="$DEFAULT_PRIVATE_KEY"
  PUBLIC_KEY="$DEFAULT_PUBLIC_KEY"
  SHORT_ID="$DEFAULT_SHORT_ID"
  DOMAIN_SNI=${DOMAIN_SNI:-"$DEFAULT_DOMAIN_SNI"}

  validate_identity || { log "fixed 参数非法"; exit 1; }

  cat > "$IDENTITY_FILE" <<EOF
{
  "uuid_xhttp": "$UUID_XHTTP",
  "uuid_reality": "$UUID_REALITY",
  "xhttp_path": "$XHTTP_PATH",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "short_id": "$SHORT_ID",
  "domain_sni": "$DOMAIN_SNI"
}
EOF
}

load_or_generate_random_identity() {
  mkdir -p "$(dirname "$IDENTITY_FILE")"

  if [[ -f "$IDENTITY_FILE" ]]; then
    read_identity
    validate_identity || { log "identity.json 损坏"; exit 1; }
    return
  fi

  UUID_XHTTP=$(cat /proc/sys/kernel/random/uuid)
  UUID_REALITY=$(cat /proc/sys/kernel/random/uuid)
  XHTTP_PATH="/$(echo "$UUID_XHTTP" | cut -d- -f1)"

  KEYS=$("$XRAY_BIN" x25519)
  PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey|Private key/{print $NF}')
  PUBLIC_KEY=$(echo "$KEYS" | awk '/Password|Public key/{print $NF}')
  SHORT_ID=$(openssl rand -hex 4)
  DOMAIN_SNI="www.icloud.com"

  cat > "$IDENTITY_FILE" <<EOF
{
  "uuid_xhttp": "$UUID_XHTTP",
  "uuid_reality": "$UUID_REALITY",
  "xhttp_path": "$XHTTP_PATH",
  "private_key": "$PRIVATE_KEY",
  "public_key": "$PUBLIC_KEY",
  "short_id": "$SHORT_ID",
  "domain_sni": "$DOMAIN_SNI"
}
EOF
}

# ================= 安装 =================
install_xray() {
  require_root
  [[ -n "$CF_DOMAIN" ]] || { log "缺少 -d <domain>"; exit 1; }

  detect_deploy_mode
  log "部署模式：$DEPLOY_MODE"

  ensure_xray_bin

  if [[ "$DEPLOY_MODE" == "primary" ]]; then
    CONFIG_FILE="$XRAY_BASE/config.json"
    IDENTITY_FILE="$XRAY_BASE/identity.json"
    SERVICE_NAME="xray"
  else
    CONFIG_FILE="$XRAY_BASE/config.d/xhttp-reality.json"
    IDENTITY_FILE="$XRAY_BASE/identity.d/xhttp-reality.json"
    SERVICE_NAME="xray-xhttp-reality"
  fi

  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

  [[ "$MODE" == "fixed" ]] && load_fixed_identity || load_or_generate_random_identity

  VPS_IP=$(curl -fsSL https://api.ipify.org)

  mkdir -p "$(dirname "$CONFIG_FILE")"

  cat > "$CONFIG_FILE" <<EOF
{
  "inbounds": [
    {
      "port": $PORT_XHTTP,
      "protocol": "vless",
      "settings": { "clients": [{ "id": "$UUID_XHTTP" }], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "$XHTTP_PATH", "mode": "auto" }
      }
    },
    {
      "port": $PORT_REALITY,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID_REALITY", "flow": "xtls-rprx-vision" }],
        "decryption": "none",
        "fallbacks": [{ "dest": $PORT_XHTTP }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "privateKey": "$PRIVATE_KEY",
          "serverNames": ["$DOMAIN_SNI"],
          "shortIds": ["$SHORT_ID"],
          "target": "$DOMAIN_SNI:443"
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray ($SERVICE_NAME)
After=network.target

[Service]
ExecStart=$XRAY_BIN run -c $CONFIG_FILE
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  # ownership marker（只在 primary）
  if [[ "$DEPLOY_MODE" == "primary" ]]; then
    echo "owned-by=$SCRIPT_NAME" > "$XRAY_OWNERSHIP_MARKER"
  fi

  # ===== 客户端输出 =====
  EXTRA_JSON=$(cat <<EOJ
{"downloadSettings":{"address":"$VPS_IP","port":443,"network":"xhttp","xhttpSettings":{"path":"$XHTTP_PATH","mode":"auto"},"security":"reality","realitySettings":{"serverName":"$DOMAIN_SNI","fingerprint":"chrome","show":false,"publicKey":"$PUBLIC_KEY","shortId":"$SHORT_ID","spiderX":"/","mldsa65Verify":""}}}
EOJ
)
  EXTRA_ENCODED=$(echo "$EXTRA_JSON" | jq -sRr @uri)
  PATH_ENCODED=$(printf '%s' "$XHTTP_PATH" | jq -sRr @uri)
  NAME_ENCODED=$(printf '%s' "$NODE_NAME" | jq -sRr @uri)

  VLESS_LINK="vless://${UUID_XHTTP}@${YOUXUAN_DOMAIN}:443?encryption=none&security=tls&sni=${CF_DOMAIN}&type=xhttp&host=${CF_DOMAIN}&path=${PATH_ENCODED}&mode=auto&extra=${EXTRA_ENCODED}#${NAME_ENCODED}"

  SUB_BASE64=$(printf '%s' "$VLESS_LINK" | base64 -w 0)

  echo ""
  echo "✔ 安装完成（$DEPLOY_MODE 模式）"
  echo "────────────────────────────────────"
  echo "$VLESS_LINK"
  echo "────────────────────────────────────"
  echo "$SUB_BASE64"
}

# ================= 卸载 =================
uninstall_xray() {
  require_root
  detect_deploy_mode

  if [[ "$DEPLOY_MODE" == "primary" ]]; then
    SERVICE_NAME="xray"
    CONFIG_FILE="$XRAY_BASE/config.json"
    IDENTITY_FILE="$XRAY_BASE/identity.json"
  else
    SERVICE_NAME="xray-xhttp-reality"
    CONFIG_FILE="$XRAY_BASE/config.d/xhttp-reality.json"
    IDENTITY_FILE="$XRAY_BASE/identity.d/xhttp-reality.json"
  fi

  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload

  rm -f "$CONFIG_FILE" "$IDENTITY_FILE"

  if [[ "$DEPLOY_MODE" == "primary" && -f "$XRAY_OWNERSHIP_MARKER" ]]; then
    log "✔ 确认 xray 由本脚本安装，执行完整卸载"
    rm -f /usr/local/bin/xray
    rm -rf "$XRAY_BASE"
  else
    log "⚠ 跳过 xray core 卸载（不属于本脚本）"
  fi

  log "✔ 卸载完成"
}

# ================= 主入口 =================
case "$ACTION" in
  install) install_xray ;;
  uninstall) uninstall_xray ;;
  *) echo "用法: -i -d <domain> | -u"; exit 1 ;;
esac
