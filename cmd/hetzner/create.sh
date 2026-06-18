#!/usr/bin/env bash
# Create a Hetzner Cloud server and wait until SSH is reachable.
# Prints the server's public IPv4 on success.
#
# Usage: create.sh NAME [TYPE] [IMAGE] [LOCATION] [SSH_KEY_NAMES]
#   TYPE           default cx33
#   IMAGE          default ubuntu-26.04
#   LOCATION       default nbg1
#   SSH_KEY_NAMES  comma-separated Hetzner ssh-key names (default: $HCLOUD_SSH_KEYS)
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

NAME="${1:?usage: create.sh NAME [TYPE] [IMAGE] [LOCATION] [SSH_KEY_NAMES]}"
TYPE="${2:-cx33}"
IMAGE="${3:-ubuntu-26.04}"
LOCATION="${4:-nbg1}"
KEYS_CSV="${5:-${HCLOUD_SSH_KEYS:-}}"
[[ -n "$KEYS_CSV" ]] || { echo "no ssh keys given (arg 5 or HCLOUD_SSH_KEYS)" >&2; exit 1; }

# Reuse if it already exists.
if id="$(server_id_by_name "$NAME")" && [[ -n "$id" ]]; then
  echo "server '$NAME' already exists (id $id)" >&2
else
  # Resolve each ssh key (name or id) to its numeric id. Hetzner's API nominally
  # accepts names here, but attaching by name has proven unreliable — attaching
  # by id reliably injects the key into root's authorized_keys.
  ids=()
  IFS=',' read -ra _keys <<< "$KEYS_CSV"
  for k in "${_keys[@]}"; do
    if [[ "$k" =~ ^[0-9]+$ ]]; then
      ids+=("$k")
    else
      kid="$(hapi GET "ssh_keys?name=$k" | jq -r '.ssh_keys[0].id // empty')"
      [[ -n "$kid" ]] || { echo "ssh key '$k' not found in project" >&2; exit 1; }
      ids+=("$kid")
    fi
  done
  keys_json="$(printf '%s\n' "${ids[@]}" | jq -cR . | jq -cs 'map(tonumber)')"
  # Optional cloud-init user_data (rarely needed now that keys attach by id).
  user_data="${HCLOUD_USER_DATA:-}"
  body="$(jq -n --arg n "$NAME" --arg t "$TYPE" --arg i "$IMAGE" --arg l "$LOCATION" \
    --argjson keys "$keys_json" --arg ud "$user_data" \
    '{name:$n, server_type:$t, image:$i, location:$l, ssh_keys:$keys, start_after_create:true, public_net:{enable_ipv4:true, enable_ipv6:true}}
     + (if $ud=="" then {} else {user_data:$ud} end)')"
  echo "creating $NAME ($TYPE, $IMAGE, $LOCATION)..." >&2
  hapi POST "servers" "$body" >/dev/null
fi

# Resolve IP.
ip=""
for _ in $(seq 1 30); do
  ip="$(hapi GET "servers?name=$NAME" | jq -r '.servers[0].public_net.ipv4.ip // empty')"
  [[ -n "$ip" ]] && break
  sleep 2
done
[[ -n "$ip" ]] || { echo "could not resolve IP for $NAME" >&2; exit 1; }
echo "ip: $ip" >&2

# Wait for SSH to accept connections. Use DEVBOX_SSH_KEY (a passphrase-less key)
# so the check works headless; restrict to that key only to avoid agent keys
# that may require a passphrase or a hardware-token touch.
key_opt=()
if [[ -n "${DEVBOX_SSH_KEY:-}" ]]; then
  key_opt=(-i "$DEVBOX_SSH_KEY" -o IdentitiesOnly=yes -o IdentityAgent=none)
fi
echo "waiting for ssh on $ip ..." >&2
for _ in $(seq 1 60); do
  if ssh "${key_opt[@]}" -o BatchMode=yes -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@$ip" true 2>/dev/null; then
    echo "ssh ready" >&2
    break
  fi
  sleep 5
done

echo "$ip"
