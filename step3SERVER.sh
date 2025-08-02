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
echo "[+] Enabling IPv4 forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo sed -i 's/^#\?net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf

echo "[+] Writing WireGuard server config to $SERVER_CONF..."

cat <<EOF | sudo tee $SERVER_CONF > /dev/null
[Interface]
Address = $SERVER_WG_IP/24
PrivateKey = $PRIVATE_KEY
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; \
         iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; \
         iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination $CLIENT_WG_IP:8080
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; \
           iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination $CLIENT_WG_IP:8080

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





