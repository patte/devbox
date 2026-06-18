#!/usr/bin/env bash
# Shared helpers for the Infomaniak Public Cloud (OpenStack) scripts.
#
# Auth: the non-secret project/user config lives in clouds.yaml (committed,
# password left empty). The password is read from $INFOMANIAK in the
# environment (never passed on the command line). Source it from
# ansible/secrets.txt: `set -a; source ansible/secrets.txt; set +a`.
#
# Region/cloud is selectable via $INFOMANIAK_CLOUD (default: dc3-a). The other
# cloud defined in clouds.yaml is PCP-GYK2Y4A-dc4-a.
#
# Requires `jq` and the `openstack` client (python-openstackclient): either
# installed locally (`brew install openstackclient`) or, failing that, run
# ephemerally via `uvx` (no local install needed). Set $INFOMANIAK_OS_CMD to
# override the runner.
set -euo pipefail

: "${INFOMANIAK:?INFOMANIAK (OpenStack password) must be set in the environment}"

_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export OS_CLIENT_CONFIG_FILE="${OS_CLIENT_CONFIG_FILE:-$_here/clouds.yaml}"
export OS_CLOUD="${INFOMANIAK_CLOUD:-PCP-GYK2Y4A-dc3-a}"
export OS_PASSWORD="$INFOMANIAK"

# Resolve how to invoke the openstack client: a local install if present,
# otherwise uvx (uv's ephemeral tool runner). uvx downloads the client once and
# caches it, so only the first call is slow.
if [[ -n "${INFOMANIAK_OS_CMD:-}" ]]; then
  # shellcheck disable=SC2206
  _os_cmd=($INFOMANIAK_OS_CMD)
elif command -v openstack >/dev/null 2>&1; then
  _os_cmd=(openstack)
elif command -v uvx >/dev/null 2>&1; then
  _os_cmd=(uvx --from python-openstackclient openstack)
else
  echo "need the 'openstack' client (brew install openstackclient) or 'uvx' (part of uv)" >&2
  exit 1
fi

# os SUBCOMMAND...  -> run the openstack client with our auth/config.
os() { "${_os_cmd[@]}" "$@"; }

# server_id_by_name NAME  -> prints id (empty if not found)
server_id_by_name() {
  os server show "$1" -f value -c id 2>/dev/null || true
}

# server_ipv4 NAME  -> prints the first IPv4 address (empty if none yet)
server_ipv4() {
  os server show "$1" -f json 2>/dev/null \
    | jq -r '[.addresses[]?[]?] | map(select(test("^[0-9]+\\.")))[0] // empty'
}

# ensure_sg NAME  -> create (idempotently) a security group opening SSH +
# Tailscale + ICMP from anywhere, and print its name. The project's `default`
# group only allows ingress from its own members (not the internet), so a fresh
# box is unreachable without this. Egress is open (OpenStack's default rules).
# The host's own UFW (system_setup role) and ssh_tailscale_only are the inner
# layer that actually restricts SSH to the tailnet after provisioning.
ensure_sg() {
  local name="$1"
  if os security group show "$name" >/dev/null 2>&1; then echo "$name"; return; fi
  echo "creating security group '$name' (ssh + tailscale + icmp)..." >&2
  os security group create "$name" \
    --description "coder dev boxes: ssh + tailscale + icmp" >/dev/null
  os security group rule create --ingress --protocol tcp --dst-port 22 \
    --ethertype IPv4 --remote-ip 0.0.0.0/0 "$name" >/dev/null
  os security group rule create --ingress --protocol tcp --dst-port 22 \
    --ethertype IPv6 --remote-ip ::/0 "$name" >/dev/null
  os security group rule create --ingress --protocol udp --dst-port 41641 \
    --ethertype IPv4 --remote-ip 0.0.0.0/0 "$name" >/dev/null
  os security group rule create --ingress --protocol icmp \
    --ethertype IPv4 --remote-ip 0.0.0.0/0 "$name" >/dev/null
  echo "$name"
}
