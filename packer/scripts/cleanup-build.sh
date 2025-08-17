#!/usr/bin/env bash
set -euo pipefail
# remove build deps if you want even leaner images
sudo apt-get autoremove -y
sudo apt-get clean
# leave salt-minion binaries but disabled to avoid trainee confusion
sudo rm -rf /tmp/salt
