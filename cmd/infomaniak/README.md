# cmd/infomaniak

Small scripts to create/list/delete boxes on [Infomaniak Public Cloud][ic],
which is plain OpenStack. The Hetzner equivalents live in
[`../hetzner/`](../hetzner/); these mirror their interface.

[ic]: https://www.infomaniak.com/en/hosting/public-cloud

## Prerequisites

- `jq`, and the `openstack` client (`python-openstackclient`). The scripts use a
  local install if present (`brew install openstackclient`); otherwise they fall
  back to running it via `uvx --from python-openstackclient openstack` (needs
  [uv][uv] — no local install required, downloaded once and cached). Override
  the runner with `$INFOMANIAK_OS_CMD`.

[uv]: https://docs.astral.sh/uv/
- `clouds.yaml` in this folder (gitignored — it carries your project/account
  identifiers, so it is per-project; see below).
- `INFOMANIAK` (the OpenStack API password) exported in the environment. It
  lives in `ansible/secrets.txt`:
  `set -a; source ansible/secrets.txt; set +a`.

### Getting `clouds.yaml`

1. In the [Infomaniak manager][mgr], create a **Public Cloud** product, then
   create a **project** inside it.
2. On the project, click the **⋮ (three dots)** → **Download the clouds.yml
   file**.
3. Drop it in this folder and rename it to `clouds.yaml`.

Leave the `password: ''` field empty — the scripts inject `$INFOMANIAK` at
runtime so the secret never lands on disk or in the shell history.

[mgr]: https://manager.infomaniak.com/

## Usage

```sh
set -a; source ../../ansible/secrets.txt; set +a   # exports $INFOMANIAK

./list.sh                                  # list servers
./create.sh box1                           # create + wait for SSH, prints IPv4
./delete.sh box1                           # delete by name (or id)
./ensure-key.sh coder ~/.ssh/id_ed25519.pub  # register a Nova keypair (optional)
```

`create.sh NAME [FLAVOR] [IMAGE] [NETWORK] [PUBKEY_FILE]` defaults to a
`a4-ram8-disk80-perf1` flavor (4 vCPU / 8 GB / 80 GB, ~Hetzner cx33), the
`Ubuntu 26.04 LTS Resolute Raccoon` image, and the shared `ext-net1` network
(which hands out a routable public IPv4 — no floating IP needed). The pubkey
(default `${CODER_SSH_KEY}.pub`, else `~/.ssh/id_ed25519.pub`) is injected into
`root` via cloud-init so the root-based ansible bootstrap works. It also
ensures a `coder` security group (see below) and attaches it.

## Notes

- **Region/cloud:** defaults to `dc3-a`. Override with
  `INFOMANIAK_CLOUD=PCP-XXXXXXX-dc4-a` (the cloud names come from `clouds.yaml`).
- **Firewall:** the project's `default` security group only allows ingress from
  its own members, so a fresh box is otherwise unreachable. `create.sh` ensures
  a `coder` security group that opens SSH (22/tcp), Tailscale (41641/udp), and
  ICMP from anywhere, with open egress, and attaches it. The host's own UFW
  (`system_setup` role) and `ssh_tailscale_only` are the inner layer that
  actually restricts SSH to the tailnet after provisioning.
- **Provisioning:** once `create.sh` prints the IP, point an inventory host at
  it and run the ansible flow exactly as for Hetzner — see
  [`../../ansible/README.md`](../../ansible/README.md) and
  [`../../AGENTS.md`](../../AGENTS.md).
