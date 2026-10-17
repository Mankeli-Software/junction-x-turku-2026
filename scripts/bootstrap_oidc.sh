#!/usr/bin/env bash
# One-time: create the app registration GitHub Actions signs in with (OIDC, no client secret),
# give it Contributor on the resource group, and print the three repository variables to set.
# Usage: scripts/bootstrap_oidc.sh [owner/repo]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/_common.sh
aei_require_login

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
NAME="aei-github-deploy"
TENANT="$(az account show --query tenantId -o tsv)"
RG_ID="/subscriptions/$AEI_SUBSCRIPTION/resourceGroups/$AEI_RESOURCE_GROUP"

APP_ID="$(az ad app list --display-name "$NAME" --query '[0].appId' -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$NAME" --query appId -o tsv)"
  az ad sp create --id "$APP_ID" -o none
fi

cred() { # <name> <subject>
  if ! az ad app federated-credential list --id "$APP_ID" --query "[?name=='$1'].name" -o tsv | grep -q .; then
    az ad app federated-credential create --id "$APP_ID" --parameters "{
      \"name\": \"$1\", \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$2\", \"audiences\": [\"api://AzureADTokenExchange\"]}" -o none
  fi
}
cred github-main "repo:$REPO:ref:refs/heads/main"
cred github-pr "repo:$REPO:pull_request"

# Contributor to deploy resources; User Access Administrator is not needed because the Bicep role
# assignments are applied by people (deploy.sh), and CI only runs what-if and code deploys.
az role assignment create --assignee "$APP_ID" --role Contributor --scope "$RG_ID" -o none 2>/dev/null || true
# Key Vault reads for the API key smoke checks are not needed; keep the scope narrow.

echo
echo "Set these repository variables (Settings > Secrets and variables > Actions > Variables):"
echo "  AZURE_CLIENT_ID=$APP_ID"
echo "  AZURE_TENANT_ID=$TENANT"
echo "  AZURE_SUBSCRIPTION_ID=$AEI_SUBSCRIPTION"
if command -v gh >/dev/null; then
  echo
  echo "Or run: gh variable set AZURE_CLIENT_ID -b $APP_ID && gh variable set AZURE_TENANT_ID -b $TENANT && gh variable set AZURE_SUBSCRIPTION_ID -b $AEI_SUBSCRIPTION"
fi
