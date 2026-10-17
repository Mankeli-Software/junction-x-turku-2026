# AMRight on Azure: runbook

Implements the infrastructure part of issue #3. Everything is Bicep (`infra/`) plus helper scripts (`scripts/`).

| What | Where |
| --- | --- |
| Subscription | `4075b785-90d2-4c43-b648-a821099f0ec2` (New Azure Benefit) |
| Resource group | `rg-junctionturku` (already existed, so Bicep deploys *into* it at resource-group scope) |
| Region | Norway East; the Static Web App is in West Europe (not offered in Norway East) |
| LLM | Claude API, not an Azure resource. Key in Key Vault, billed by Anthropic |

Resources are named `aei-demo-<type>`; globally unique ones (Key Vault, Postgres, Web App) get a 5-character suffix from the resource group id. Everything is tagged `project=aei`, `env=demo`, `owner=junction-turku`.

## Deploy

```bash
az login                      # as the account that owns the subscription
scripts/deploy.sh demo        # what-if, asks for confirmation, deploys, prints URLs
scripts/set_anthropic_key.sh  # once: stores the Anthropic key in Key Vault, restarts the Web App
```

`deploy.sh` generates the Postgres password and the API key on the first run and stores them only in Key Vault. Later runs reuse them, so a second run changes nothing. Use `--yes` to skip the prompt.

Deploy requires `Owner` (or Contributor plus User Access Administrator) on the resource group, because Bicep creates role assignments.

## Load data and use the database

```bash
scripts/db_allow_my_ip.sh                 # firewall rule for your current IP
VAULT=$(az keyvault list -g rg-junctionturku --query '[0].name' -o tsv)
az keyvault secret show --vault-name $VAULT -n database-url --query value -o tsv   # the DSN
```

The loader and the Alembic migrations belong to the data issues (#5, #11); they take that DSN.

## Deploy the code

CI does it on push to `main`; to do it by hand:

```bash
# backend: zip backend/app plus a requirements.txt, then
az webapp deploy -g rg-junctionturku -n <webAppName> --src-path backend.zip --type zip --clean true
# frontend: flutter build web --release --dart-define=API_BASE=https://<api host>, then upload build/web
```

CI signs in with OIDC (no stored secret). Once per repository: `scripts/bootstrap_oidc.sh`, then set the three variables it prints (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`).

## Rotate a secret

- Anthropic key: run `scripts/set_anthropic_key.sh` again.
- API key or DB password: set a new value with `az keyvault secret set`, update the Postgres admin password to match (`az postgres flexible-server update --admin-password`), update `database-url`, restart the Web App.

## Logs

Application Insights `aei-demo-ai` (Logs, Live metrics) or `az webapp log tail -g rg-junctionturku -n <webAppName>`. The Web App's configuration page shows whether each Key Vault reference is "Resolved".

## Stop and tear down

```bash
scripts/db_stop.sh            # stop Postgres between sessions (`db_stop.sh start` to resume)
scripts/teardown.sh demo      # deletes every resource tagged project=aei, env=demo, then purges the vault
```

`teardown.sh` never deletes the resource group. There is no Azure budget alert (the environment is short-lived); the Anthropic spend limit of 100 USD per month is set in the Anthropic Console, which Azure cannot see.

## Known limits

App Service plan: Basic B3 (4 vCPU, 7 GB, about $52 a month at list price in Norway East; B1 was $13, B2 $26). Billed by the hour, so scale it down with `sku` in `infra/modules/appservice.bicep` when the demo is over.

No login (the API key only protects non-browser clients), public endpoints, one App Service instance, Postgres open to Azure services plus listed IPs, synthetic data only. Real data would need private networking and authentication.
