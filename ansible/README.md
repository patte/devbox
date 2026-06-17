# coder — Ansible provisioning for remote coding environments

Provisions Ubuntu hosts into carefree playfields for AI agents: hardened base
system, optional Tailscale, and a developer toolchain (nvm + Node, Claude Code,
atuin, podman + compose). Your laptop stays "just a terminal" — you SSH in.

## Layout

```
ansible/
├── ansible.cfg
├── requirements.yml            # ansible collections
├── vault-pw.sh                 # reads ANSIBLE_VAULT_PASSWORD from env
├── inventory/
│   ├── hosts                   # your hosts, in the [coding] group
│   └── group_vars/
│       ├── all.yml             # non-secret config
│       ├── vault.example.yml   # template for secrets -> copy to vault.yml
│       └── vault.yml           # your encrypted secrets (you create this)
├── playbooks/
│   └── provision.yml
├── roles/
│   ├── create_user/            # makes the dev user; runs only when conn. as root
│   ├── system_setup/           # ssh hardening, ufw, unattended-upgrades, ...
│   ├── tailscale/              # optional per host (tailscale_enabled)
│   └── dev_tools/              # nvm+node, Claude Code, atuin, podman+compose
└── scripts/
    ├── setup.sh                # install ansible collections (run once)
    ├── bootstrap.sh            # first run on a fresh root-only host
    ├── provision.sh            # normal runs (connect as dev user)
    ├── ping.sh                 # connectivity check
    └── vault.sh                # ansible-vault wrapper
```

## Setup (once)

```bash
cd ansible
./scripts/setup.sh                       # install ansible collections
export ANSIBLE_VAULT_PASSWORD="…"        # pick a vault password

cp inventory/group_vars/vault.example.yml inventory/group_vars/vault.yml
# edit vault.yml: ansible_become_pass + tailscale OAuth creds
./scripts/vault.sh encrypt inventory/group_vars/vault.yml
```

Add your hosts to `inventory/hosts` (see the examples in that file).

## Provisioning

**Fresh Hetzner box (root only on init):**

```bash
./scripts/bootstrap.sh --limit box1
```

This connects as `root`, the `create_user` role creates the `patte` user, the
system is hardened (root SSH login disabled), and the dev tools are installed —
all in one pass.

**Everything afterwards** (connects as the dev user):

```bash
./scripts/provision.sh --limit box1
./scripts/provision.sh                       # all hosts
./scripts/provision.sh --tags dev_tools      # re-run one part
```

## Per-host knobs

Set these as host vars in `inventory/hosts`:

- `ansible_user=root` — needed only for the first bootstrap of a root-only host.
- `tailscale_enabled=false` — skip Tailscale on that host.

## Notes / decisions

- **Dev user:** `patte` (see `dev_user` in `group_vars/all.yml`).
- **Secrets:** ansible-vault; the password comes from `ANSIBLE_VAULT_PASSWORD`.
- **Tailscale** joins via an OAuth client that mints a tagged, preauthorized key
  per host (copied verbatim from the reference setup).
- Dropped from the reference `system_setup`: Grafana Alloy monitoring and the
  extra (jonas) SSH key — not relevant here.
- **podman** is installed rootless: linger is enabled for the dev user and the
  user `podman.socket` is started, so agent containers keep running after logout.
```
