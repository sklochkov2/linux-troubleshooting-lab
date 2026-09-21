#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-8000}"

if [[ ! -f "${ROOT}/dist/index.html" ]]; then
    echo "[!] Missing ${ROOT}/dist. Run 'make image' first." >&2
    exit 1
fi

echo "[*] Serving JSLinux lab at http://127.0.0.1:${PORT}/"
exec python3 -m http.server \
    --bind 127.0.0.1 \
    --directory "${ROOT}/dist" \
    "${PORT}"
