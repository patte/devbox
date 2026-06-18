#!/usr/bin/env bash
# Create an Infomaniak Public Cloud (OpenStack) server and wait until SSH is
# reachable. Prints the server's public IPv4 on success.
#
# Usage: create.sh NAME [FLAVOR] [IMAGE] [NETWORK] [PUBKEY_FILE]
#   FLAVOR       default a4-ram8-disk80-perf1 (4 vCPU / 8 GB / 80 GB, ~Hetzner cx33)
#   IMAGE        default "Ubuntu 26.04 LTS Resolute Raccoon"
#   NETWORK      default ext-net1 (shared, hands out a routable public IPv4)
#   PUBKEY_FILE  default ${CODER_SSH_KEY}.pub, else ~/.ssh/id_ed25519.pub
#
# The pubkey is injected into root via cloud-init (PermitRootLogin + key) so the
# existing root-based ansible bootstrap works, and registered as a Nova keypair
# (lands on the default `ubuntu` user too). The project's default security group
# already allows inbound, so no firewall setup is needed here.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

NAME="${1:?usage: create.sh NAME [FLAVOR] [IMAGE] [NETWORK] [PUBKEY_FILE]}"
FLAVOR="${2:-a4-ram8-disk80-perf1}"
IMAGE="${3:-Ubuntu 26.04 LTS Resolute Raccoon}"
NETWORK="${4:-ext-net1}"
PUBKEY_FILE="${5:-${CODER_SSH_KEY:+${CODER_SSH_KEY}.pub}}"
PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
[[ -f "$PUBKEY_FILE" ]] || { echo "no such pubkey file: $PUBKEY_FILE" >&2; exit 1; }
pub="$(cat "$PUBKEY_FILE")"

KEYPAIR="${INFOMANIAK_KEYPAIR:-coder}"
SG="${INFOMANIAK_SG:-coder}"

if id="$(server_id_by_name "$NAME")" && [[ -n "$id" ]]; then
  echo "server '$NAME' already exists (id $id)" >&2
else
  # Register the Nova keypair (idempotent) so it can be attached at boot.
  if ! os keypair show "$KEYPAIR" >/dev/null 2>&1; then
    os keypair create --public-key "$PUBKEY_FILE" "$KEYPAIR" >/dev/null
  fi

  # Open SSH/Tailscale/ICMP (the default SG only allows ingress from itself).
  ensure_sg "$SG" >/dev/null

  # cloud-init: put the key on root and re-enable root SSH login. OpenStack
  # Ubuntu images default the login user to `ubuntu` and disable root, but the
  # ansible bootstrap (create_user role) connects as root on a fresh box.
  user_data="$(mktemp -t coder-infomaniak-userdata.XXXXXX)"
  trap 'rm -f "$user_data"' EXIT
  cat >"$user_data" <<EOF
#cloud-config
disable_root: false
users:
  - name: root
    ssh_authorized_keys:
      - $pub
EOF

  echo "creating $NAME ($FLAVOR, $IMAGE, $NETWORK)..." >&2
  os server create \
    --flavor "$FLAVOR" \
    --image "$IMAGE" \
    --network "$NETWORK" \
    --key-name "$KEYPAIR" \
    --security-group "$SG" \
    --user-data "$user_data" \
    --wait \
    "$NAME" >/dev/null
fi

# Resolve public IPv4.
ip=""
for _ in $(seq 1 30); do
  ip="$(server_ipv4 "$NAME")"
  [[ -n "$ip" ]] && break
  sleep 2
done
[[ -n "$ip" ]] || { echo "could not resolve IP for $NAME" >&2; exit 1; }
echo "ip: $ip" >&2

# Wait for SSH as root. Use CODER_SSH_KEY (a passphrase-less key) when set so
# the check works headless; restrict to that key only to avoid agent keys that
# may require a passphrase or a hardware-token touch.
key_opt=()
if [[ -n "${CODER_SSH_KEY:-}" ]]; then
  key_opt=(-i "$CODER_SSH_KEY" -o IdentitiesOnly=yes -o IdentityAgent=none)
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
