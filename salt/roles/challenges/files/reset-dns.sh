#!/usr/bin/env bash
set -euo pipefail
sed -i '/www\.wikipedia\.org/d' /etc/hosts || true
systemctl reload nginx || true
echo "[*] DNS hosts reset complete."
