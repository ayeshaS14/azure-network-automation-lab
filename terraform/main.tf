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
