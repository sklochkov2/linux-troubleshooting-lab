#!/usr/bin/env bash
set -euo pipefail
# Poison /etc/hosts so wikipedia resolves to a bogus IP, breaking the PHP request.
if ! grep -q 'www\.wikipedia\.org' /etc/hosts; then
  echo "10.0.0.1 www.wikipedia.org" >> /etc/hosts
fi
