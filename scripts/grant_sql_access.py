#!/usr/bin/env python3
"""Create the schema and a contained user for the app's managed identity.

CREATE USER ... WITH SID avoids a Microsoft Graph lookup, so it also works when the
SQL Entra admin is a service principal (the CI pipeline).
"""
import argparse
import re
import struct
import sys
import time
import uuid

import pyodbc
from azure.identity import AzureCliCredential


def connect(server, database):
    raw = AzureCliCredential().get_token("https://database.windows.net/.default").token
    raw = raw.encode("utf-16-le")
    token = struct.pack(f"<I{len(raw)}s", len(raw), raw)
    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER=tcp:{server},1433;DATABASE={database};Encrypt=yes;TrustServerCertificate=no;"
    )
    return pyodbc.connect(conn_str, attrs_before={1256: token}, autocommit=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--server", required=True)
    p.add_argument("--database", required=True)
    p.add_argument("--identity-name", required=True)
    p.add_argument("--client-id", required=True)
    p.add_argument("--schema", required=True)
    a = p.parse_args()

    if not re.fullmatch(r"[A-Za-z0-9_-]+", a.identity_name):
        sys.exit("invalid identity name")
    sid = "0x" + uuid.UUID(a.client_id).bytes_le.hex().upper()
    name = a.identity_name
    statements = [
        open(a.schema, encoding="utf-8").read(),
        f"IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'{name}') "
        f"CREATE USER [{name}] WITH SID = {sid}, TYPE = E",
        f"ALTER ROLE db_datareader ADD MEMBER [{name}]",
        f"ALTER ROLE db_datawriter ADD MEMBER [{name}]",
    ]

    last = None
    for attempt in range(1, 11):  # firewall rule + serverless resume can take a few minutes
        try:
            conn = connect(a.server, a.database)
            for stmt in statements:
                conn.execute(stmt)
            conn.close()
            print(f"OK: schema applied and access granted to {name}")
            return
        except Exception as exc:  # noqa: BLE001
            last = exc
            print(f"attempt {attempt} failed: {exc}")
            time.sleep(20)
    sys.exit(f"giving up: {last}")


if __name__ == "__main__":
    main()
