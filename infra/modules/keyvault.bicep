param name string
param location string
param tags object
@description('Object ID of the person who administers the vault.')
param adminObjectId string
@secure()
param dbPassword string
@secure()
param databaseUrl string
@secure()
param apiKey string

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Purge protection stays off so teardown.sh can purge and the name can be reused.
    enablePurgeProtection: null
  }
}

// Key Vault Administrator
var kvAdminRole = '00482a5a-887f-4fb3-b363-3b7fe8e74483'

resource adminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, adminObjectId, kvAdminRole)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvAdminRole)
    principalId: adminObjectId
    principalType: 'User'
  }
}

resource sDbPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'db-password'
  properties: { value: dbPassword }
}

resource sDatabaseUrl 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'database-url'
  properties: { value: databaseUrl }
}

resource sApiKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'api-key'
  properties: { value: apiKey }
}

// 'anthropic-api-key' is deliberately not created here: scripts/set_anthropic_key.sh sets it.

output id string = vault.id
output name string = vault.name
output uri string = vault.properties.vaultUri
