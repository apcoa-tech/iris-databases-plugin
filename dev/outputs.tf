# PostgreSQL Outputs
output "postgresql_server_ids" {
  description = "Map of PostgreSQL server IDs"
  value = {
    for k, v in azurerm_postgresql_flexible_server.this : k => v.id
  }
}

output "postgresql_server_fqdns" {
  description = "Map of PostgreSQL server FQDNs"
  value = {
    for k, v in azurerm_postgresql_flexible_server.this : k => v.fqdn
  }
}

output "postgresql_databases" {
  description = "Map of PostgreSQL databases created"
  value = {
    for k, v in azurerm_postgresql_flexible_server_database.this : k => {
      name    = v.name
      id      = v.id
      charset = v.charset
    }
  }
  sensitive = true
}

output "postgresql_connection_strings" {
  description = "PostgreSQL connection strings for app services (using Managed Identity)"
  value = {
    for k, server in azurerm_postgresql_flexible_server.this : k => {
      for db_key, db in local.postgres_servers[k].databases :
      db_key => "Host=${server.fqdn};Database=${db.name};SSL Mode=Require"
    }
  }
  sensitive = true
}

output "postgresql_ad_admins_configured" {
  description = "List of Azure AD administrators configured for PostgreSQL"
  value = {
    for k, admin in azurerm_postgresql_flexible_server_active_directory_administrator.app_services :
    k => {
      principal_name = admin.principal_name
      principal_type = admin.principal_type
      server_name    = admin.server_name
    }
  }
}
