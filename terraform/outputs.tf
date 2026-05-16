# outputs.tf
# Values printed to the terminal after 'terraform apply' and readable via
# 'terraform output'. Useful for piping into other scripts or CI pipelines.

output "resource_group_name" {
  description = "Name of the created Resource Group."
  value       = azurerm_resource_group.lab.name
}

output "vnet_id" {
  description = "Resource ID of the Virtual Network."
  value       = azurerm_virtual_network.lab.id
}

output "subnet_management_id" {
  description = "Resource ID of the management subnet."
  value       = azurerm_subnet.management.id
}

output "subnet_application_id" {
  description = "Resource ID of the application subnet."
  value       = azurerm_subnet.application.id
}

output "subnet_storage_id" {
  description = "Resource ID of the storage subnet."
  value       = azurerm_subnet.storage.id
}

output "nsg_management_id" {
  description = "Resource ID of the management NSG."
  value       = azurerm_network_security_group.management.id
}

output "nsg_application_id" {
  description = "Resource ID of the application NSG."
  value       = azurerm_network_security_group.application.id
}

output "nsg_storage_id" {
  description = "Resource ID of the storage NSG."
  value       = azurerm_network_security_group.storage.id
}
