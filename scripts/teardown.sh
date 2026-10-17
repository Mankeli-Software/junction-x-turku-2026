#!/usr/bin/env bash
# Delete every resource tagged project=aei, env=<env> in the resource group, then purge the
# soft-deleted Key Vault. The resource group itself is NOT deleted: this project did not create it.
# Usage: scripts/teardown.sh [env] [--yes]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh
YES=false
for a in "$@"; do
  case "$a" in --yes) YES=true ;; -*) echo "unknown flag $a" >&2; exit 2 ;; *) AEI_ENV="$a" ;; esac
done
aei_require_login

QUERY="[?tags.project=='aei' && tags.env=='$AEI_ENV']"
az resource list -g "$AEI_RESOURCE_GROUP" --query "$QUERY.{name:name,type:type}" -o table
IDS="$(az resource list -g "$AEI_RESOURCE_GROUP" --query "$QUERY.id" -o tsv)"
[[ -n "$IDS" ]] || { echo "Nothing to delete."; exit 0; }

if [[ "$YES" != true ]]; then
  read -r -p "Delete the resources above from $AEI_RESOURCE_GROUP? Type the env name to confirm: " c
  [[ "$c" == "$AEI_ENV" ]] || { echo "Aborted."; exit 1; }
fi

VAULT="$(aei_vault_name || true)"
VAULT_LOC="$(az keyvault show -n "${VAULT:-none}" --query location -o tsv 2>/dev/null || true)"

# Dependencies (web app before plan, and so on) can make a first pass fail; retry a few times.
for attempt in 1 2 3 4; do
  IDS="$(az resource list -g "$AEI_RESOURCE_GROUP" --query "$QUERY.id" -o tsv)"
  [[ -z "$IDS" ]] && break
  echo "$IDS" | xargs -I{} az resource delete --ids {} --verbose >/dev/null 2>&1 || true
done
LEFT="$(az resource list -g "$AEI_RESOURCE_GROUP" --query "$QUERY.name" -o tsv)"
[[ -z "$LEFT" ]] || { echo "Still present: $LEFT" >&2; exit 1; }

if [[ -n "$VAULT" ]]; then
  az keyvault purge --name "$VAULT" --location "$VAULT_LOC" && echo "Purged Key Vault $VAULT."
fi
az role assignment list -g "$AEI_RESOURCE_GROUP" --query "[?principalName==''].id" -o tsv \
  | xargs -r -I{} az role assignment delete --ids {} >/dev/null 2>&1 || true
echo "Done."
