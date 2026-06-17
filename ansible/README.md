# coder — Ansible provisioning for remote coding environments

Provisions Ubuntu hosts into carefree playfields for AI agents: hardened base
system, optional Tailscale, and a developer toolchain (nvm + Node, Claude Code,
Rust, atuin, btop, podman + compose, zsh + starship). Your laptop stays "just a
terminal" — you SSH in over tailscale.

## Layout

```
ansible/
├── ansible.cfg
├── requirements.yml            # ansible collections
├── vault-pw.sh                 # reads ANSIBLE_VAULT_PASSWORD from env
├── inventory/
│   ├── hosts                   # your hosts, in the [coding] group
│   └── group_vars/
│       └── all/                # loaded for every host (a dir, so secrets split out)
│           ├── vars.yml        # non-secret config
│           ├── vault.example.yml  # template for secrets -> copy to vault.yml
│           └── vault.yml       # your encrypted secrets (you create this)
├── playbooks/
│   ├── bootstrap.yml           # create the dev user (run as root, once)
│   └── provision.yml           # everything else (run as the dev user)
├── roles/
│   ├── create_user/            # makes the dev user (+ passwordless sudo)
│   ├── system_setup/           # ssh hardening, ufw, unattended-upgrades, ...
│   ├── tailscale/              # optional per host (tailscale_enabled); waits for signing
│   ├── dev_tools/              # node, Claude Code, Rust, atuin, btop, podman+compose, zsh+starship
│   └── ssh_tailscale_only/     # close public SSH, allow only over tailscale (runs last)
└── scripts/
    ├── setup.sh                # install ansible collections (run once)
    ├── bootstrap.sh            # create dev user on a fresh root-only host
    ├── provision.sh            # provision / all future runs (as dev user)
    ├── ping.sh                 # connectivity check
    └── vault.sh                # ansible-vault wrapper
```

> Secrets live in `group_vars/all/` as a **directory** on purpose: Ansible only
> auto-loads `group_vars/<name>` for a group called `<name>`, so a lone
> `group_vars/vault.yml` would never load. Files inside `group_vars/all/` all
> load for every host.

## Setup (once)

```bash
cd ansible
./scripts/setup.sh                       # install ansible collections
export ANSIBLE_VAULT_PASSWORD="…"        # pick a vault password

cp inventory/group_vars/all/vault.example.yml inventory/group_vars/all/vault.yml
# edit vault.yml: ansible_become_pass + tailscale OAuth creds
./scripts/vault.sh encrypt inventory/group_vars/all/vault.yml
```

Add your hosts to `inventory/hosts` (see the examples in that file).

## Provisioning

**Fresh Hetzner box (root only on init)** — two steps:

```bash
./scripts/bootstrap.sh --limit box1      # as root: create the patte user
./scripts/provision.sh --limit box1      # as patte: harden, tailscale, tools, lockdown
```

Bootstrap and provision are split because `system_setup` disables root SSH login
and may reboot the host (kernel updates). If the whole run happened over the root
connection it would lock itself out after that reboot — so the dev user is
created first, and all the rest runs as that user, who survives root being
disabled.

**Signing step (tailnet lock):** during provision the tailscale role brings the
node onto your tailnet and then *waits* until the node has connectivity/DNS. If
your tailnet has tailnet lock enabled, the node is "locked out" until you sign it
— do that at <https://login.tailscale.com/admin/machines> and the run continues
on its own.

**SSH lockdown:** the last role closes SSH on the public interface and only
allows it over `tailscale0`. So after the first successful provision, reach the
box by its tailscale name and point the inventory at it:

```ini
box1 ansible_host=box1.<your-tailnet>.ts.net
```

**Everything afterwards** (connects as the dev user, over tailscale):

```bash
./scripts/provision.sh --limit box1
./scripts/provision.sh                       # all hosts
./scripts/provision.sh --tags dev_tools      # re-run one part
```

## Per-host knobs

Set these as host vars in `inventory/hosts`:

- `tailscale_enabled=false` — skip Tailscale on that host. (Also keeps public SSH
  open, since the SSH-over-tailscale lockdown is skipped without a tailnet.)
- `ssh_tailscale_only=false` — keep public SSH open even with tailscale enabled.

## Notes / decisions

- **Dev user:** `patte` (see `dev_user` in `group_vars/all/vars.yml`).
- **Secrets:** ansible-vault; the password comes from `ANSIBLE_VAULT_PASSWORD`.
- **Passwordless sudo** for the dev user: keeps provisioning reliable across
  `sudo` and `sudo-rs` (Ubuntu 26.04+ ships sudo-rs, whose password prompt the
  ansible become plugin can't detect). Appropriate for a single-user, key-only,
  tailscale-fronted sandbox. Remove the relevant task in `create_user` to require
  a sudo password instead.
- **Tailscale** joins via an OAuth client that mints a tagged, preauthorized key
  per host. MagicDNS stays on; provision waits for connectivity (and signing,
  under tailnet lock) before continuing.
- **SSH is tailnet-only** after provisioning: UFW allows port 22 only on
  `tailscale0` and drops the public allow rule (applied last, so the in-flight
  run isn't cut off). Public SSH is refused thereafter.
- **Shell:** zsh + [starship](https://starship.rs) (no plugin framework); nvm and
  PATH load from `.zshenv`/top-of-`.bashrc` so tools resolve non-interactively.
- Dropped from the reference `system_setup`: Grafana Alloy monitoring and the
  extra (jonas) SSH key — not relevant here.
- **podman** is installed rootless: linger is enabled for the dev user and the
  user `podman.socket` is started, so agent containers keep running after logout.

## Creating / destroying Hetzner servers

Helper scripts (Hetzner Cloud API, token from `HCLOUD_TOKEN`) live in
`../cmd/hetzner`:

```bash
export HCLOUD_TOKEN="…"
cmd/hetzner/ensure-key.sh coder ~/.ssh/id_ed25519.pub   # register a key, prints its name
HCLOUD_SSH_KEYS=coder cmd/hetzner/create.sh box1        # cx33 / ubuntu-26.04 / nbg1 by default
cmd/hetzner/list.sh
cmd/hetzner/delete.sh box1
```

Note: SSH keys are attached **by id** (resolved from the name), since attaching
by name alone does not reliably inject the key into the server.
