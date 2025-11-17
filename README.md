# IRIS Terraform Databases

Terraform infrastructure for managing PostgreSQL and Redis databases for the APCOA IRIS project.

## Architecture

This repository follows the APCOA Azure Terraform architecture pattern:

- **Declarative configuration** in `locals.tf` defining what to create
- **Iteration-based `main.tf`** using Azure Verified Modules (AVM)
- **Environment-based folder structure**: `dev/`, `uat/`, `prd/`
- **Centralized state storage** in Azure Storage account

## Resources Managed

### PostgreSQL Flexible Server
- Azure Database for PostgreSQL Flexible Server (v16)
- **Azure AD (Entra ID) authentication** - Passwordless with Managed Identity
- Multiple databases: `iris-app`, `iris-analytics`
- Automatic backups and maintenance windows
- Firewall rules for Azure services

### Redis Cache
- Azure Cache for Redis
- TLS 1.2 enforcement
- LRU eviction policy
- Managed access keys (retrieved via Terraform outputs)
- Basic tier for dev (configurable per environment)

## 🔐 Security: Passwordless Authentication

This infrastructure uses **Azure Managed Identity** for secure, passwordless authentication:

- ✅ **No passwords to manage** - PostgreSQL uses Azure AD authentication
- ✅ **Automatic credential rotation** - Azure handles all token management
- ✅ **Zero secrets in code** - App Services use Managed Identity
- ✅ **Enhanced security** - Fine-grained RBAC control

See [MANAGED_IDENTITY_SETUP.md](./MANAGED_IDENTITY_SETUP.md) for complete setup instructions.

## Prerequisites

1. **Azure CLI** installed and authenticated
   ```bash
   az login
   az account set --subscription c6f2ac08-f21c-4e28-b5c2-dd798051a5f8
   ```

2. **Terraform** >= 1.5
   ```bash
   terraform version
   ```

3. **Access to APCOA Azure Subscription**
   - Subscription ID: `c6f2ac08-f21c-4e28-b5c2-dd798051a5f8`
   - Resource Group: `iot-dev` (for dev environment)

## Local Development Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd iris-terraform-databases
```

### 2. Authenticate with Azure
```bash
az login
az account set --subscription c6f2ac08-f21c-4e28-b5c2-dd798051a5f8
```

**Note:** No passwords or environment variables needed! The infrastructure uses Azure AD authentication.

### 3. Initialize Terraform (Dev Environment)
```bash
cd dev
terraform init
```

### 4. Review Configuration
Check the plan before applying:
```bash
terraform plan
```

### 5. Apply Changes
```bash
terraform apply
```

### 6. View Outputs
Get connection strings and resource information:
```bash
terraform output
```

## Configuration

### Adding New Databases

Edit `dev/locals.tf` and add to the `databases` map:

```hcl
databases = {
  "iris-app" = {
    name      = "iris-app"
    charset   = "UTF8"
    collation = "en_US.utf8"
  }
  "your-new-db" = {
    name      = "your-new-db"
    charset   = "UTF8"
    collation = "en_US.utf8"
  }
}
```

### Scaling Resources

For production environments, update `locals.tf`:

**PostgreSQL:**
```hcl
sku_name   = "GP_Standard_D4s_v3"  # General Purpose, 4 vCores
storage_mb = 131072                 # 128 GB
high_availability = {
  mode = "ZoneRedundant"
}
geo_redundant_backup_enabled = true
```

**Redis:**
```hcl
sku_name = "Premium"
family   = "P"
capacity = 1  # 6 GB cache
```

## CI/CD with GitHub Actions

### Required GitHub Secrets

Configure these secrets in your GitHub repository:

```yaml
AZURE_CLIENT_ID: <from-federated-identity>
AZURE_TENANT_ID: <azure-tenant-id>
AZURE_SUBSCRIPTION_ID: c6f2ac08-f21c-4e28-b5c2-dd798051a5f8
```

**Note:** No database passwords needed! Azure AD authentication is used.

### Workflow Triggers

- **Pull Requests**: Automatic `terraform plan` on PRs to main/develop
- **Manual Deployment**: Use workflow dispatch to run plan/apply/destroy

### Manual Workflow Execution

1. Go to **Actions** tab in GitHub
2. Select **Terraform CI/CD** workflow
3. Click **Run workflow**
4. Choose:
   - Environment: `dev`, `uat`, or `prd`
   - Action: `plan`, `apply`, or `destroy`

## Setting up Azure Federated Identity (OIDC)

For iris-* repositories, federated credentials should already exist. Just add the GitHub secrets listed above.

If you need to create new credentials, use the `github-oidc-federated-identity` skill or run:

```bash
# This will be set up separately using the APCOA federated identity skill
```

## Project Structure

```
iris-terraform-databases/
├── dev/
│   ├── backend.tf          # Azure backend configuration
│   ├── data.tf             # Data sources (resource group, client config)
│   ├── locals.tf           # Declarative resource configuration
│   ├── main.tf             # AVM module iterations
│   ├── outputs.tf          # Connection strings and resource IDs
│   ├── provider_set.tf     # Azure provider setup
│   ├── variables.tf        # Input variables
│   ├── versions.tf         # Terraform and provider versions
│   └── terraform.tfvars    # Environment-specific values
├── uat/                    # UAT environment (to be created)
├── prd/                    # Production environment (to be created)
├── .github/
│   └── workflows/
│       └── terraform.yml        # CI/CD pipeline
├── .env.example                 # Environment template (no passwords!)
├── .gitignore
├── MANAGED_IDENTITY_SETUP.md    # Passwordless auth setup guide
└── README.md
```

## Terraform State

State files are stored in Azure Storage:
- **Storage Account**: `tfstateirisapcoa`
- **Resource Group**: `terraform-state-rg`
- **Container**: `tfstate`
- **State Files**:
  - Dev: `iris-terraform-databases.dev.tfstate`
  - UAT: `iris-terraform-databases.uat.tfstate`
  - Prd: `iris-terraform-databases.prd.tfstate`

State locking is automatically enabled via Azure Storage blob leases.

## Outputs

After applying, you can retrieve:

### PostgreSQL
- Server FQDNs
- Database names
- Connection strings (format: `postgresql://user@host:5432/dbname?sslmode=require`)

### Redis
- Hostnames
- SSL ports
- Primary access keys
- Connection strings

Example:
```bash
# Get PostgreSQL connection string
terraform output -json postgresql_connection_strings

# Get Redis connection string
terraform output -json redis_connection_strings
```

## Security Best Practices

1. **Use Managed Identity** - No passwords in code or config (already implemented!)
2. **Enable private endpoints** for production environments
3. **Azure AD authentication only** - Disable password auth in production
4. **Enable Advanced Threat Protection** for production databases
5. **Use VNet integration** to restrict network access
6. **Never commit .tfvars or .env files** to git (already in .gitignore)

## Troubleshooting

### Authentication Issues
```bash
# Verify Azure CLI login
az account show

# Re-authenticate if needed
az login
az account set --subscription c6f2ac08-f21c-4e28-b5c2-dd798051a5f8
```

### State Lock Issues
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>
```

### Plan Fails
```bash
# Verify Azure authentication
az account show

# Verify resource group exists
az group show --name iot-dev

# Check Terraform version
terraform version
```

## Adding UAT/Production Environments

When ready to add UAT/PRD:

1. Copy the `dev/` folder structure to `uat/` or `prd/`
2. Update `backend.tf` with the correct state file key
3. Update `terraform.tfvars` with environment-specific values
4. Adjust resource SKUs in `locals.tf` for production workloads
5. Enable high availability and geo-redundancy for production

## Support

For issues or questions:
- Internal: Contact the APCOA DevOps team
- Terraform Registry: https://registry.terraform.io/namespaces/Azure

## License

Internal APCOA project - All rights reserved
