set -euo pipefail

# ------------------ Tanya user tentang adapter ------------------
read -p "Apakah Anda sudah tahu nama adapter yang menuju ke internet dengan IP Public? (y/n): " ANSWER

if [[ "$ANSWER" != "y" && "$ANSWER" != "Y" ]]; then
    echo "Silakan cek nama adapter terlebih dahulu dengan: ip a atau ifconfig"
    exit 0
fi

read -p "Masukkan nama adapter (contoh: eth0, ens3, enp0s3): " ADAPTER

if [[ -z "$ADAPTER" ]]; then
    echo "Nama adapter tidak boleh kosong!" >&2
    exit 1
fi

echo "Adapter yang dipilih: $ADAPTER"
#SERVER SETTINGS
WG_FILE=wg0
WG_DIR=/etc/wireguard
SRV_ADDR_CIDR="10.8.0.1/24"
SRV_PORT=51820 #default, silahkan ganti

#FIRST CLIENT SETTINGS
PEER_NAME="peer1"
PEER_ADDR_HOST="10.8.0.2"
PEER_ALLOWED="10.8.0.2/32"

# ------------------ Root check ------------------
if [[ $EUID -ne 0 ]]; then
    echo "Harus dijalankan sebagai root (sudo su -)" >&2
    exit 1
fi

# ------------------ Update package list ------------------
echo "Updating package list..."
apt update
# ------------------ Stop WireGuard jika aktif ------------------
if systemctl is-active --quiet wg-quick@${WG_FILE}; then
    echo "Men-stop service wg-quick@${WG_FILE}..."
    systemctl stop wg-quick@${WG_FILE}
fi
# ------------------ Install paket ------------------
if ! command -v wg >/dev/null 2>&1; then
  apt update
  apt install -y wireguard wireguard-tools resolvconf || true
fi

# ------------------ Check Public IP ------------------
echo "Mendapatkan Public IP..."
PUBLIC_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || curl -s -4 ipinfo.io/ip)

if [[ -z "$PUBLIC_IP" ]]; then
    echo "Gagal mendapatkan Public IP. Silakan periksa koneksi internet." >&2
    exit 1
fi

echo "Public IP Server: $PUBLIC_IP"

# ------------------ Generate Keys ------------------
echo "Generating server keys..."
SRV_PRIVATE_KEY=$(wg genkey)
SRV_PUBLIC_KEY=$(echo "$SRV_PRIVATE_KEY" | wg pubkey)
echo "Generating peer keys..."
PEER_PRIVATE_KEY=$(wg genkey)
PEER_PUBLIC_KEY=$(echo "$PEER_PRIVATE_KEY" | wg pubkey)
echo "Peer Public Key: $PEER_PUBLIC_KEY"
echo "Server Public Key: $SRV_PUBLIC_KEY"

# ------------------ Generate wg0.conf ------------------
WG_CONF_PATH="${WG_DIR}/${WG_FILE}.conf"

if [[ -f "$WG_CONF_PATH" ]]; then
    echo "File $WG_CONF_PATH sudah ada, menghapus file lama..."
    rm -f "$WG_CONF_PATH"
fi

echo "Membuat file konfigurasi $WG_CONF_PATH..."
cat > "$WG_CONF_PATH" <<EOF
[Interface]
PrivateKey = $SRV_PRIVATE_KEY
Address = $SRV_ADDR_CIDR
ListenPort = $SRV_PORT

[Peer]
# $PEER_NAME
PublicKey = $PEER_PUBLIC_KEY
AllowedIPs = $PEER_ALLOWED

EOF

chmod 600 "$WG_CONF_PATH"
echo "File konfigurasi server berhasil dibuat."

# ------------------ Enable IPv4 Forwarding ------------------
echo "Mengaktifkan IPv4 forwarding..."
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1
echo "IPv4 forwarding telah diaktifkan."


# ------------------ Start WireGuard service ------------------
echo "Memulai WireGuard service..."
systemctl enable wg-quick@${WG_FILE}
systemctl start wg-quick@${WG_FILE}

# Tunggu interface wg0 benar-benar up
sleep 2

echo "Status WireGuard:"
systemctl status wg-quick@${WG_FILE} --no-pager

# Cek apakah interface wg0 sudah ada
if ! ip link show wg0 >/dev/null 2>&1; then
    echo "Interface wg0 tidak ditemukan!" >&2
    exit 1
fi

echo "Interface wg0 aktif."

# ------------------ Configure iptables forwarding rules ------------------
echo "Mengkonfigurasi iptables forwarding rules..."

# Remove existing rules to prevent duplicates
iptables -D FORWARD -i "$ADAPTER" -o wg0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i wg0 -o "$ADAPTER" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT 2>/dev/null || true

# Allow input UDP traffic on WireGuard port
iptables -D INPUT -p udp --dport "$SRV_PORT" -j ACCEPT 2>/dev/null || true
iptables -I INPUT 1 -p udp --dport "$SRV_PORT" -j ACCEPT

# Insert at beginning (before REJECT rule)
iptables -I FORWARD 1 -i wg0 -o wg0 -j ACCEPT
iptables -I FORWARD 2 -i "$ADAPTER" -o wg0 -j ACCEPT
iptables -I FORWARD 3 -i wg0 -o "$ADAPTER" -j ACCEPT

# Configure NAT/MASQUERADE for routing
iptables -t nat -D POSTROUTING -o "$ADAPTER" -j MASQUERADE 2>/dev/null || true
iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE 2>/dev/null || true
iptables -t nat -A POSTROUTING -o "$ADAPTER" -j MASQUERADE
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE

echo "iptables forwarding rules telah ditambahkan."
echo ""
echo "Aturan FORWARD aktif:"
iptables -L FORWARD -n -v --line-numbers

echo ""
echo "Aturan NAT aktif:"
iptables -t nat -L POSTROUTING -n -v

# ------------------ Install & Save iptables persistent ------------------

apt install -y iptables-persistent netfilter-persistent

# Simpan rules IPv4 saat ini
echo "Menyimpan aturan iptables"
netfilter-persistent save || true

# Pastikan service aktif saat boot
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent

echo "iptables-persistent aktif. Rules akan tetap ada setelah reboot."

# ------------------ Generate Client Config ------------------
echo ""
echo "=========================================="
echo "KONFIGURASI CLIENT (${PEER_NAME})"
echo "=========================================="
echo ""

cat <<EOF
[Interface]
PrivateKey = $PEER_PRIVATE_KEY
Address = $PEER_ADDR_HOST/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SRV_PUBLIC_KEY
Endpoint = $PUBLIC_IP:$SRV_PORT
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25

EOF

echo "=========================================="
echo "Copy konfigurasi di atas ke file client"
echo "=========================================="

echo "pastikan FIREWALL tidak block port 51820(UDP)"



