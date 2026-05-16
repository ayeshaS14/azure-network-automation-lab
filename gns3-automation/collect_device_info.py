"""
collect_device_info.py
Connects to two Cisco IOS routers via SSH using Netmiko, collects interface
status and routing table output, saves results to timestamped files, and
alerts on any interfaces that are administratively or operationally down.
"""

import os
import re
from datetime import datetime
from netmiko import ConnectHandler
from netmiko.exceptions import NetmikoTimeoutException, NetmikoAuthenticationException
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import AzureError


# Device definitions to fill in your GNS3 router IPs and credentials here
DEVICES = [
    {
        "device_type": "cisco_ios",
        "host": "192.168.1.1",        # Router 1 management IP
        "username": "admin",           # SSH username
        "password": "cisco",           # SSH password
        "secret": "cisco",             # Enable secret (for privileged mode)
        "port": 22,
        "name": "R1",                  # Friendly label used in output filenames
    },
    {
        "device_type": "cisco_ios",
        "host": "192.168.1.2",        # Router 2 management IP
        "username": "admin",
        "password": "cisco",
        "secret": "cisco",
        "port": 22,
        "name": "R2",
    },
]

# ---------------------------------------------------------------------------
# Commands to run on every device
# ---------------------------------------------------------------------------
COMMANDS = {
    "interfaces": "show interfaces",
    "routing_table": "show ip route",
}

# Directory where collected output files will be saved
OUTPUT_DIR = "collected_output"

# ---------------------------------------------------------------------------
# Azure Blob Storage configuration
# AZURE_STORAGE_KEY must be set in your shell before running this script:
#   export AZURE_STORAGE_KEY="<primary or secondary key from the Azure portal>"
# The key is read at runtime so it is never stored in source code.
# ---------------------------------------------------------------------------
STORAGE_ACCOUNT_NAME = "stnetautomationlab"
STORAGE_CONTAINER_NAME = "device-backups"
STORAGE_ACCOUNT_URL = f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"


def ensure_output_dir():
    """Create the output directory if it does not already exist."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)


def build_filename(device_name: str, data_type: str, timestamp: str) -> str:
    """Return a timestamped filename for a given device and data type."""
    return os.path.join(OUTPUT_DIR, f"{device_name}_{data_type}_{timestamp}.txt")


def save_output(filepath: str, content: str):
    """Write command output to a text file."""
    with open(filepath, "w") as f:
        f.write(content)
    print(f"  [saved] {filepath}")


def upload_to_blob(local_filepath: str) -> str | None:
    """
    Upload a single local file to the Azure Blob Storage container.

    The blob is stored under the container root using the file's basename,
    e.g. "R1_interfaces_20240516_143022.txt".

    Returns the full blob URL on success, or None if the upload fails.
    The caller decides whether a failure is fatal; this function only warns.
    """
    # Read the storage key from the environment — never hard-code it
    storage_key = os.environ.get("AZURE_STORAGE_KEY", "")
    if not storage_key:
        print("  [WARN] AZURE_STORAGE_KEY is not set — skipping blob upload")
        return None

    blob_name = os.path.basename(local_filepath)

    try:
        # Authenticate with the account key; no connection string needed
        service_client = BlobServiceClient(
            account_url=STORAGE_ACCOUNT_URL,
            credential=storage_key,
        )
        blob_client = service_client.get_blob_client(
            container=STORAGE_CONTAINER_NAME,
            blob=blob_name,
        )

        # Open the already-written local file and stream it to Azure
        with open(local_filepath, "rb") as data:
            blob_client.upload_blob(data, overwrite=True)

        blob_url = blob_client.url
        print(f"  [uploaded] {blob_url}")
        return blob_url

    except AzureError as exc:
        # Upload failure is non-fatal — the file is already saved locally
        print(f"  [WARN] Blob upload failed for '{blob_name}': {exc}")
        return None
    except OSError as exc:
        print(f"  [WARN] Could not open '{local_filepath}' for upload: {exc}")
        return None


def detect_down_interfaces(interfaces_output: str, device_name: str):
    """
    Parse 'show interfaces' output and print an alert for every interface
    whose line protocol or admin state is reported as down.

    Cisco IOS lines look like:
        GigabitEthernet0/0 is administratively down, line protocol is down
        GigabitEthernet0/1 is up, line protocol is down
    """
    # Match lines that describe interface state
    pattern = re.compile(
        r"^(\S+)\s+is\s+(administratively down|down),?\s*line protocol is\s+(down|up)",
        re.MULTILINE | re.IGNORECASE,
    )

    alerts = []
    for match in pattern.finditer(interfaces_output):
        intf_name = match.group(1)
        admin_state = match.group(2)
        protocol_state = match.group(3)
        alerts.append((intf_name, admin_state, protocol_state))

    if alerts:
        print(f"\n  [ALERT] Down interfaces detected on {device_name}:")
        for intf, admin, proto in alerts:
            print(f"    - {intf}: admin={admin}, protocol={proto}")
    else:
        print(f"  [OK] All interfaces are up on {device_name}")

    return alerts


def collect_from_device(device_config: dict, timestamp: str):
    """
    Open an SSH session to one device, run all commands, save output files,
    and check for down interfaces. Returns a list of any alert tuples.
    """
    name = device_config["name"]
    # Netmiko does not accept our custom 'name' key — strip it before connecting
    conn_params = {k: v for k, v in device_config.items() if k != "name"}

    print(f"\nConnecting to {name} ({conn_params['host']}) ...")

    try:
        connection = ConnectHandler(**conn_params)
        connection.enable()  # Enter privileged EXEC mode using the 'secret'
        print(f"  [connected] {name}")

        results = {}
        for label, command in COMMANDS.items():
            print(f"  Running: {command}")
            output = connection.send_command(command)
            results[label] = output

            filepath = build_filename(name, label, timestamp)
            save_output(filepath, output)
            upload_to_blob(filepath)   # non-fatal if upload fails

        connection.disconnect()
        print(f"  [disconnected] {name}")

        # Analyse interface output for down state alerts
        alerts = detect_down_interfaces(results["interfaces"], name)
        return alerts

    except NetmikoTimeoutException:
        print(f"  [ERROR] Connection timed out for {name} ({conn_params['host']})")
    except NetmikoAuthenticationException:
        print(f"  [ERROR] Authentication failed for {name} — check username/password/secret")
    except Exception as exc:
        print(f"  [ERROR] Unexpected error on {name}: {exc}")

    return []


def main():
    # Shared timestamp so all files from this run share the same suffix
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    print("=" * 60)
    print(f"Network Data Collection — {timestamp}")
    print("=" * 60)

    ensure_output_dir()

    all_alerts = {}
    for device in DEVICES:
        alerts = collect_from_device(device, timestamp)
        if alerts:
            all_alerts[device["name"]] = alerts

    # Final summary
    print("\n" + "=" * 60)
    print("Collection complete.")
    if all_alerts:
        print("SUMMARY — Devices with down interfaces:")
        for dev, alerts in all_alerts.items():
            for intf, admin, proto in alerts:
                print(f"  {dev} / {intf}: admin={admin}, protocol={proto}")
    else:
        print("SUMMARY — All interfaces are up across all devices.")
    print("=" * 60)


if __name__ == "__main__":
    main()
