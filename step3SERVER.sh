#!/bin/bash

set -e

echo "[+] Input WireGuard server IP (e.g., 10.0.0.1):"
read -p "Server WG IP: " SERVER_WG_IP

echo "[+] Input peer (client) WG IP (e.g., 10.0.0.2):"
read -p "Client WG IP: " CLIENT_WG_IP

echo "[+] Input client public key:"
read -p "Client Public Key: " CLIENT_PUBLIC_KEY

PRIVATE_KEY=$(cat server_private.key)
SERVER_CONF="/etc/wireguard/wg0.conf"

if systemctl is-active --quiet wg-quick@wg0; then
    echo "[+] Stopping existing WireGuard interface..."
    sudo systemctl stop wg-quick@wg0
fi
if [ -f "$SERVER_CONF" ]; then
    echo "[+] Existing config found. Deleting $SERVER_CONF..."
    sudo rm -f "$SERVER_CONF"
fi

echo "[+] Writing WireGuard server config to $SERVER_CONF..."

cat <<EOF | sudo tee $SERVER_CONF > /dev/null
[Interface]
Address = $SERVER_WG_IP/24
PrivateKey = $PRIVATE_KEY
ListenPort = 51820
SaveConfig = true

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_WG_IP/32
EOF


echo "[+] Starting and enabling WireGuard..."
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0 --no-pager

echo "[+] WireGuard status:"
sudo wg

echo "[+] Testing ping to client ($CLIENT_WG_IP)..."

# === PING LOOP: MAX 2 MENIT ===
TIMEOUT=120
INTERVAL=5
ELAPSED=0
CONNECTED=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    if ping -c 1 -W 1 "$CLIENT_WG_IP" &>/dev/null; then
        CONNECTED=true
        break
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "[-] Waiting for client... ($ELAPSED seconds elapsed)"
done

if $CONNECTED; then
    echo "[+] Client is reachable via ping!"
    
    echo "[+] Starting ping monitor in screen session..."
    screen -S ping -dm ping "$CLIENT_WG_IP"

    echo "[+] Setting up iptables to forward port 80 to client..."
    sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination "$CLIENT_WG_IP:80"
    sudo iptables -t nat -A POSTROUTING -j MASQUERADE

    echo "[✓] Setup completed successfully."
else
    echo "[✗] Setup gagal, mohon coba lagi. Client tidak bisa dihubungi dalam 2 menit."
    exit 1
fi
