#!/usr/bin/env bash
# ============================================
#  WireGuard Server + 1 Peer Setup / Refresh
#  - Stop wg0 jika sudah jalan
#  - Install WireGuard bila belum ada
#  - Generate server + peer key
#  - Buat wg0.conf server (10.8.0.1/24, UDP 51820)
#  - Buat konfigurasi peer siap-copas
# ============================================
set -euo pipefail

WG_IF=wg0
WG_DIR=/etc/wireguard
KEY_DIR=$WG_DIR/keys
SRV_ADDR_CIDR="10.8.0.1/24"
SRV_PORT=51820

PEER_NAME="peer1"
PEER_ADDR_HOST="10.8.0.2"
PEER_ADDR_CIDR="${PEER_ADDR_HOST}/24"
PEER_ALLOWED="10.8.0.0/24"

# ------------------ Root check ------------------
if [[ $EUID -ne 0 ]]; then
  echo "Harus dijalankan sebagai root (sudo su -)" >&2
  exit 1
fi

# ------------------ Stop WireGuard jika aktif ------------------
if systemctl is-active --quiet wg-quick@${WG_IF}; then
  echo "Men-stop service wg-quick@${WG_IF}..."
  systemctl stop wg-quick@${WG_IF}
fi

# ------------------ Install paket ------------------
if ! command -v wg >/dev/null 2>&1; then
  apt-get update
  apt-get install -y wireguard wireguard-tools resolvconf || true
fi

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

# ------------------ Generate Server Keys ------------------
umask 077
wg genkey | tee "$KEY_DIR/server_private.key" | wg pubkey > "$KEY_DIR/server_public.key"
SRV_PRIV_KEY=$(cat "$KEY_DIR/server_private.key")
SRV_PUB_KEY=$(cat "$KEY_DIR/server_public.key")

# ------------------ Generate Peer Keys ------------------
wg genkey | tee "$KEY_DIR/${PEER_NAME}_private.key" | wg pubkey > "$KEY_DIR/${PEER_NAME}_public.key"
PEER_PRIV_KEY=$(cat "$KEY_DIR/${PEER_NAME}_private.key")
PEER_PUB_KEY=$(cat "$KEY_DIR/${PEER_NAME}_public.key")

# ------------------ Detect Public IP ------------------
detect_public_ip() {
  ip1=$(curl -4s https://api.ipify.org || true)
  [[ -z "$ip1" ]] && ip1=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
  [[ -z "$ip1" ]] && ip1=$(curl -4s https://ifconfig.me || true)
  [[ -z "$ip1" ]] && ip1="<PUBLIC_IP_VPS_ANDA>"
  echo "$ip1"
}
PUBLIC_IP=$(detect_public_ip)

# ------------------ Write wg0.conf (server) ------------------
SRV_CONF="$WG_DIR/$WG_IF.conf"
cat > "$SRV_CONF" <<EOF
[Interface]
Address = ${SRV_ADDR_CIDR}
ListenPort = ${SRV_PORT}
PrivateKey = ${SRV_PRIV_KEY}

[Peer]
PublicKey = ${PEER_PUB_KEY}
AllowedIPs = ${PEER_ADDR_HOST}/32
EOF
chmod 600 "$SRV_CONF"

# ------------------ Start WireGuard service ------------------
echo "Menyalakan service wg-quick@${WG_IF}..."
systemctl enable --now wg-quick@${WG_IF}

# ------------------ Output peer configuration ------------------
PEER_CONF="/root/${PEER_NAME}.conf"
cat > "$PEER_CONF" <<EOF
[Interface]
PrivateKey = ${PEER_PRIV_KEY}
Address = ${PEER_ADDR_CIDR}

[Peer]
PublicKey = ${SRV_PUB_KEY}
Endpoint = ${PUBLIC_IP}:${SRV_PORT}
AllowedIPs = ${PEER_ALLOWED}
PersistentKeepalive = 10
EOF
chmod 600 "$PEER_CONF"

echo
echo "========= Salin ke perangkat peer ========="
cat "$PEER_CONF"
echo "==========================================="
echo
echo "Server config : $SRV_CONF"
echo "Peer config   : $PEER_CONF"
echo "Server pubkey : $SRV_PUB_KEY"
echo
echo "Pastikan port UDP ${SRV_PORT} dibuka di Security List/NSG Oracle."
