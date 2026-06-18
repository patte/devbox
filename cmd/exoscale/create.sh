#!/usr/bin/env bash
# Create an Exoscale Compute instance and wait until SSH is reachable.
# Prints the instance's public IPv4 on success.
#
# Usage: create.sh NAME [TYPE] [TEMPLATE] [DISK_GB] [PUBKEY_FILE]
#   TYPE         default standard.large (4 vCPU / 8 GB, ~Hetzner cx33 class)
#   TEMPLATE     default "Linux Ubuntu 26.04 LTS 64-bit"
#   DISK_GB      default 80 (matches the rest of the fleet)
#   PUBKEY_FILE  default ${CODER_SSH_KEY}.pub, else ~/.ssh/id_ed25519.pub
#
# Zone comes from $EXOSCALE_ZONE (default ch-dk-2). The pubkey is injected into
# root via cloud-init (the Ubuntu image disables root and logs in as `ubuntu`,
# but the root-based ansible bootstrap connects as root), and also registered as
# an Exoscale SSH key (lands on the default user too). A dedicated `coder`
# security group opening SSH/Tailscale/ICMP is ensured and attached — the
# account's `default` group is left untouched.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

NAME="${1:?usage: create.sh NAME [TYPE] [TEMPLATE] [DISK_GB] [PUBKEY_FILE]}"
TYPE="${2:-standard.large}"
TEMPLATE="${3:-Linux Ubuntu 26.04 LTS 64-bit}"
DISK_GB="${4:-80}"
PUBKEY_FILE="${5:-${CODER_SSH_KEY:+${CODER_SSH_KEY}.pub}}"
PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
[[ -f "$PUBKEY_FILE" ]] || { echo "no such pubkey file: $PUBKEY_FILE" >&2; exit 1; }
pub="$(cat "$PUBKEY_FILE")"

KEYPAIR="${EXOSCALE_KEYPAIR:-coder}"
SG="${EXOSCALE_SG:-coder}"

if id="$(instance_id_by_name "$NAME")" && [[ -n "$id" ]]; then
  echo "instance '$NAME' already exists (id $id) in $EXOSCALE_ZONE" >&2
else
  # Register the SSH key (idempotent) so it can be attached at boot.
  if ! exo compute ssh-key show "$KEYPAIR" >/dev/null 2>&1; then
    exo compute ssh-key register "$KEYPAIR" "$PUBKEY_FILE" >/dev/null
  fi

  # Ensure the `coder` security group (ssh + tailscale + icmp from anywhere).
  ensure_sg "$SG" >/dev/null

  # cloud-init: put the key on root and re-enable root SSH login.
  user_data="$(mktemp -t coder-exoscale-userdata.XXXXXX)"
  # Extend lib.sh's EXIT trap to also drop the user_data file. _exo_cfgdir is set
  # in lib.sh (sourced above); re-include it so the config still gets cleaned up.
  # shellcheck disable=SC2154
  trap 'rm -f "$user_data"; rm -rf "$_exo_cfgdir"' EXIT
  cat >"$user_data" <<EOF
#cloud-config
disable_root: false
users:
  - name: root
    ssh_authorized_keys:
      - $pub
EOF

  echo "creating $NAME ($TYPE, $TEMPLATE, ${DISK_GB}GB, $EXOSCALE_ZONE)..." >&2
  exo compute instance create "$NAME" \
    --zone "$EXOSCALE_ZONE" \
    --instance-type "$TYPE" \
    --template "$TEMPLATE" \
    --disk-size "$DISK_GB" \
    --ssh-key "$KEYPAIR" \
    --security-group "$SG" \
    --cloud-init "$user_data" \
    >/dev/null
fi

# Resolve public IPv4.
ip=""
for _ in $(seq 1 30); do
  ip="$(instance_ipv4 "$NAME")"
  [[ -n "$ip" && "$ip" != "null" ]] && break
  sleep 2
done
[[ -n "$ip" && "$ip" != "null" ]] || { echo "could not resolve IP for $NAME" >&2; exit 1; }
echo "ip: $ip" >&2

# Wait for SSH as root. Use CODER_SSH_KEY (a passphrase-less key) when set so the
# check works headless; restrict to that key to avoid agent keys that need a
# passphrase or a hardware-token touch.
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
