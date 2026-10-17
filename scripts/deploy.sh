#!/usr/bin/env bash
# Deploy the whole environment: what-if, confirm, deploy, print outputs. Idempotent.
# Usage: scripts/deploy.sh [env] [--yes]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh

YES=false
for a in "$@"; do
  case "$a" in
    --yes) YES=true ;;
    -*) echo "unknown flag $a" >&2; exit 2 ;;
    *) AEI_ENV="$a" ;;
  esac
done
export AEI_ENV
aei_require_login

# Secrets: reuse what the vault already holds so a second run changes nothing; generate otherwise.
# Alphanumeric only, so the password can sit inside DATABASE_URL without URL encoding.
gen() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }
VAULT="$(aei_vault_name || true)"
DB_PASSWORD=""; API_KEY=""
if [[ -n "$VAULT" ]]; then
  DB_PASSWORD="$(az keyvault secret show --vault-name "$VAULT" -n db-password --query value -o tsv 2>/dev/null || true)"
  API_KEY="$(az keyvault secret show --vault-name "$VAULT" -n api-key --query value -o tsv 2>/dev/null || true)"
fi
export AEI_DB_PASSWORD="${DB_PASSWORD:-$(gen 32)}"
export AEI_API_KEY="${API_KEY:-$(gen 40)}"

DEPLOYMENT="aei-$AEI_ENV"
ARGS=(-g "$AEI_RESOURCE_GROUP" -n "$DEPLOYMENT" --template-file infra/main.bicep
      --parameters infra/main.bicepparam --parameters env="$AEI_ENV")

echo "== Subscription: $(az account show --query name -o tsv) | group: $AEI_RESOURCE_GROUP | env: $AEI_ENV"
az bicep build --file infra/main.bicep --stdout >/dev/null
az deployment group what-if "${ARGS[@]}" --result-format ResourceIdOnly

if [[ "$YES" != true ]]; then
  [[ -t 0 ]] || { echo "No terminal to confirm on. Re-run with --yes to deploy." >&2; exit 1; }
  read -r -p "Deploy these changes? [y/N] " ok
  [[ "$ok" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

az deployment group create "${ARGS[@]}" -o none
echo "== Outputs"
az deployment group show -g "$AEI_RESOURCE_GROUP" -n "$DEPLOYMENT" \
  --query "properties.outputs.{apiUrl:apiUrl.value,staticWebAppUrl:staticWebAppUrl.value,postgresHost:postgresHost.value,keyVaultName:keyVaultName.value,webAppName:webAppName.value}" -o table

if ! az keyvault secret show --vault-name "$(aei_outputs keyVaultName)" -n anthropic-api-key >/dev/null 2>&1; then
  echo
  echo "NOTE: the Anthropic key is not set yet. Run: scripts/set_anthropic_key.sh"
fi
