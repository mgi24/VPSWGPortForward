#!/bin/bash

set -e

echo "[+] Installing WireGuard..."
sudo apt update
sudo apt install -y wireguard

echo "[+] Generating server keys..."
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

echo "[+] Server public key (share this to client):"
cat server_public.key
