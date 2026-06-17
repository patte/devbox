#!/usr/bin/env bash
# Provision coding host(s), connecting as the dev user (default: patte).
#
# Usage:
#   scripts/provision.sh                       # all hosts in [coding]
#   scripts/provision.sh --limit box2          # a single host
#   scripts/provision.sh --tags dev_tools      # only re-run a role/tag
#
# Use scripts/bootstrap.sh instead for a fresh, root-only host.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ANSIBLE_VAULT_PASSWORD:-}" ]]; then
  echo "ERROR: export ANSIBLE_VAULT_PASSWORD before running (used to decrypt the vault)." >&2
  exit 1
fi

exec ansible-playbook playbooks/provision.yml "$@"
