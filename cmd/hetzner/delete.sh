#!/usr/bin/env bash
# Delete a Hetzner Cloud server by name (or numeric id).
#
# Usage: delete.sh NAME_OR_ID
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

ARG="${1:?usage: delete.sh NAME_OR_ID}"

if [[ "$ARG" =~ ^[0-9]+$ ]]; then
  id="$ARG"
else
  id="$(server_id_by_name "$ARG")"
fi

[[ -n "${id:-}" ]] || { echo "server '$ARG' not found" >&2; exit 0; }

echo "deleting server id $id ..." >&2
hapi DELETE "servers/$id" >/dev/null
echo "deleted $ARG (id $id)" >&2
