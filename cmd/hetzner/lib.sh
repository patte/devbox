#!/usr/bin/env bash
# Shared helpers for the Hetzner Cloud API scripts.
# Requires HCLOUD_TOKEN in the environment (never pass it on the command line).
set -euo pipefail

: "${HCLOUD_TOKEN:?HCLOUD_TOKEN must be set in the environment}"
API="https://api.hetzner.cloud/v1"

# hapi METHOD PATH [JSON_BODY]
hapi() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS -X "$method" \
      -H "Authorization: Bearer $HCLOUD_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$body" "$API/$path"
  else
    curl -fsS -X "$method" \
      -H "Authorization: Bearer $HCLOUD_TOKEN" \
      "$API/$path"
  fi
}

# server_id_by_name NAME  -> prints id (empty if not found)
server_id_by_name() {
  hapi GET "servers?name=$1" | jq -r '.servers[0].id // empty'
}
