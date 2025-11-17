terraform {
  backend "azurerm" {
    # Storage account for Terraform state
    # Created in subscription: c6f2ac08-f21c-4e28-b5c2-dd798051a5f8
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateirisapcoa"
    container_name       = "tfstate"
    key                  = "iris-databases-plugin.dev.tfstate"

    # Use OIDC for authentication in CI/CD
    # Falls back to Azure CLI (az login) for local development
    use_oidc = true

    # State locking is automatically enabled via Azure Storage blob leases
    # This prevents concurrent terraform operations
  }
}
