#!/usr/bin/env bash
# Delete an Exoscale Compute instance by name (or id), scoped to $EXOSCALE_ZONE
# (default ch-dk-2) so it can never act on a box in another zone.
#
# Usage: delete.sh NAME_OR_ID
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

ARG="${1:?usage: delete.sh NAME_OR_ID}"

# Resolve to an id within our zone so we only ever delete a box we can see here.
id="$(instance_id_by_name "$ARG")"
if [[ -z "$id" ]]; then
  # Maybe an id was passed directly; verify it exists in this zone first.
  if exo compute instance show "$ARG" --zone "$EXOSCALE_ZONE" >/dev/null 2>&1; then
    id="$ARG"
  else
    echo "instance '$ARG' not found in zone $EXOSCALE_ZONE" >&2
    exit 0
  fi
fi

echo "deleting instance '$ARG' (id $id) in $EXOSCALE_ZONE ..." >&2
exo compute instance delete --zone "$EXOSCALE_ZONE" --force "$id"
echo "deleted $ARG (id $id)" >&2
