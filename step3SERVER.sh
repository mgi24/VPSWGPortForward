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

echo "[+] Input public interface name (e.g., eth0, ens3):"
read -p "Public Interface: " PUBLIC_IF

# Collect port forwarding rules
PORT_FORWARD_RULES_POSTUP=()
PORT_FORWARD_RULES_POSTDOWN=()

while true; do
    echo "[+] Input public port to forward:"
    read -p "Port Public: " PORT_PUBLIC

    echo "[+] Input local port (on client):"
    read -p "Port Local: " PORT_LOCAL

    # Add rules for PostUp and PostDown
    PORT_FORWARD_RULES_POSTUP+=("iptables -t nat -A PREROUTING -i $PUBLIC_IF -p tcp --dport $PORT_PUBLIC -j DNAT --to-destination $CLIENT_WG_IP:$PORT_LOCAL;")
    PORT_FORWARD_RULES_POSTDOWN+=("iptables -t nat -D PREROUTING -i $PUBLIC_IF -p tcp --dport $PORT_PUBLIC -j DNAT --to-destination $CLIENT_WG_IP:$PORT_LOCAL;")

    read -p "Tambahkan port lagi? (y/n): " ADD_MORE
    [[ "$ADD_MORE" =~ ^[Yy]$ ]] || break
done

cat <<EOF | sudo tee $SERVER_CONF > /dev/null
[Interface]
Address = $SERVER_WG_IP/24
PrivateKey = $PRIVATE_KEY
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; \
         iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE; \
         iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT; \
         ${PORT_FORWARD_RULES_POSTUP[@]}
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE; \
           iptables -D INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT; \
           ${PORT_FORWARD_RULES_POSTDOWN[@]}
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





