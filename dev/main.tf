# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "this" {
  for_each = local.postgres_servers

  name                = each.value.name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  sku_name   = each.value.sku_name
  storage_mb = each.value.storage_mb
  version    = each.value.version

  # Only set admin credentials if password authentication is enabled
  administrator_login    = each.value.authentication.password_auth_enabled ? each.value.administrator_login : null
  administrator_password = each.value.authentication.password_auth_enabled ? each.value.administrator_password : null

  # Azure AD authentication
  authentication {
    active_directory_auth_enabled = each.value.authentication.active_directory_auth_enabled
    password_auth_enabled         = each.value.authentication.password_auth_enabled
    tenant_id                     = each.value.authentication.tenant_id
  }

  backup_retention_days        = each.value.backup_retention_days
  geo_redundant_backup_enabled = each.value.geo_redundant_backup_enabled

  public_network_access_enabled = each.value.public_network_access_enabled

  tags = local.common_tags
}

# PostgreSQL Databases
resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = merge([
    for server_key, server in local.postgres_servers : {
      for db_key, db in server.databases :
      "${server_key}-${db_key}" => {
        server_key = server_key
        server_id  = azurerm_postgresql_flexible_server.this[server_key].id
        name       = db.name
        charset    = db.charset
        collation  = db.collation
      }
    }
  ]...)

  name      = each.value.name
  server_id = each.value.server_id
  charset   = each.value.charset
  collation = each.value.collation
}

# PostgreSQL Firewall Rules
resource "azurerm_postgresql_flexible_server_firewall_rule" "this" {
  for_each = merge([
    for server_key, server in local.postgres_servers : {
      for rule_key, rule in server.firewall_rules :
      "${server_key}-${rule_key}" => {
        server_id        = azurerm_postgresql_flexible_server.this[server_key].id
        name             = rule.name
        start_ip_address = rule.start_ip_address
        end_ip_address   = rule.end_ip_address
      }
    }
  ]...)

  name             = each.value.name
  server_id        = each.value.server_id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

# Flatten PostgreSQL servers and Azure AD administrators for iteration
locals {
  # Create a map of all AD administrators across all PostgreSQL servers
  postgres_ad_admins = merge([
    for server_key, server in local.postgres_servers : {
      for admin_key, admin in server.azure_ad_administrators :
      "${server_key}-${admin_key}" => {
        server_key     = server_key
        server_name    = server.name
        admin_key      = admin_key
        object_id      = admin.object_id
        principal_name = admin.principal_name
        principal_type = admin.principal_type
      } if admin.object_id != null # Only create if principal_id exists
    }
  ]...)
}

# Grant Azure AD Administrator access to App Services for PostgreSQL
# This allows app services to authenticate using their Managed Identity
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "app_services" {
  for_each = local.postgres_ad_admins

  server_name         = azurerm_postgresql_flexible_server.this[each.value.server_key].name
  resource_group_name = data.azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = each.value.object_id
  principal_name      = each.value.principal_name
  principal_type      = each.value.principal_type

  depends_on = [azurerm_postgresql_flexible_server.this]
}
