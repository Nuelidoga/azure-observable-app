"""Blob storage access: connection string locally (Azurite), managed identity in Azure."""
import os


def _service():
    from azure.storage.blob import BlobServiceClient

    conn = os.getenv("STORAGE_CONNECTION_STRING")
    if conn:
        return BlobServiceClient.from_connection_string(conn)
    from azure.identity import ManagedIdentityCredential

    return BlobServiceClient(
        os.environ["STORAGE_ACCOUNT_URL"],
        credential=ManagedIdentityCredential(client_id=os.getenv("AZURE_CLIENT_ID")),
    )


def _container():
    client = _service().get_container_client(os.getenv("STORAGE_CONTAINER", "uploads"))
    if os.getenv("STORAGE_CONNECTION_STRING"):  # Azurite starts empty
        try:
            client.create_container()
        except Exception:  # noqa: BLE001
            pass
    return client


def upload(name, data):
    _container().upload_blob(name, data, overwrite=True)


def list_names():
    return [b.name for b in _container().list_blobs()]
