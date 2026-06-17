# AGENTS.md

Notes for AI agents working in this repo. Keep short; append things future-you would want to know.

## Secrets
- `ansible/secrets.txt` (gitignored) holds `ANSIBLE_VAULT_PASSWORD` and `HETZNER_API_KEY`.
  Source it in each shell; **never echo the values** into output/transcript.
- Encrypted vault: `ansible/inventory/group_vars/all/vault.yml`. Edit via `ansible/scripts/vault.sh`.

## Connecting to test boxes (SSH key)
- The operator's real key (`github.com/patte.keys`) is a Secretive / Touch-ID key — unusable headless.
- So use a throwaway key for the session:
  1. `ssh-keygen -t ed25519 -N "" -f ~/.ssh/coder_test_ed25519`
  2. register on Hetzner: `HCLOUD_TOKEN=$HETZNER_API_KEY ansible/.. cmd/hetzner/ensure-key.sh coder-test ~/.ssh/coder_test_ed25519.pub`
  3. inject into the dev user for the run via extra-vars file `/tmp/coder-extra.yml`:
     `additional_ssh_keys: [{key: "<pubkey>", comment: coder-test}]`, passed with `-e @/tmp/coder-extra.yml`
     (only needed on `bootstrap.sh`; create_user + system_setup install it).
- SSH flags to avoid recycled-IP host-key errors:
  `-o IdentitiesOnly=yes -o IdentityAgent=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no`
- **Clean up at end of session:** delete `~/.ssh/coder_test_ed25519*`, remove the key from Hetzner, and from the box (or just delete the box).

## Hetzner (cmd/hetzner/)
- Attach SSH keys by **id**, not name (attach-by-name silently does not inject the key).
- IPs are recycled across creates → stale `~/.ssh/known_hosts` entries.

## Provisioning flow
- `scripts/bootstrap.sh` (as root, once) creates the dev user; then `scripts/provision.sh` (as the dev user) for everything, and every future run.
- **Tailnet lock is ON**: a freshly joined node has no connectivity/DNS until the operator signs it in the Tailscale admin console. The tailscale role polls until that happens — ask the operator to sign when a run is waiting there.
- After provisioning, UFW allows SSH **only over tailscale0**; public SSH is closed. Reach the box via its tailscale name afterwards (this Mac is on the tailnet; CLI at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`). So set `ansible_host` to the tailscale name/IP for re-runs.
- Nodes get `tag:coder`. The tailnet ACL must grant the operator's devices access to it, else the node isn't even a visible peer (`tailscale ping` → "no matching peer"). Needs a grant like `dst: ["tag:coder:22"]` from `autogroup:member` (operator's devices). Without it the locked-down box is unreachable.

## Ubuntu 26.04 gotchas
- sudo-rs: ansible `become` can't read its password prompt → the dev user gets passwordless sudo.
- `apt-key` is gone → add repos with `signed-by` keyrings.
- Load nvm/PATH where non-interactive shells see it (`.bashrc` top, `.zshenv`) so `ssh host 'node …'` works.
- Default shell is zsh + starship (no plugin framework).
