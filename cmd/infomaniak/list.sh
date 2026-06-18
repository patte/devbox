#!/usr/bin/env bash
# List Infomaniak Public Cloud servers in the project.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

os server list -f json \
  | jq -r '.[] | [
      .ID,
      .Name,
      (.Flavor // "-"),
      .Status,
      ([.Networks[]?[]?] | map(select(test("^[0-9]+\\.")))[0] // "-")
    ] | @tsv' \
  | { printf "ID\tNAME\tFLAVOR\tSTATUS\tIPv4\n"; cat; } \
  | column -t -s $'\t'
