#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
BASE="/var/log/endpoint2"
BKDIR="${BASE}/backup"
LOGSDIR="${BASE}/logs"

mkdir -p "${BKDIR}"

if [ -d "${LOGSDIR}" ]; then
  mv "${LOGSDIR}" "/tmp/endpoint2-logs-${TS}"
  mkdir -p "${LOGSDIR}"
  tar -czf "${BKDIR}/logs-${TS}.tar.gz" -C /tmp "endpoint2-logs-${TS}" || true
  rm -rf "/tmp/endpoint2-logs-${TS}"
fi

