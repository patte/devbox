#!/usr/bin/env bash
# Ensure an SSH public key is registered as an Exoscale SSH key.
# Prints the key name to use when creating instances. Idempotent: if a key with
# NAME already exists it is reused as-is.
#
# Note: create.sh also injects the key directly into root via cloud-init (so the
# existing root-based ansible bootstrap works). The registered Exoscale SSH key
# additionally lands on the image's default `ubuntu` user — handy but optional;
# create.sh manages the key itself.
#
# Usage: ensure-key.sh [NAME] [PUBKEY_FILE]
#   NAME         defaults to "coder"
#   PUBKEY_FILE  defaults to ~/.ssh/id_ed25519.pub
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

NAME="${1:-coder}"
PUBKEY_FILE="${2:-$HOME/.ssh/id_ed25519.pub}"
[[ -f "$PUBKEY_FILE" ]] || { echo "no such pubkey file: $PUBKEY_FILE" >&2; exit 1; }

if exo compute ssh-key show "$NAME" >/dev/null 2>&1; then
  echo "ssh key '$NAME' already exists" >&2
  echo "$NAME"
  exit 0
fi

exo compute ssh-key register "$NAME" "$PUBKEY_FILE" >/dev/null
echo "$NAME"
