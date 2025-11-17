# Managed Identity Setup Guide

This guide explains how to configure your App Services to connect to PostgreSQL and Redis using Azure Managed Identity (passwordless authentication).

## Overview

**Benefits of Managed Identity:**
- ✅ No passwords to manage or rotate
- ✅ Credentials never exposed in code or configuration
- ✅ Automatic credential rotation by Azure
- ✅ Enhanced security with Azure AD (Entra ID) authentication
- ✅ Fine-grained access control with RBAC

## Quick Start: iris-claps Service

The `iris-claps` service is already configured to access PostgreSQL! Here's what was set up:

1. **App Service** (`iris-iris-claps-dev-001`) created with Managed Identity
2. **Azure AD Administrator** role granted on PostgreSQL server
3. **Connection string** available for your application code

See the [Using Managed Identity in Your App](#4-update-application-code) section below for code examples.

## Architecture

```
┌─────────────────┐
│   App Service   │
│  (Managed ID)   │
└────────┬────────┘
         │
         │ Azure AD Token
         │
    ┌────▼─────────────────┐
    │                      │
    │  PostgreSQL Server   │
    │  (Azure AD Auth)     │
    │                      │
    └──────────────────────┘
```

## PostgreSQL Setup with Managed Identity

### 1. Enable Managed Identity on App Service

If your App Service doesn't have a Managed Identity yet:

```bash
# Enable system-assigned managed identity
az webapp identity assign \
  --name <your-app-service-name> \
  --resource-group iot-dev

# Get the principal ID (you'll need this)
APP_PRINCIPAL_ID=$(az webapp identity show \
  --name <your-app-service-name> \
  --resource-group iot-dev \
  --query principalId -o tsv)

echo "App Service Principal ID: $APP_PRINCIPAL_ID"
```

### 2. Verify Configured Access

**For iris-claps and iot-ingestion services**: Access is already configured via Terraform! You can verify:

```bash
cd /Users/naveennegi/projects/apcoa/iris-terraform-databases/dev
terraform output postgresql_ad_admins_configured
```

This will show:
```json
{
  "primary-iris_claps": {
    "principal_name": "iris-iris-claps-dev-001",
    "principal_type": "ServicePrincipal",
    "server_name": "iris-postgres-dev"
  },
  "primary-iot_ingestion": {
    "principal_name": "iris-iot-ingestion-dev-001",
    "principal_type": "ServicePrincipal",
    "server_name": "iris-postgres-dev"
  }
}
```

### 2b. Grant Database Access to NEW Services (Manual Step)

**Note**: For iris-claps and iot-ingestion, skip to step 3 (database permissions).

For NEW app services not yet configured in Terraform, you need to grant Azure AD admin access:

#### Option A: Using Azure CLI (Recommended)

```bash
# Get PostgreSQL server details
PG_SERVER_NAME="iris-postgres-dev"
PG_FQDN="${PG_SERVER_NAME}.postgres.database.azure.com"

# Login to Azure
az login

# Get an access token for PostgreSQL
TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)

# Connect to PostgreSQL using Azure AD
PGPASSWORD=$TOKEN psql \
  "host=${PG_FQDN} user=$(az account show --query user.name -o tsv) dbname=postgres sslmode=require"
```

Once connected, run these SQL commands:

```sql
-- Create a role for your App Service Managed Identity
-- Replace <app-service-name> with your actual App Service name
SET aad_validate_oids_in_tenant = off;

CREATE ROLE "my-app-service" WITH LOGIN;
GRANT CONNECT ON DATABASE "iris-app" TO "my-app-service";

-- Grant permissions on the iris-app database
\c iris-app

GRANT USAGE ON SCHEMA public TO "my-app-service";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "my-app-service";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "my-app-service";

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "my-app-service";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO "my-app-service";

-- Repeat for other databases if needed
\c iris-analytics
GRANT USAGE ON SCHEMA public TO "my-app-service";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "my-app-service";
```

#### Option B: Using Terraform (Add to locals.tf)

You can also manage database permissions via Terraform:

```hcl
# Add this to dev/locals.tf
postgres_database_roles = {
  app_service_role = {
    database_name = "iris-app"
    role_name     = "my-app-service"  # Your App Service name
    permissions   = ["SELECT", "INSERT", "UPDATE", "DELETE"]
  }
}
```

### 3. Get Connection String from Terraform Outputs

Get the connection string for your service:

```bash
cd /Users/naveennegi/projects/apcoa/iris-terraform-databases/dev
terraform output -json postgresql_connection_strings
```

Output:
```json
{
  "primary": {
    "iris-analytics": "Host=iris-postgres-dev.postgres.database.azure.com;Database=iris-analytics;SSL Mode=Require",
    "iris-app": "Host=iris-postgres-dev.postgres.database.azure.com;Database=iris-app;SSL Mode=Require"
  }
}
```

### 3b. Configure App Service Environment Variable

You can add this to your `iris-app-service-plugin` Terraform configuration, or set it manually:

```hcl
# In iris-app-service-plugin/dev/locals.tf - iris-claps app_settings:
app_settings = {
  # ... existing settings ...

  # PostgreSQL connection (no password!)
  "ConnectionStrings__PostgreSQL" = "Host=iris-postgres-dev.postgres.database.azure.com;Database=iris-app;SSL Mode=Require"

  # Redis connection (access key from outputs)
  "ConnectionStrings__Redis" = "${data.terraform_remote_state.databases.outputs.redis_connection_strings["primary"]}"
}
```

### 4. Update Application Code

Your application needs to request Azure AD tokens for PostgreSQL authentication.

#### .NET Example

```csharp
using Azure.Identity;
using Npgsql;

var connectionString =
  "Host=iris-postgres-dev.postgres.database.azure.com;" +
  "Database=iris-app;" +
  "Username=my-app-service;" +
  "SSL Mode=Require;";

var dataSourceBuilder = new NpgsqlDataSourceBuilder(connectionString);

// Use DefaultAzureCredential to get token
dataSourceBuilder.UsePeriodicPasswordProvider(async (_, ct) =>
{
    var credential = new DefaultAzureCredential();
    var token = await credential.GetTokenAsync(
        new TokenRequestContext(["https://ossrdbms-aad.database.windows.net/.default"]),
        ct);
    return token.Token;
}, TimeSpan.FromHours(1), TimeSpan.FromSeconds(10));

await using var dataSource = dataSourceBuilder.Build();
await using var connection = await dataSource.OpenConnectionAsync();
```

#### Python Example

```python
from azure.identity import DefaultAzureCredential
import psycopg2

# Get Azure AD token
credential = DefaultAzureCredential()
token = credential.get_token("https://ossrdbms-aad.database.windows.net/.default")

# Connect using token as password
conn = psycopg2.connect(
    host="iris-postgres-dev.postgres.database.azure.com",
    database="iris-app",
    user="my-app-service@iris-postgres-dev",  # format: role@servername
    password=token.token,
    sslmode="require"
)
```

#### Node.js Example

```javascript
const { DefaultAzureCredential } = require("@azure/identity");
const { Client } = require("pg");

async function connectToPostgres() {
  // Get Azure AD token
  const credential = new DefaultAzureCredential();
  const token = await credential.getToken(
    "https://ossrdbms-aad.database.windows.net/.default"
  );

  // Create PostgreSQL client
  const client = new Client({
    host: "iris-postgres-dev.postgres.database.azure.com",
    database: "iris-app",
    user: "my-app-service",
    password: token.token,
    port: 5432,
    ssl: true,
  });

  await client.connect();
  return client;
}
```

## Redis Setup with Managed Identity

Redis can also use Managed Identity for authentication (Azure Cache for Redis Enterprise tier) or access keys.

### Option 1: Using Managed Identity (Enterprise/Premium tier)

For Enterprise tier Redis:

```bash
# Assign Managed Identity role
az redis access-policy-assignment create \
  --name <your-app-service-name> \
  --resource-group iot-dev \
  --redis-name iris-redis-dev \
  --object-id $APP_PRINCIPAL_ID \
  --object-id-alias <your-app-service-name> \
  --access-policy-name "Data Contributor"
```

### Option 2: Using Access Keys (Basic/Standard tier)

For Basic/Standard tier (current setup):

Retrieve the Redis access key from Terraform outputs:

```bash
cd dev
terraform output -json redis_cache_primary_access_keys
```

Configure in App Service (using Key Vault reference):

```bash
# Store in Key Vault
az keyvault secret set \
  --vault-name <your-keyvault> \
  --name "RedisAccessKey" \
  --value "<redis-access-key>"

# Reference in App Service
az webapp config appsettings set \
  --resource-group iot-dev \
  --name <your-app-service-name> \
  --settings REDIS_CONNECTION_STRING="@Microsoft.KeyVault(SecretUri=https://<your-keyvault>.vault.azure.net/secrets/RedisAccessKey)"
```

## Testing the Connection

### Test PostgreSQL Connection

```bash
# Get the Terraform output for connection string
cd dev
terraform output -json postgresql_connection_strings

# Test connection from your local machine (requires Azure AD login)
az login
TOKEN=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)

PGPASSWORD=$TOKEN psql \
  "host=iris-postgres-dev.postgres.database.azure.com user=$(az account show --query user.name -o tsv) dbname=iris-app sslmode=require"
```

### Test Redis Connection

```bash
# Get Redis connection details
cd dev
terraform output -json redis_connection_strings

# Test with redis-cli (if installed)
redis-cli -h iris-redis-dev.redis.cache.windows.net \
  -p 6380 \
  -a <access-key> \
  --tls \
  PING
```

## Troubleshooting

### PostgreSQL Connection Issues

**Error: "password authentication failed"**
- Ensure Azure AD authentication is enabled
- Verify the role was created correctly in PostgreSQL
- Check that the App Service Managed Identity name matches the role name

**Error: "no pg_hba.conf entry"**
- Verify firewall rules allow Azure services
- Check that SSL mode is set to "require"

**Token Refresh Issues**
- Implement token refresh in your application (tokens expire after 1 hour)
- Use connection pooling with token refresh callbacks

### Redis Connection Issues

**Error: "Connection timeout"**
- Verify firewall rules allow your IP/App Service
- Check that SSL port (6380) is being used
- Ensure TLS is enabled in your client

**Error: "Authentication failed"**
- Verify the access key is correct
- Check if using Key Vault reference that the App Service has permission

## Security Best Practices

1. **Use Private Endpoints** for production:
   - Configure VNet integration for App Service
   - Use private endpoints for PostgreSQL and Redis
   - Disable public network access

2. **Principle of Least Privilege**:
   - Grant only necessary database permissions
   - Use separate Managed Identities for different apps
   - Create read-only roles for analytics services

3. **Monitoring and Auditing**:
   - Enable diagnostic logs on PostgreSQL
   - Monitor failed authentication attempts
   - Set up alerts for unusual access patterns

4. **Network Security**:
   - Use NSGs to restrict traffic
   - Enable Azure DDoS Protection
   - Use Azure Firewall for outbound traffic

## Additional Resources

- [Azure Database for PostgreSQL - Azure AD authentication](https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-azure-ad-authentication)
- [Managed Identity for App Service](https://learn.microsoft.com/azure/app-service/overview-managed-identity)
- [Azure Cache for Redis - Managed Identity](https://learn.microsoft.com/azure/azure-cache-for-redis/cache-azure-active-directory-for-authentication)
