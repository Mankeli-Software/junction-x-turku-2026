#!/usr/bin/env bash
# Store the Anthropic API key in Key Vault as 'anthropic-api-key'. The key is read from
# $ANTHROPIC_API_KEY or a hidden prompt and is never echoed or written to disk.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh
aei_require_login

VAULT="$(aei_vault_name)"
[[ -n "$VAULT" ]] || { echo "No Key Vault found. Run scripts/deploy.sh first." >&2; exit 1; }

KEY="${ANTHROPIC_API_KEY:-}"
if [[ -z "$KEY" ]]; then
  read -r -s -p "Anthropic API key: " KEY; echo
fi
[[ -n "$KEY" ]] || { echo "Empty key" >&2; exit 1; }

# Pass the value through a file descriptor so it never appears in the process list.
# printf, not a here-string: `<<<` appends a newline, which ends up in the secret and makes the key
# unusable as an HTTP header ("connection error" from the SDK).
printf '%s' "$KEY" | az keyvault secret set --vault-name "$VAULT" -n anthropic-api-key \
  --file /dev/stdin --encoding utf-8 --query id -o tsv >/dev/null
echo "Stored anthropic-api-key in $VAULT."

# Key Vault references are cached for up to a day; restart to pick the value up now.
WEBAPP="$(az webapp list -g "$AEI_RESOURCE_GROUP" --query "[?tags.project=='aei' && tags.env=='$AEI_ENV'].name | [0]" -o tsv)"
if [[ -n "$WEBAPP" ]]; then
  az webapp restart -g "$AEI_RESOURCE_GROUP" -n "$WEBAPP" && echo "Restarted $WEBAPP."
fi
