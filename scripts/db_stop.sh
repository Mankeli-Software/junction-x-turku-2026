#!/usr/bin/env bash
# Stop (or start with 'start') the Postgres server between work sessions. Azure restarts a stopped
# server by itself after 7 days.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh
aei_require_login
ACTION="${1:-stop}"
SERVER="$(az postgres flexible-server list -g "$AEI_RESOURCE_GROUP" \
  --query "[?tags.project=='aei' && tags.env=='$AEI_ENV'].name | [0]" -o tsv)"
[[ -n "$SERVER" ]] || { echo "No Postgres server found." >&2; exit 1; }
az postgres flexible-server "$ACTION" -g "$AEI_RESOURCE_GROUP" -n "$SERVER"
