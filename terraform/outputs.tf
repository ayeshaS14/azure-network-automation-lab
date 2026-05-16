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

output "vm_management_public_ip" {
  description = "Public IP address of vm-management — use this to SSH in: ssh azureuser@<ip>"
  value       = azurerm_public_ip.management.ip_address
}

output "vm_management_private_ip" {
  description = "Private IP address of vm-management within the management subnet."
  value       = azurerm_network_interface.management.private_ip_address
}

output "vm_application_private_ip" {
  description = "Private IP address of vm-application within the application subnet."
  value       = azurerm_network_interface.application.private_ip_address
}

output "storage_account_name" {
  description = "Name of the Azure Storage Account — used in the blob upload script's connection string."
  value       = azurerm_storage_account.lab.name
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob service endpoint URL — base URL for all blob operations against this account."
  value       = azurerm_storage_account.lab.primary_blob_endpoint
}

output "storage_account_key" {
  description = "Primary access key for the storage account — used to build the connection string for upload_to_blob.py."
  value       = azurerm_storage_account.lab.primary_access_key
  sensitive   = true   # prevents the key from being printed in plain text during terraform apply/output
}
