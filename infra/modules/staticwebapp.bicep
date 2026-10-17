param name string
@description('Static Web Apps is only available in a few regions; West Europe is the nearest.')
param location string
param tags object

// No repository link: the GitHub Action deploys with a token fetched through OIDC.
resource swa 'Microsoft.Web/staticSites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {}
}

output name string = swa.name
output hostname string = swa.properties.defaultHostname
