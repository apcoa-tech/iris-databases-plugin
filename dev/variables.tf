variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where resources will be created"
  default     = "iot-dev"
}

variable "location" {
  type        = string
  description = "Azure region for resources"
  default     = "westeurope"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, uat, prd)"
  validation {
    condition     = contains(["dev", "uat", "prd"], var.environment)
    error_message = "Environment must be dev, uat, or prd"
  }
  default = "dev"
}

variable "tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default     = {}
}

# NOTE: No password variables needed!
# PostgreSQL uses Azure AD (Entra ID) authentication with Managed Identity
# Redis access keys are automatically managed by Azure
