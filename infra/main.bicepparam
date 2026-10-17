using 'main.bicep'

param env = 'demo'
param location = 'norwayeast'
param swaLocation = 'westeurope'
param owner = 'junction-turku'
param anthropicModel = 'claude-sonnet-5-5'
param agentEffort = 'medium'
param adminObjectId = '9434d4fc-d094-49d7-8036-b987e0270cd4'

// Secrets come from the environment, set by scripts/deploy.sh. Never write them here.
param postgresAdminPassword = readEnvironmentVariable('AEI_DB_PASSWORD')
param apiKey = readEnvironmentVariable('AEI_API_KEY')
