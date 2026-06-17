#!/usr/bin/env bash
# One-time local setup: install the Ansible collections this project needs.
set -euo pipefail
cd "$(dirname "$0")/.."

ansible-galaxy collection install -r requirements.yml
echo "Done. Collections installed."
