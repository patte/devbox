#!/usr/bin/env bash
# List Hetzner Cloud servers in the project.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

hapi GET "servers?per_page=100" \
  | jq -r '.servers[] | "\(.id)\t\(.name)\t\(.server_type.name)\t\(.status)\t\(.public_net.ipv4.ip // "-")"' \
  | { printf "ID\tNAME\tTYPE\tSTATUS\tIPv4\n"; cat; } \
  | column -t -s $'\t'
