#!/usr/bin/env bash
# First-time setup of a fresh, root-only host (e.g. Hetzner).
# Connects as root and creates the unprivileged dev user (create_user role).
# Run this ONCE; then use scripts/provision.sh (which connects as that user) for
# the actual provisioning and all future runs.
#
# Usage:
#   scripts/bootstrap.sh --limit box1
#   then: scripts/provision.sh --limit box1
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ANSIBLE_VAULT_PASSWORD:-}" ]]; then
  echo "ERROR: export ANSIBLE_VAULT_PASSWORD before running (used to decrypt the vault)." >&2
  exit 1
fi

exec ansible-playbook playbooks/bootstrap.yml -u root "$@"
