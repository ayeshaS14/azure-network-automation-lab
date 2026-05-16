# Azure Network Automation Lab

End-to-end network automation lab combining GNS3 router data collection,
Terraform-managed Azure infrastructure, and a Python utility for pushing
collected data to Azure Blob Storage.

---

## Project Structure

```
azure-network-automation-lab/
├── gns3-automation/
│   ├── collect_device_info.py   # Netmiko script — pulls data from Cisco IOS routers
│   └── requirements.txt         # Python dependencies
├── terraform/
│   ├── main.tf                  # Resource Group, VNet, Subnets, NSGs
│   ├── variables.tf             # All configurable values
│   └── outputs.tf               # Values printed after apply
├── scripts/
│   └── upload_to_blob.py        # Uploads collected files to Azure Blob Storage
└── README.md
```

---

## Part 1 — GNS3 Router Data Collection

### What it does
`collect_device_info.py` connects to two Cisco IOS routers over SSH and:

1. Runs `show interfaces` and `show ip route` on each router
2. Saves the output to timestamped `.txt` files inside `gns3-automation/collected_output/`
3. Parses the interface output and prints an alert for any interface that is
   administratively down or has a down line protocol

### Setup

```bash
cd gns3-automation
pip install -r requirements.txt
```

### Configuration

Open `collect_device_info.py` and update the `DEVICES` list with your router details:

```python
DEVICES = [
    {
        "host": "192.168.1.1",   # ← your GNS3 router IP
        "username": "admin",      # ← SSH username
        "password": "cisco",      # ← SSH password
        "secret": "cisco",        # ← enable secret
        ...
    },
    ...
]
```

### Run

```bash
python collect_device_info.py
```

### Sample output

```
============================================================
Network Data Collection — 20240516_143022
============================================================

Connecting to R1 (192.168.1.1) ...
  [connected] R1
  Running: show interfaces
  [saved] collected_output/R1_interfaces_20240516_143022.txt
  Running: show ip route
  [saved] collected_output/R1_routing_table_20240516_143022.txt
  [disconnected] R1

  [ALERT] Down interfaces detected on R1:
    - GigabitEthernet0/1: admin=administratively down, protocol=down

============================================================
SUMMARY — Devices with down interfaces:
  R1 / GigabitEthernet0/1: admin=administratively down, protocol=down
============================================================
```

---

## Part 2 — Azure Infrastructure (Terraform)

### What it creates

| Resource | Name | Details |
|---|---|---|
| Resource Group | `rg-network-automation-lab` | All resources live here |
| Virtual Network | `vnet-automation-lab` | `10.0.0.0/16` address space |
| Subnet — Management | `snet-management` | `10.0.1.0/24` |
| Subnet — Application | `snet-application` | `10.0.2.0/24` |
| Subnet — Storage | `snet-storage` | `10.0.3.0/24` |
| NSG — Management | `nsg-management` | Allows SSH (22) and RDP (3389) inbound |
| NSG — Application | `nsg-application` | Allows HTTP/HTTPS; SSH only from management subnet |
| NSG — Storage | `nsg-storage` | Accepts traffic only from application & management subnets |

### Prerequisites

- [Terraform >= 1.5](https://developer.hashicorp.com/terraform/install)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- An active Azure subscription

### Authentication

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### Deploy

```bash
cd terraform

terraform init      # download the AzureRM provider
terraform plan      # preview what will be created
terraform apply     # create the resources (type 'yes' to confirm)
```

### Override default values

Create a `terraform.tfvars` file (do not commit it if it contains secrets):

```hcl
location            = "West Europe"
resource_group_name = "rg-my-custom-lab"
```

### Tear down

```bash
terraform destroy
```

---

## Part 3 — Upload to Azure Blob Storage

### What it does

`scripts/upload_to_blob.py` takes one or more local file paths as arguments
and uploads them to the `network-automation-output` container in your Azure
Storage Account. The container is created automatically if it does not exist.

### Setup

```bash
pip install azure-storage-blob
```

Set your storage account connection string as an environment variable
(never hard-code credentials):

```bash
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net"
```

Find the connection string in the Azure Portal under:
**Storage Account → Security + Networking → Access keys**

### Run

Upload all files collected by the GNS3 script in one command:

```bash
python scripts/upload_to_blob.py gns3-automation/collected_output/*.txt
```

Or upload individual files:

```bash
python scripts/upload_to_blob.py gns3-automation/collected_output/R1_interfaces_20240516_143022.txt
```

---

## End-to-End Workflow

```
GNS3 Routers
     │
     │  SSH (Netmiko)
     ▼
collect_device_info.py
     │
     │  writes timestamped .txt files
     ▼
gns3-automation/collected_output/
     │
     │  upload_to_blob.py
     ▼
Azure Blob Storage (network-automation-output container)
```

The Azure VNet and subnets provisioned by Terraform provide the network
foundation into which you would deploy VMs or containers that run these
scripts in a production scenario.

---

## Requirements Summary

| Tool | Version | Purpose |
|---|---|---|
| Python | 3.8+ | GNS3 scripts and blob uploader |
| netmiko | 4.3.0 | SSH automation for Cisco IOS |
| azure-storage-blob | latest | Azure Blob Storage SDK |
| Terraform | 1.5+ | Azure infrastructure provisioning |
| Azure CLI | latest | Authentication for Terraform |
