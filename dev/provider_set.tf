provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }

  # For local dev, use Azure CLI (az login)
  subscription_id = "c6f2ac08-f21c-4e28-b5c2-dd798051a5f8"

  # OIDC authentication for CI/CD
  use_oidc = true
}
