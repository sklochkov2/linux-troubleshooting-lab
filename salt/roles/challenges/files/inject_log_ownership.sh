#!/usr/bin/env bash
set -euo pipefail
# Break permissions so endpoint2 (running as endpoint2) cannot write
chown -R root:root /var/log/endpoint2/logs || true
chmod 0755 /var/log/endpoint2 || true
systemctl restart endpoint2 || true
