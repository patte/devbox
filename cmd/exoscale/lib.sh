#!/usr/bin/env bash
# Shared helpers for the Exoscale Compute scripts.
#
# Auth: the `exo` CLI (egoscale v3) reads credentials from an account defined in
# its TOML config; environment variables only *override* an existing account's
# credentials, so env vars alone are not enough. To keep the secret off disk we
# generate an ephemeral, mode-600 config file at runtime (removed on exit) that
# carries the key/secret pulled from the environment. Set them from
# ansible/secrets.txt: `set -a; source ansible/secrets.txt; set +a`
# (exports $EXOSCALE_KEY and $EXOSCALE_SECRET).
#
# Zone is selectable via $EXOSCALE_ZONE (default: ch-dk-2, where the rest of the
# account's boxes live). Requires the `exo` CLI (brew install exoscale-cli) and
# jq.
set -euo pipefail

: "${EXOSCALE_KEY:?EXOSCALE_KEY must be set in the environment (source ansible/secrets.txt)}"
: "${EXOSCALE_SECRET:?EXOSCALE_SECRET must be set in the environment (source ansible/secrets.txt)}"

command -v exo >/dev/null 2>&1 || { echo "need the 'exo' CLI (brew install exoscale-cli)" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "need 'jq'" >&2; exit 1; }

export EXOSCALE_ZONE="${EXOSCALE_ZONE:-ch-dk-2}"

# Write an ephemeral exo config (the CLI requires a configured account; env vars
# only override one). The dir + file are mode 600 and removed when the script
# exits, so the secret never persists. Viper infers the format from the .toml
# extension, hence the fixed filename inside a temp dir.
_exo_cfgdir="$(mktemp -d -t devbox-exoscale-cfg.XXXXXX)"
chmod 700 "$_exo_cfgdir"
_exo_cfg="$_exo_cfgdir/exoscale.toml"
trap 'rm -rf "$_exo_cfgdir"' EXIT
( umask 077
  printf 'defaultaccount = "devbox"\ndefaultzone = "%s"\n[[accounts]]\nname = "devbox"\nkey = "%s"\nsecret = "%s"\ndefaultZone = "%s"\n' \
    "$EXOSCALE_ZONE" "$EXOSCALE_KEY" "$EXOSCALE_SECRET" "$EXOSCALE_ZONE" >"$_exo_cfg" )
export EXOSCALE_CONFIG="$_exo_cfg"

# exo SUBCOMMAND...  -> run the exo CLI with our ephemeral config. -Q silences
# the progress spinner (lots of redraw noise in non-interactive output).
exo() { command exo -Q -C "$_exo_cfg" "$@"; }

# instance_id_by_name NAME  -> prints id (empty if not found). Restricted to
# $EXOSCALE_ZONE so we never resolve (or act on) boxes in other zones.
instance_id_by_name() {
  exo compute instance list --zone "$EXOSCALE_ZONE" -O json 2>/dev/null \
    | jq -r --arg n "$1" '.[] | select(.name==$n) | .id' | head -n1
}

# instance_ipv4 NAME  -> prints the public IPv4 (empty if none yet).
instance_ipv4() {
  exo compute instance show "$1" --zone "$EXOSCALE_ZONE" -O json 2>/dev/null \
    | jq -r '.ip_address // .public_ip // empty'
}

# ensure_sg NAME  -> create (idempotently) a security group opening SSH +
# Tailscale + ICMP from anywhere, and print its name. The account's `default`
# group is left untouched. Egress is open by default on Exoscale. The host's own
# UFW (system_setup role) and ssh_tailscale_only are the inner layer that
# actually restricts SSH to the tailnet after provisioning.
ensure_sg() {
  local name="$1"
  if exo compute security-group show "$name" >/dev/null 2>&1; then echo "$name"; return; fi
  echo "creating security group '$name' (ssh + tailscale + icmp)..." >&2
  exo compute security-group create "$name" \
    --description "devbox dev boxes: ssh + tailscale + icmp" >/dev/null
  # SSH (tcp/22) from anywhere, v4 + v6.
  exo compute security-group rule add "$name" --flow ingress \
    --protocol tcp --port 22 --network 0.0.0.0/0 >/dev/null
  exo compute security-group rule add "$name" --flow ingress \
    --protocol tcp --port 22 --network ::/0 >/dev/null
  # Tailscale (udp/41641) from anywhere.
  exo compute security-group rule add "$name" --flow ingress \
    --protocol udp --port 41641 --network 0.0.0.0/0 >/dev/null
  # ICMP echo from anywhere (type 8 / code 0).
  exo compute security-group rule add "$name" --flow ingress \
    --protocol icmp --icmp-type 8 --icmp-code 0 --network 0.0.0.0/0 >/dev/null
  echo "$name"
}
