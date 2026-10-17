# Shared settings for the scripts in this folder. Source it, do not run it.
# Override any of these through the environment.
AEI_SUBSCRIPTION="${AEI_SUBSCRIPTION:-4075b785-90d2-4c43-b648-a821099f0ec2}"
AEI_RESOURCE_GROUP="${AEI_RESOURCE_GROUP:-rg-junctionturku}"
AEI_ENV="${AEI_ENV:-demo}"

aei_require_login() {
  command -v az >/dev/null || { echo "az CLI not found" >&2; exit 1; }
  az account set --subscription "$AEI_SUBSCRIPTION" 2>/dev/null \
    || { echo "Cannot select subscription $AEI_SUBSCRIPTION. Run: az login" >&2; exit 1; }
}

# Name of the Key Vault this project created (tagged project=aei, env=<env>), or empty.
aei_vault_name() {
  az keyvault list -g "$AEI_RESOURCE_GROUP" \
    --query "[?tags.project=='aei' && tags.env=='$AEI_ENV'].name | [0]" -o tsv 2>/dev/null
}

aei_outputs() { # <output name>
  az deployment group show -g "$AEI_RESOURCE_GROUP" -n "aei-$AEI_ENV" \
    --query "properties.outputs.$1.value" -o tsv
}
