# Use data source for shared resource group (not managed by this module)
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

##############################################
# Remote State - App Service Plugin
##############################################

data "terraform_remote_state" "app_services" {
  backend = "azurerm"

  config = {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstateirisapcoa"
    container_name       = "tfstate"
    key                  = "iris-app-service-plugin.dev.tfstate"
    use_oidc             = true
  }
}
