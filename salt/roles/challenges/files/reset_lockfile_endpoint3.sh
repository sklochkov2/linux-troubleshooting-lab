#!/usr/bin/env bash
set -euo pipefail
LOCK="/var/lib/endpoint3/maintenance.lock"
rm -f "$LOCK"
systemctl restart endpoint3 || true
echo "[*] endpoint3 lock removed"
