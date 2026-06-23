# AGENTS.md

Notes for AI agents working in this repo. Keep short; append things future-you would want to know.

## Secrets
- `ansible/secrets.txt` (gitignored) holds `ANSIBLE_VAULT_PASSWORD` and `HETZNER_API_KEY`.
  `source` it into the environment (`set -a; source ansible/secrets.txt; set +a`) and
  reference the variables by name (`$HETZNER_API_KEY`, etc.). **Never** `Read`/`cat` the
  file, inline the literal values into a command, or `echo` them — that leaks the plaintext
  into the transcript. (`export HCLOUD_TOKEN="$HETZNER_API_KEY"` for the cmd/hetzner scripts.)
- Encrypted vault: `ansible/inventory/group_vars/all/vault.yml`. Edit via `ansible/scripts/vault.sh`.

## Connecting to test boxes (SSH key)
- The operator's real key (`github.com/patte.keys`) is a Secretive / Touch-ID key — unusable headless.
- So use a throwaway key for the session:
  1. `ssh-keygen -t ed25519 -N "" -f ~/.ssh/devbox_test_ed25519`
  2. register on Hetzner (from repo root): `HCLOUD_TOKEN=$HETZNER_API_KEY cmd/hetzner/ensure-key.sh devbox-test ~/.ssh/devbox_test_ed25519.pub`
  3. inject into the dev user for the run via extra-vars file `/tmp/devbox-extra.yml`:
     `additional_ssh_keys: [{key: "<pubkey>", comment: devbox-test}]`, passed with `-e @/tmp/devbox-extra.yml`
     (only needed on `bootstrap.sh`; create_user + system_setup install it).
- Test host lives in `ansible/inventory/hosts.test` (sets the key + recycled-IP SSH flags). Use `-i inventory/hosts.test`. On the first run point `ansible_host` at the public IP; after the SSH lockdown switch it to the box's tailscale IP/name to keep iterating.
- SSH flags to avoid recycled-IP host-key errors:
  `-o IdentitiesOnly=yes -o IdentityAgent=none -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no`
- **Clean up at end of session:** delete `~/.ssh/devbox_test_ed25519*`, remove the key from Hetzner, and from the box (or just delete the box).

### Persistent key (do NOT delete)
Instead of creating a new key you can just use ~/.ssh/id_ed25519.pub It's without passkey, so it can be used headless. Add it to the hoster if it's not there already. Call it "patte@air.local". Don't delete it. Neither from this machine, nor from the hoster.


## Hetzner (cmd/hetzner/)
- Attach SSH keys by **id**, not name (attach-by-name silently does not inject the key).
- IPs are recycled across creates → stale `~/.ssh/known_hosts` entries.

## Provisioning flow
- `scripts/bootstrap.sh` (as root, once) creates the dev user; then `scripts/provision.sh` (as the dev user) for everything, and every future run.
- **Tailnet lock is ON**: a freshly joined node has no connectivity/DNS until the operator signs it in the Tailscale admin console. The tailscale role polls until that happens — ask the operator to sign when a run is waiting there.
- After provisioning, UFW allows SSH **only over tailscale0**; public SSH is closed. Reach the box via its tailscale name afterwards (this Mac is on the tailnet; CLI at `/Applications/Tailscale.app/Contents/MacOS/Tailscale`). So set `ansible_host` to the tailscale name/IP for re-runs.
- Nodes get `tag:devbox`. The tailnet ACL must grant the operator's devices access to it, else the node isn't even a visible peer (`tailscale ping` → "no matching peer"). Needs a grant like `dst: ["tag:devbox:22"]` from `autogroup:member` (operator's devices). Without it the locked-down box is unreachable.

## Ubuntu 26.04 gotchas
- sudo-rs: ansible `become` can't read its password prompt → the dev user gets passwordless sudo.
- `apt-key` is gone → add repos with `signed-by` keyrings.
- Load nvm/PATH where non-interactive shells see it (`.bashrc` top, `.zshenv`) so `ssh host 'node …'` works.
- Default shell is zsh + starship (no plugin framework).
