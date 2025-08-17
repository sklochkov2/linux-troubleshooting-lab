#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update
sudo apt-get install -y curl jq lsof strace rsyslog nginx php-fpm php-cli software-properties-common php8.3-curl

# Try Ubuntu repo first (enable universe if needed)
if ! apt-cache show salt-minion >/dev/null 2>&1; then
  sudo add-apt-repository -y universe || true
  sudo apt-get update
fi

if apt-cache show salt-minion >/dev/null 2>&1; then
  echo "[*] Installing salt-minion from Ubuntu repos"
  sudo apt-get install -y salt-minion
else
  echo "[*] Ubuntu repos don’t have salt-minion; installing via Salt bootstrap"
  wget -qO bootstrap-salt.sh https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh
  sudo sh bootstrap-salt.sh stable 3006.14
fi

# masterless; don’t leave the service running/enabled
sudo systemctl disable --now salt-minion || true

# copy states into place
sudo mkdir -p /srv/salt
sudo rsync -a /tmp/salt/ /srv/salt/
