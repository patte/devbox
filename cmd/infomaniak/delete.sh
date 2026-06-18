#!/usr/bin/env bash
# Delete an Infomaniak Public Cloud server by name (or id).
#
# Usage: delete.sh NAME_OR_ID
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

ARG="${1:?usage: delete.sh NAME_OR_ID}"

id="$(server_id_by_name "$ARG")"
[[ -n "$id" ]] || { echo "server '$ARG' not found" >&2; exit 0; }

echo "deleting server '$ARG' (id $id) ..." >&2
os server delete --wait "$id"
echo "deleted $ARG (id $id)" >&2
