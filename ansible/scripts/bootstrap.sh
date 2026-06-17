#!/usr/bin/env bash
# First-time provision of a fresh, root-only host (e.g. Hetzner).
# Connects as root, which triggers the create_user role to make the dev user,
# then runs the full provision. After this, SSH root login is disabled, so use
# scripts/provision.sh (connecting as the dev user) from then on.
#
# Usage:
#   scripts/bootstrap.sh --limit box1
#   scripts/bootstrap.sh --limit box1 --tags create_user,system
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ANSIBLE_VAULT_PASSWORD:-}" ]]; then
  echo "ERROR: export ANSIBLE_VAULT_PASSWORD before running (used to decrypt the vault)." >&2
  exit 1
fi

exec ansible-playbook playbooks/provision.yml -u root "$@"
