#!/bin/bash

set -e

echo "[+] Installing WireGuard..."
sudo apt update
sudo apt install -y wireguard

echo "[+] Input client WireGuard IP (e.g., 10.0.0.2):"
read -p "Client WG IP: " CLIENT_WG_IP

echo "[+] Input server public IP or domain:"
read -p "Server Public IP: " SERVER_PUBLIC_IP

echo "[+] Input server WireGuard public key:"
read -p "Server Public Key: " SERVER_PUBLIC_KEY

echo "[+] Generating client keys..."
umask 077
wg genkey | tee client_private.key | wg pubkey > client_public.key

CLIENT_PRIVATE_KEY=$(cat client_private.key)
CLIENT_PUBLIC_KEY=$(cat client_public.key)

CLIENT_CONF="/etc/wireguard/wg0.conf"

if [ -f "$SERVER_CONF" ]; then
    echo "[+] Existing config found. Deleting $SERVER_CONF..."
    sudo rm -f "$SERVER_CONF"
fi

echo "[+] Writing client config to $CLIENT_CONF..."

cat <<EOF | sudo tee $CLIENT_CONF > /dev/null
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_WG_IP/24

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo "[+] Reloading WireGuard config..."
if systemctl is-active --quiet wg-quick@wg0; then
    echo "[+] Stopping existing WireGuard interface..."
    sudo systemctl stop wg-quick@wg0
fi

echo "[+] Starting and enabling WireGuard..."
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0 --no-pager

echo "[+] WireGuard status:"
sudo wg

echo ""
echo "==========="
echo "Client public key (gunakan ini di server pada step3.sh):"
echo "$CLIENT_PUBLIC_KEY"
echo "==========="

