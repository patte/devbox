#!/usr/bin/env bash
# List Exoscale Compute instances in the configured zone ($EXOSCALE_ZONE,
# default ch-dk-2). Pass `all` as the first arg to list every zone.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

zone_flag=(--zone "$EXOSCALE_ZONE")
[[ "${1:-}" == "all" ]] && zone_flag=()

exo compute instance list "${zone_flag[@]}" -O json \
  | jq -r '.[] | [ .id, .name, .zone, .type, (.ip_address // "-"), .state ] | @tsv' \
  | { printf "ID\tNAME\tZONE\tTYPE\tIPv4\tSTATE\n"; cat; } \
  | column -t -s $'\t'
