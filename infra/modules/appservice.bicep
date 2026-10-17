param planName string
param siteName string
param location string
param tags object
param keyVaultName string
param keyVaultUri string
param corsOrigins string
param appInsightsConnectionString string
param anthropicModel string
param agentEffort string
param asOfDefault string

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: { reserved: true }
}

func kvRef(uri string, secret string) string => '@Microsoft.KeyVault(SecretUri=${uri}secrets/${secret}/)'

resource site 'Microsoft.Web/sites@2023-12-01' = {
  name: siteName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.12'
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      healthCheckPath: '/healthz'
      appCommandLine: 'gunicorn -k uvicorn.workers.UvicornWorker -w 2 -t 0 app.main:app --bind 0.0.0.0:8000'
      appSettings: [
        { name: 'WEBSITES_PORT', value: '8000' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'DATABASE_URL', value: kvRef(keyVaultUri, 'database-url') }
        { name: 'API_KEY', value: kvRef(keyVaultUri, 'api-key') }
        { name: 'ANTHROPIC_API_KEY', value: kvRef(keyVaultUri, 'anthropic-api-key') }
        { name: 'ANTHROPIC_MODEL', value: anthropicModel }
        { name: 'AGENT_EFFORT', value: agentEffort }
        { name: 'CORS_ORIGINS', value: corsOrigins }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'AS_OF_DEFAULT', value: asOfDefault }
        // One instance only; the scheduler is guarded by a Postgres advisory lock anyway.
        { name: 'SCHEDULER_ENABLED', value: 'true' }
      ]
    }
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Key Vault Secrets User
var kvSecretsUserRole = '4633458b-17de-40ea-a5d5-b5d6d9ba7ee5'

resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, site.id, kvSecretsUserRole)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRole)
    principalId: site.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output name string = site.name
output hostname string = site.properties.defaultHostName
output principalId string = site.identity.principalId
