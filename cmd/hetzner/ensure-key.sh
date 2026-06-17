#!/usr/bin/env bash
# Ensure an SSH public key is registered in the Hetzner project.
# Prints the key name to use when creating servers. Idempotent (matches by
# fingerprint, so re-uploading the same key reuses the existing entry).
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

pub="$(cat "$PUBKEY_FILE")"

# Already present (by exact public key match)?
existing="$(hapi GET "ssh_keys?per_page=100" \
  | jq -r --arg pub "$pub" '.ssh_keys[] | select((.public_key|rtrimstr("\n")|split(" ")[0:2]|join(" ")) == ($pub|split(" ")[0:2]|join(" "))) | .name' \
  | head -1)"

if [[ -n "$existing" ]]; then
  echo "$existing"
  exit 0
fi

# Avoid name collision: if NAME taken by a different key, suffix it.
if hapi GET "ssh_keys?name=$NAME" | jq -e '.ssh_keys|length>0' >/dev/null; then
  NAME="${NAME}-$(echo "$pub" | awk '{print $2}' | cut -c1-8)"
fi

body="$(jq -n --arg n "$NAME" --arg k "$pub" '{name:$n, public_key:$k}')"
hapi POST "ssh_keys" "$body" | jq -r '.ssh_key.name'
