#!/usr/bin/env bash
# Connectivity check against all coding hosts.
#
# Usage:
#   scripts/ping.sh                 # ping as the dev user
#   scripts/ping.sh -u root         # ping a not-yet-bootstrapped host as root
set -euo pipefail
cd "$(dirname "$0")/.."

exec ansible coding -m ping "$@"
