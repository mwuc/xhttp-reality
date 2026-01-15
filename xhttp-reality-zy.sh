#!/usr/bin/env bash
set -e

SCRIPT_VERSION="0.1.0"
SCRIPT_NAME="xhttp-reality"


if [[ "$1" == "version" ]]; then
  echo "$SCRIPT_NAME version $SCRIPT_VERSION"
  exit 0
fi


# ================= 基本配置 =================
XRAY_DIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
CONFIG_FILE="$XRAY_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"

ACTION="$1"
CF_DOMAIN="$2"

DOMAIN_SNI="www.icloud.com"

PORT_XHTTP=80
PORT_REALITY=443

# UUID=$(cat /proc/sys/kernel/random/uuid)
# XHTTP_PATH="/$(echo "$UUID" | cut -d- -f1)"

UUID_XHTTP="64c4dd3f-5c99-46dc-b6b8-1bde9cb98edd"
UUID_REALITY="bff34330-9f5f-4efc-90f1-1fc73d9fb12b"
XHTTP_PATH="/fc73d9fb12b"
VPS_IP=$(curl -fsSL https://api.ipify.org)

# ================= 系统检查 =================
if ! command -v apt >/dev/null 2>&1; then
  echo "仅支持 Debian / Ubuntu 系统"
  exit 1
fi

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 运行"
    exit 1
  fi
}

update_script() {
  require_root

  REPO_RAW="https://raw.githubusercontent.com/ooplastone22/xhttp-reality/refs/heads/main/xhttp-reality.sh"
  TMP_FILE="/tmp/xhttp-reality.sh"

  echo ">>> 检查并更新脚本..."

  curl -fsSL "$REPO_RAW" -o "$TMP_FILE"

  if ! grep -q "SCRIPT_VERSION" "$TMP_FILE"; then
    echo "下载的脚本无效，取消更新"
    exit 1
  fi

  install -m 755 "$TMP_FILE" "$0"
  echo ">>> 更新完成"
  exit 0
}

uninstall_xray() {
  require_root
  echo ">>> 卸载 Xray"

  systemctl stop xray 2>/dev/null || true
  systemctl disable xray 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload

  rm -f "$XRAY_BIN"
  rm -rf "$XRAY_DIR"

  echo ">>> 卸载完成"
  exit 0
}

install_xray() {
  require_root

  if [ -z "$CF_DOMAIN" ]; then
    echo "用法: install <CF_DOMAIN>"
    exit 1
  fi
# ================= 安装依赖 =================
apt update
apt install -y curl unzip jq uuid-runtime openssl

# ================= 安装 Xray =================
mkdir -p "$XRAY_DIR"
ARCH=$(uname -m)

case "$ARCH" in
  x86_64|amd64)
    XRAY_ARCH="64"
    ;;
  aarch64|arm64)
    XRAY_ARCH="arm64-v8a"
    ;;
  *)
    echo "不支持的架构: $ARCH"
    exit 1
    ;;
esac

curl -fsSL \
  https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip \
  -o /tmp/xray.zip

# curl -fsSL https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o /tmp/xray.zip
unzip -qo /tmp/xray.zip -d /tmp/xray
install -m 755 /tmp/xray/xray "$XRAY_BIN"

# ================= Reality 密钥 =================
# REALITY_KEYS=$("$XRAY_BIN" x25519)
# PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/PrivateKey|Private key/{print $NF}')
# PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/Password|Public key/{print $NF}')

PRIVATE_KEY="8O9iwbAbCAFg4fMWgTTaTpyFsboKSFD__VGFEb8RiHU"
PUBLIC_KEY="bKtUFakQNVC3onraxo0Z3_nu6DRuCB70_9djSpRJkyM"
# SHORT_ID=$(openssl rand -hex 4)
SHORT_ID="adba013e"
# ================= 写配置 =================
cat > "$CONFIG_FILE" <<EOF
{
  "inbounds": [
    {
      "port": $PORT_XHTTP,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID_XHTTP" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": {
          "path": "$XHTTP_PATH",
          "mode": "auto"
        }
      },
      "tag": "xhttp-in"
    },
    {
      "port": $PORT_REALITY,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID_REALITY", "flow": "xtls-rprx-vision" }
        ],
        "decryption": "none",
        "fallbacks": [
          { 
            "dest": $PORT_XHTTP
            # "xver": 1
            }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverNames": ["$DOMAIN_SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"],
          "target": "$DOMAIN_SNI:443"
        }
      },
      "tag": "reality-in"
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" }
  ]
}
EOF

# ================= systemd =================
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=$XRAY_BIN run -c $CONFIG_FILE
Restart=on-failure
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ================= 开启 BBR =================
modprobe tcp_bbr || true

cat > /etc/sysctl.d/99-xray-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl --system

  # ===== 生成分享链接 =====

  EXTRA_JSON=$(cat <<EOJ
{
  "downloadSettings": {
    "address": "$VPS_IP",
    "port": 443,
    "network": "xhttp",
    "xhttpSettings": {
      "path": "$XHTTP_PATH",
      "mode": "auto"
    },
    "security": "reality",
    "realitySettings": {
      "serverName": "$DOMAIN_SNI",
      "fingerprint": "chrome",
      "show": false,
      "publicKey": "$PUBLIC_KEY",
      "shortId": "$SHORT_ID",
      "spiderX": "/",
      "mldsa65Verify": ""
    }
  }
}
EOJ
)

  EXTRA_ENCODED=$(echo "$EXTRA_JSON" | jq -c . | jq -sRr @uri)
  PATH_ENCODED=$(printf '%s' "$XHTTP_PATH" | jq -sRr @uri)

  VLESS_LINK="vless://${UUID_XHTTP}@${CF_DOMAIN}:443?encryption=none&security=tls&sni=${CF_DOMAIN}&type=xhttp&host=${CF_DOMAIN}&path=${PATH_ENCODED}&mode=auto&extra=${EXTRA_ENCODED}#xhttp-reality"

  echo ""
  echo "========== 安装完成 =========="
  echo ""
  echo "📎 v2rayN / sing-box 分享链接："
  echo ""
  echo "$VLESS_LINK"
  echo ""
  echo "$VLESS_LINK" > "$XRAY_DIR/client-link.txt"
}

case "$ACTION" in
  update)
    update_script
    ;;
  install)
    install_xray
    ;;
  uninstall)
    uninstall_xray
    ;;
  *)
    echo "用法:"
    echo "  install <CF_DOMAIN>"
    echo "  uninstall"
    echo "  update"
    exit 1
    ;;
esac
