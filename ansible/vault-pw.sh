#!/usr/bin/env bash
# Ansible reads the vault password from this script.
# Provide it via the ANSIBLE_VAULT_PASSWORD env var, e.g.:
#   export ANSIBLE_VAULT_PASSWORD="my-secret"
# or drop it in a file and `export ANSIBLE_VAULT_PASSWORD="$(cat ~/.config/coder/vault-pw)"`.
echo "${ANSIBLE_VAULT_PASSWORD:-}"
