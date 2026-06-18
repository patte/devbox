#!/usr/bin/env bash
# Ensure an SSH public key is registered as a Nova keypair in the project.
# Prints the keypair name to use when creating servers. Idempotent: if a
# keypair with NAME already exists it is reused as-is.
#
# Note: create.sh also injects the key directly into root via cloud-init (so the
# existing root-based ansible bootstrap works). A Nova keypair additionally
# lands the key on the image's default `ubuntu` user, which is handy for the
# web console — but it is optional; create.sh manages the keypair itself.
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

if os keypair show "$NAME" >/dev/null 2>&1; then
  echo "keypair '$NAME' already exists" >&2
  echo "$NAME"
  exit 0
fi

os keypair create --public-key "$PUBKEY_FILE" "$NAME" >/dev/null
echo "$NAME"
