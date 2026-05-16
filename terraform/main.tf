# main.tf
# Provisions the core Azure network infrastructure for the automation lab:
#   - Resource Group
#   - Virtual Network with three subnets (management / application / storage)
#   - Network Security Groups (one per subnet) with baseline rules
#   - NSG-to-subnet associations
#
# Run order:
#   terraform init        — download the AzureRM provider
#   terraform plan        — preview changes
#   terraform apply       — create resources
#   terraform destroy     — tear everything down

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"   # pin to 3.x; update intentionally
    }
  }
  required_version = ">= 1.5.0"
}

# The AzureRM provider authenticates via environment variables or the Azure CLI.
# Recommended: run 'az login' before applying, or set:
#   ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID
provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# ---------------------------------------------------------------------------
# Resource Group — logical container for all lab resources
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# Virtual Network — single address space that all subnets live inside
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "lab" {
  name                = var.vnet_name
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

# Management subnet — jump hosts, Ansible/Netmiko control nodes, bastion VMs
resource "azurerm_subnet" "management" {
  name                 = "snet-management"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_management_cidr]
}

# Application subnet — app-tier VMs or containers
resource "azurerm_subnet" "application" {
  name                 = "snet-application"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_application_cidr]
}

# Storage subnet — storage accounts, file shares, databases
resource "azurerm_subnet" "storage" {
  name                 = "snet-storage"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [var.subnet_storage_cidr]
}

# ---------------------------------------------------------------------------
# Network Security Groups
# Each NSG gets a deny-all inbound default plus the minimum rules for its tier.
# ---------------------------------------------------------------------------

# --- Management NSG ---
# Allows SSH from anywhere (tighten the source_address_prefix to your IP in prod)
resource "azurerm_network_security_group" "management" {
  name                = "nsg-management"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = var.tags

  security_rule {
    name                       = "allow-ssh-inbound"
    priority                   = 100          # lower number = higher priority
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"          # replace with your admin CIDR
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-rdp-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"          # replace with your admin CIDR
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096         # last rule — catch-all deny
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# --- Application NSG ---
# Allows HTTP/HTTPS inbound from the management subnet and internet
resource "azurerm_network_security_group" "application" {
  name                = "nsg-application"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = var.tags

  security_rule {
    name                       = "allow-http-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh-from-management"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.subnet_management_cidr   # only management subnet
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# --- Storage NSG ---
# Only the application and management subnets may reach storage resources
resource "azurerm_network_security_group" "storage" {
  name                = "nsg-storage"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = var.tags

  security_rule {
    name                       = "allow-from-application-subnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.subnet_application_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-from-management-subnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.subnet_management_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# ---------------------------------------------------------------------------
# NSG associations — attach each NSG to its matching subnet
# ---------------------------------------------------------------------------

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.management.id
  network_security_group_id = azurerm_network_security_group.management.id
}

resource "azurerm_subnet_network_security_group_association" "application" {
  subnet_id                 = azurerm_subnet.application.id
  network_security_group_id = azurerm_network_security_group.application.id
}

resource "azurerm_subnet_network_security_group_association" "storage" {
  subnet_id                 = azurerm_subnet.storage.id
  network_security_group_id = azurerm_network_security_group.storage.id
}

# ---------------------------------------------------------------------------
# Public IP — management VM
# Static allocation so the address is known immediately after apply and
# remains stable across VM stop/start cycles.
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "management" {
  name                = "pip-vm-management"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  allocation_method   = "Static"   # dynamic IPs are only assigned on VM start
  sku                 = "Standard" # Standard SKU — Basic has zero quota on this subscription
  tags                = var.tags
}

# ---------------------------------------------------------------------------
# Network Interface — management VM
# Attaches the VM to the management subnet and associates the public IP so
# the VM is reachable over SSH from the internet.
# ---------------------------------------------------------------------------
resource "azurerm_network_interface" "management" {
  name                = "nic-vm-management"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig-management"
    subnet_id                     = azurerm_subnet.management.id
    private_ip_address_allocation = "Dynamic"              # Azure assigns a free IP from the subnet
    public_ip_address_id          = azurerm_public_ip.management.id
  }
}

# ---------------------------------------------------------------------------
# Linux VM — management
# Jump host / control node for SSH-ing into the rest of the lab.
# Password authentication is disabled; use the SSH key set in var.admin_ssh_public_key.
# ---------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "management" {
  name                            = "vm-management"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = "Standard_B1s"          # 1 vCPU, 1 GB RAM — cheapest burstable size
  admin_username                  = "azureuser"
  disable_password_authentication = true                    # SSH key only; no password login
  network_interface_ids           = [azurerm_network_interface.management.id]
  tags                            = var.tags

  # SSH public key — replace the placeholder in variables.tf with your real key
  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  # Ubuntu 22.04 LTS (Jammy Jellyfish) — Gen2 image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-vm-management"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"   # Standard HDD — lowest cost for a lab OS disk
  }
}

# ---------------------------------------------------------------------------
# Network Interface — application VM
# Internal-only NIC; no public IP because application VMs are accessed via
# the management VM or a load balancer, not directly from the internet.
# ---------------------------------------------------------------------------
resource "azurerm_network_interface" "application" {
  name                = "nic-vm-application"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig-application"
    subnet_id                     = azurerm_subnet.application.id
    private_ip_address_allocation = "Dynamic"
  }
}

# ---------------------------------------------------------------------------
# Linux VM — application
# App-tier VM reachable from the management VM over SSH (port 22 is allowed
# from the management subnet by the application NSG).
# ---------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "application" {
  name                            = "vm-application"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.application.id]
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "osdisk-vm-application"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

# ---------------------------------------------------------------------------
# Storage Account
# Holds all blob data for the lab (collected router output, backups, etc.).
# Name must be globally unique across all of Azure, 3-24 lowercase alphanumeric
# characters only — no hyphens or underscores allowed.
# Standard_LRS replicates data three times within a single data centre;
# sufficient for a lab where durability requirements are low.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "lab" {
  name                     = "stnetautomationlab"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable public blob access at the account level — individual containers
  # must explicitly opt in if public access is ever needed.
  allow_nested_items_to_be_public = false

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Blob Container — device-backups
# Logical namespace inside the storage account for router/device backup files.
# container_access_type = "private" means no anonymous access; every request
# must be authenticated via the storage account key or an Azure AD identity.
# ---------------------------------------------------------------------------
resource "azurerm_storage_container" "device_backups" {
  name                  = "device-backups"
  storage_account_name  = azurerm_storage_account.lab.name
  container_access_type = "private"
}
