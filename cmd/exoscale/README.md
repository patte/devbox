# cmd/exoscale

Small scripts to create/list/delete boxes on [Exoscale][exo] Compute. The
Hetzner equivalents live in [`../hetzner/`](../hetzner/) and the Infomaniak ones
in [`../infomaniak/`](../infomaniak/); these mirror their interface.

[exo]: https://www.exoscale.com/compute/

## Prerequisites

- `jq` and the `exo` CLI (`brew install exoscale-cli`).
- `EXOSCALE_KEY` and `EXOSCALE_SECRET` (an IAM key/secret pair) exported in the
  environment. They live in `ansible/secrets.txt`:
  `set -a; source ../../ansible/secrets.txt; set +a`.

The `exo` CLI requires an account in its TOML config; environment variables only
*override* an existing account's credentials. To avoid writing the secret to the
shared config, `lib.sh` generates an **ephemeral, mode-600 config file** at
runtime (in a temp dir, removed on exit) carrying the key/secret from the
environment — the secret never lands on disk or in shell history.

## Usage

```sh
set -a; source ../../ansible/secrets.txt; set +a   # exports $EXOSCALE_KEY/$EXOSCALE_SECRET

./list.sh                                  # list instances in the zone (or: ./list.sh all)
./create.sh box1                           # create + wait for SSH, prints IPv4
./delete.sh box1                           # delete by name (or id), scoped to the zone
./ensure-key.sh devbox ~/.ssh/id_ed25519.pub  # register an SSH key (optional)
```

`create.sh NAME [TYPE] [TEMPLATE] [DISK_GB] [PUBKEY_FILE]` defaults to a
`standard.large` type (4 vCPU / 8 GB, ~Hetzner cx33 class), the
`Linux Ubuntu 26.04 LTS 64-bit` template, an 80 GB disk, and the pubkey
(default `${DEVBOX_SSH_KEY}.pub`, else `~/.ssh/id_ed25519.pub`) injected into
`root` via cloud-init so the root-based ansible bootstrap works. It also ensures
a `devbox` security group (see below) and attaches it.

## Notes

- **Zone:** defaults to `ch-dk-2` (where the account's other boxes live).
  Override with `EXOSCALE_ZONE=de-fra-1` (any zone from `exo zone`). Every script
  is scoped to this zone — `delete.sh` resolves names within it, so it can never
  act on a box in another zone.
- **Firewall:** Exoscale's `default` security group does not open SSH from the
  internet, so a fresh box is otherwise unreachable. `create.sh` ensures a
  `devbox` security group that opens SSH (22/tcp, v4+v6), Tailscale (41641/udp),
  and ICMP echo from anywhere, with open egress, and attaches it. The account's
  existing groups are left untouched. The host's own UFW (`system_setup` role)
  and `ssh_tailscale_only` are the inner layer that actually restricts SSH to the
  tailnet after provisioning.
- **Provisioning:** once `create.sh` prints the IP, point an inventory host at it
  and run the ansible flow exactly as for Hetzner — see
  [`../../ansible/README.md`](../../ansible/README.md) and
  [`../../AGENTS.md`](../../AGENTS.md).
