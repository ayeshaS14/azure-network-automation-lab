# variables.tf
# All tuneable values are defined here so main.tf stays free of hard-coded
# strings. Override any default by passing -var="name=value" to terraform apply
# or by creating a terraform.tfvars file in this directory.

variable "location" {
  description = "Azure region where all resources will be created."
  type        = string
  default     = "East US"
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group."
  type        = string
  default     = "rg-network-automation-lab"
}

variable "vnet_name" {
  description = "Name of the Virtual Network."
  type        = string
  default     = "vnet-automation-lab"
}

variable "vnet_address_space" {
  description = "Overall address space for the VNet (must contain all subnet CIDRs)."
  type        = string
  default     = "10.0.0.0/16"
}

# ---------------------------------------------------------------------------
# Subnet CIDRs
# ---------------------------------------------------------------------------
variable "subnet_management_cidr" {
  description = "CIDR for the management subnet — used for jump hosts / admin VMs."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_application_cidr" {
  description = "CIDR for the application subnet — hosts app-tier workloads."
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_storage_cidr" {
  description = "CIDR for the storage subnet — isolates storage-tier resources."
  type        = string
  default     = "10.0.3.0/24"
}

# ---------------------------------------------------------------------------
# Tags applied to every resource for billing / ownership tracking
# ---------------------------------------------------------------------------
variable "tags" {
  description = "Map of tags to apply to all resources."
  type        = map(string)
  default = {
    project     = "azure-network-automation-lab"
    environment = "dev"
    owner       = "ayesha"
  }
}
