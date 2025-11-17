# App Service Database Access Configuration

This document shows which App Services have been granted access to PostgreSQL and Redis.

## Currently Configured App Services

### iris-claps
- **App Service Name**: `iris-iris-claps-dev-001`
- **PostgreSQL Access**: ✅ Azure AD Administrator on `iris-postgres-dev`
- **Redis Access**: ✅ Via access keys (retrieved from Terraform outputs)
- **Databases**: `iris-app`, `iris-analytics`
- **Authentication Method**: Managed Identity (passwordless)

### iot-ingestion
- **App Service Name**: `iris-iot-ingestion-dev-001`
- **PostgreSQL Access**: ✅ Azure AD Administrator on `iris-postgres-dev`
- **Redis Access**: ✅ Via access keys (retrieved from Terraform outputs)
- **Databases**: `iris-app`, `iris-analytics`
- **Authentication Method**: Managed Identity (passwordless)

## How It Works

### 1. Managed Identity Created
When you deploy `iris-app-service-plugin`, each App Service gets a Managed Identity (System-Assigned).

```bash
cd /Users/naveennegi/projects/apcoa/iris-app-service-plugin/dev
terraform output app_service_principal_ids
```

Output:
```json
{
  "iris-claps": "abc-123-def-456",
  "iot-ingestion": "xyz-789-ghi-012"
}
```

### 2. Database Plugin Reads Remote State
The `iris-terraform-databases` plugin reads the App Service principal IDs from remote state:

**File**: `iris-terraform-databases/dev/data.tf`
```hcl
data "terraform_remote_state" "app_services" {
  backend = "azurerm"
  config = {
    key = "iris-app-service-plugin.dev.tfstate"
  }
}
```

### 3. Azure AD Admin Roles Granted
The database plugin automatically grants Azure AD Administrator roles:

**File**: `iris-terraform-databases/dev/locals.tf`
```hcl
azure_ad_administrators = {
  iris_claps = {
    object_id      = local.app_service_identities["iris-claps"]
    principal_name = "iris-iris-claps-dev-001"
    principal_type = "ServicePrincipal"
  }
  # ... more services
}
```

### 4. App Service Connects Using Managed Identity
Your application code uses Azure SDK to authenticate:

```csharp
using Azure.Identity;
using Npgsql;

var credential = new DefaultAzureCredential();
var dataSourceBuilder = new NpgsqlDataSourceBuilder(
    "Host=iris-postgres-dev.postgres.database.azure.com;" +
    "Database=iris-app;" +
    "Username=iris-iris-claps-dev-001;" +
    "SSL Mode=Require;"
);

dataSourceBuilder.UsePeriodicPasswordProvider(async (_, ct) =>
{
    var token = await credential.GetTokenAsync(
        new TokenRequestContext(["https://ossrdbms-aad.database.windows.net/.default"]),
        ct);
    return token.Token;
}, TimeSpan.FromHours(1), TimeSpan.FromSeconds(10));

await using var dataSource = dataSourceBuilder.Build();
```

## Adding a New App Service

To grant database access to a new App Service:

### Step 1: Add Service to App Service Plugin
**File**: `iris-app-service-plugin/dev/locals.tf`

```hcl
app_services = {
  # ... existing services ...

  my-new-service = {
    name                = "${var.project_name}-my-new-service-${var.environment}-001"
    kind                = "webapp"
    app_service_plan_id = "primary"
    os_type             = "Linux"
    # ... rest of configuration ...
    identity_type = "SystemAssigned"  # IMPORTANT: Enable Managed Identity
  }
}
```

### Step 2: Deploy App Service Plugin
```bash
cd /Users/naveennegi/projects/apcoa/iris-app-service-plugin/dev
terraform apply
```

### Step 3: Add to Database Plugin
**File**: `iris-terraform-databases/dev/locals.tf`

```hcl
azure_ad_administrators = {
  # ... existing services ...

  my_new_service = {
    object_id      = try(local.app_service_identities["my-new-service"], null)
    principal_name = "iris-my-new-service-dev-001"
    principal_type = "ServicePrincipal"
  }
}
```

### Step 4: Deploy Database Plugin
```bash
cd /Users/naveennegi/projects/apcoa/iris-terraform-databases/dev
terraform apply
```

### Step 5: Grant Database Permissions (SQL)
Azure AD admin role allows CONNECTION but not data access. You must grant SQL permissions:

```sql
-- Connect to PostgreSQL as admin
psql "host=iris-postgres-dev.postgres.database.azure.com user=<your-admin> dbname=iris-app sslmode=require"

-- Create role for the new app service
SET aad_validate_oids_in_tenant = off;
CREATE ROLE "iris-my-new-service-dev-001" WITH LOGIN;
GRANT CONNECT ON DATABASE "iris-app" TO "iris-my-new-service-dev-001";

-- Grant permissions
GRANT USAGE ON SCHEMA public TO "iris-my-new-service-dev-001";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "iris-my-new-service-dev-001";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO "iris-my-new-service-dev-001";

-- Set default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "iris-my-new-service-dev-001";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO "iris-my-new-service-dev-001";
```

## Verification

### Check Azure AD Administrators
```bash
cd /Users/naveennegi/projects/apcoa/iris-terraform-databases/dev
terraform output postgresql_ad_admins_configured
```

### Check App Service Principal IDs
```bash
cd /Users/naveennegi/projects/apcoa/iris-app-service-plugin/dev
terraform output app_service_principal_ids
```

### Test Connection from App Service
Use the Azure Portal Kudu console or SSH:

```bash
# Install psql if not available
apt-get update && apt-get install -y postgresql-client

# Get token
TOKEN=$(curl -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://ossrdbms-aad.database.windows.net" | jq -r .access_token)

# Test connection
PGPASSWORD=$TOKEN psql "host=iris-postgres-dev.postgres.database.azure.com user=iris-iris-claps-dev-001 dbname=iris-app sslmode=require"
```

## Connection Strings

### PostgreSQL
```
Host=iris-postgres-dev.postgres.database.azure.com;Database=iris-app;SSL Mode=Require
```
**Username**: Your app service name (e.g., `iris-iris-claps-dev-001`)
**Password**: Azure AD token (retrieved automatically by SDK)

### Redis
```bash
# Get from Terraform outputs
cd /Users/naveennegi/projects/apcoa/iris-terraform-databases/dev
terraform output -json redis_connection_strings
```

## Security Notes

1. **No passwords stored anywhere** - All authentication via Azure AD tokens
2. **Automatic token rotation** - Azure SDK handles token refresh
3. **Principle of least privilege** - Grant only necessary SQL permissions
4. **Audit trail** - All connections logged in Azure AD
5. **Revocation** - Remove AD admin role to revoke access immediately

## Troubleshooting

### "Permission denied for table X"
- Azure AD admin role only grants CONNECTION, not data access
- You must grant SQL permissions manually (see Step 5 above)

### "Connection timeout"
- Check firewall rules on PostgreSQL server
- Verify "Allow Azure services" is enabled

### "Authentication failed"
- Verify Managed Identity is enabled on App Service
- Check AD admin role was granted (`terraform output postgresql_ad_admins_configured`)
- Ensure app is using correct username (app service name)

### "Token expired"
- Azure SDK should auto-refresh tokens
- Implement token refresh in your connection pooling logic
- Tokens are valid for 1 hour by default

## References

- [MANAGED_IDENTITY_SETUP.md](./MANAGED_IDENTITY_SETUP.md) - Complete setup guide
- [README.md](./README.md) - Project overview
- [Integration Guide](../iris-app-service-plugin/INTEGRATION_GUIDE.md) - Cross-plugin integration patterns
