"""
upload_to_blob.py
Uploads one or more local files to an Azure Blob Storage container.

Usage:
    python upload_to_blob.py <file1> [file2 ...]

The script reads the storage account connection string from the environment
variable AZURE_STORAGE_CONNECTION_STRING so that credentials are never
hard-coded in source files.

Install dependencies:
    pip install azure-storage-blob
"""

import os
import sys
from pathlib import Path
from datetime import datetime, timezone
from azure.storage.blob import BlobServiceClient, ContentSettings
from azure.core.exceptions import AzureError

# ---------------------------------------------------------------------------
# Configuration — set these to match your Azure storage account
# ---------------------------------------------------------------------------

# Read the connection string from the environment (never commit real secrets).
# To set it temporarily in your shell:
#   export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;..."
CONNECTION_STRING = os.environ.get("AZURE_STORAGE_CONNECTION_STRING", "")

# Name of the Blob Storage container that will receive the uploads.
# The script creates the container automatically if it does not exist.
CONTAINER_NAME = "network-automation-output"

# Optional: upload files into a virtual folder inside the container.
# Leave as "" to place files at the container root.
BLOB_FOLDER_PREFIX = "collected_output"


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def get_blob_client() -> BlobServiceClient:
    """Return an authenticated BlobServiceClient.

    Raises ValueError if the connection string env var is not set.
    """
    if not CONNECTION_STRING:
        raise ValueError(
            "Environment variable AZURE_STORAGE_CONNECTION_STRING is not set.\n"
            "Export it in your shell before running this script."
        )
    return BlobServiceClient.from_connection_string(CONNECTION_STRING)


def ensure_container_exists(service_client: BlobServiceClient, container_name: str):
    """Create the blob container if it does not already exist."""
    container_client = service_client.get_container_client(container_name)
    try:
        container_client.get_container_properties()
        print(f"[container] '{container_name}' already exists.")
    except Exception:
        # Container does not exist — create it with private access
        container_client.create_container()
        print(f"[container] Created '{container_name}'.")
    return container_client


def build_blob_name(local_path: str, folder_prefix: str) -> str:
    """
    Construct the blob name (path inside the container).
    If a folder prefix is set the file is placed inside that virtual folder.
    """
    filename = Path(local_path).name
    if folder_prefix:
        return f"{folder_prefix.rstrip('/')}/{filename}"
    return filename


def upload_file(container_client, local_path: str, blob_name: str):
    """Upload a single local file to the container, overwriting if it exists."""
    blob_client = container_client.get_blob_client(blob_name)

    # Detect content type for .txt files so the portal renders them correctly
    content_settings = ContentSettings(content_type="text/plain") if local_path.endswith(".txt") else None

    with open(local_path, "rb") as data:
        blob_client.upload_blob(
            data,
            overwrite=True,
            content_settings=content_settings,
        )

    print(f"  [uploaded] {local_path}  →  {CONTAINER_NAME}/{blob_name}")
    return blob_client.url


def main():
    # Collect file paths from command-line arguments
    if len(sys.argv) < 2:
        print("Usage: python upload_to_blob.py <file1> [file2 ...]")
        sys.exit(1)

    files_to_upload = sys.argv[1:]

    # Validate that every supplied path actually exists before connecting
    missing = [f for f in files_to_upload if not os.path.isfile(f)]
    if missing:
        for m in missing:
            print(f"[ERROR] File not found: {m}")
        sys.exit(1)

    start_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    print("=" * 60)
    print(f"Azure Blob Storage Upload — {start_time}")
    print(f"Container : {CONTAINER_NAME}")
    print(f"Files     : {len(files_to_upload)}")
    print("=" * 60)

    try:
        service_client = get_blob_client()
        container_client = ensure_container_exists(service_client, CONTAINER_NAME)

        uploaded_urls = []
        for local_path in files_to_upload:
            blob_name = build_blob_name(local_path, BLOB_FOLDER_PREFIX)
            url = upload_file(container_client, local_path, blob_name)
            uploaded_urls.append(url)

        print("\n" + "=" * 60)
        print(f"Upload complete — {len(uploaded_urls)} file(s) uploaded.")
        print("=" * 60)

    except ValueError as exc:
        # Missing credentials
        print(f"\n[ERROR] {exc}")
        sys.exit(1)
    except AzureError as exc:
        print(f"\n[ERROR] Azure SDK error: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
