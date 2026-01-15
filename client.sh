#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Script harus dijalankan sebagai root"
    echo "Gunakan: sudo $0"
    exit 1
fi

echo "Script berjalan sebagai root"
# Lanjutkan dengan kode lainnya di sini