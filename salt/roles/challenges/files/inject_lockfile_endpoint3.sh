#!/usr/bin/env bash
set -euo pipefail
LOCK="/var/lib/endpoint3/maintenance.lock"
mkdir -p "$(dirname "$LOCK")"
echo "maintenance mode enabled $(date -Is)" > "$LOCK"
chown root:root "$LOCK" || true
chmod 0644 "$LOCK" || true
systemctl restart endpoint3 || true
