#!/usr/bin/env bash
# Add a Postgres firewall rule for this machine's public IP (or the IP given as $1).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh
aei_require_login

IP="${1:-$(curl -fsS https://api.ipify.org)}"
SERVER="$(az postgres flexible-server list -g "$AEI_RESOURCE_GROUP" \
  --query "[?tags.project=='aei' && tags.env=='$AEI_ENV'].name | [0]" -o tsv)"
[[ -n "$SERVER" ]] || { echo "No Postgres server found." >&2; exit 1; }

RULE="dev-$(printf '%s' "$(whoami)" | tr -c 'A-Za-z0-9' '-' | head -c 20)"
# For firewall-rule commands, --name is the rule and --server-name is the server.
az postgres flexible-server firewall-rule create -g "$AEI_RESOURCE_GROUP" --server-name "$SERVER" \
  --name "$RULE" --start-ip-address "$IP" --end-ip-address "$IP" -o none
echo "Allowed $IP on $SERVER as rule $RULE."
