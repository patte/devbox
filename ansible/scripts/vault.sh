#!/usr/bin/env bash
# Thin wrapper around ansible-vault that uses this project's vault-pw.sh.
#
# Usage:
#   scripts/vault.sh encrypt inventory/group_vars/vault.yml
#   scripts/vault.sh edit    inventory/group_vars/vault.yml
#   scripts/vault.sh view    inventory/group_vars/vault.yml
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ANSIBLE_VAULT_PASSWORD:-}" ]]; then
  echo "ERROR: export ANSIBLE_VAULT_PASSWORD before running." >&2
  exit 1
fi

exec ansible-vault "$@"
