#!/bin/bash

WG_CONF="/etc/wireguard/wg0.conf"
WG_INTERFACE="wg0"
# Auto detect server public key, listen port, dan IP publik
detect_public_ip() {
  ip1=$(curl -4s https://api.ipify.org || true)
  [[ -z "$ip1" ]] && ip1=$(dig +short myip.opendns.com @resolver1.opendns.com || true)
  [[ -z "$ip1" ]] && ip1=$(curl -4s https://ifconfig.me || true)
  echo "$ip1"
}
SERVER_PUBKEY="$(wg show "$WG_INTERFACE" 2>/dev/null | awk '/public key/ {print $3; exit}')"
if [[ -z "$SERVER_PUBKEY" ]]; then
  SRV_PRIV="$(wg showconf "$WG_INTERFACE" 2>/dev/null | awk -F' = ' '/^PrivateKey/ {print $2}')"
  [[ -n "$SRV_PRIV" ]] && SERVER_PUBKEY="$(printf '%s' "$SRV_PRIV" | wg pubkey)"
fi
WG_PORT="$(wg show "$WG_INTERFACE" 2>/dev/null | awk '/listening port/ {print $3; exit}')"
if [[ -z "$WG_PORT" ]]; then
  WG_PORT="$(awk -F' = ' '/^ListenPort/ {print $2; exit}' "$WG_CONF" 2>/dev/null || true)"
fi
PUBLIC_IP="$(detect_public_ip)"
[[ -z "$PUBLIC_IP" ]] && PUBLIC_IP="<PUBLIC_IP_VPS>"
[[ -z "$WG_PORT" ]] && WG_PORT="51820"
ENDPOINT="${PUBLIC_IP}:${WG_PORT}"

read -p "Input nama peer: " PEER_NAME

read -p "Gunakan preshared key? (y/n): " USE_PSK

# Generate keypair
PRIVKEY=$(wg genkey)
PUBKEY=$(echo "$PRIVKEY" | wg pubkey)

if [[ "$USE_PSK" =~ ^[Yy]$ ]]; then
    PRESHARED=$(wg genpsk)
    USE_PSK_FLAG=true
else
    USE_PSK_FLAG=false
fi

# Cari IP terakhir yang digunakan dengan benar
LAST_IP=$(grep "AllowedIPs" "$WG_CONF" | grep -o "10\.8\.0\.[0-9]*" | cut -d'.' -f4 | sort -n | tail -1)
echo "Last used IP: $LAST_IP"
if [[ -z "$LAST_IP" ]]; then
    PEER_IP=2
else
    PEER_IP=$((LAST_IP+1))
fi

if [[ "$USE_PSK_FLAG" == true ]]; then
    wg set "$WG_INTERFACE" peer "$PUBKEY" preshared-key <(echo "$PRESHARED") allowed-ips 10.8.0.$PEER_IP/32
else
    wg set "$WG_INTERFACE" peer "$PUBKEY" allowed-ips 10.8.0.$PEER_IP/32
fi

# Simpan konfigurasi aktif ke file
wg-quick save "$WG_INTERFACE"

# Siapkan baris PSK opsional
PSK_LINE=""
if [[ "$USE_PSK_FLAG" == true ]]; then
  PSK_LINE="PresharedKey = $PRESHARED"
fi

# Cetak konfigurasi untuk peer
cat <<EOC

# Config untuk $PEER_NAME
[Interface]
PrivateKey = $PRIVKEY
Address = 10.8.0.$PEER_IP/24

[Peer]
PublicKey = $SERVER_PUBKEY
${PSK_LINE}
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 0
Endpoint = $ENDPOINT

EOC