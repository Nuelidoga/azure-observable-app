"""Azure SQL / SQL Server access.

Two auth modes, chosen by DB_AUTH:
  sql               -> user/password (local docker compose only)
  managed_identity  -> Entra token from the container's managed identity (Azure)
"""
import os
import re
import struct
import time

SCHEMA = (
    "IF OBJECT_ID(N'dbo.tasks', N'U') IS NULL "
    "CREATE TABLE dbo.tasks ("
    "id INT IDENTITY(1,1) PRIMARY KEY, "
    "title NVARCHAR(200) NOT NULL, "
    "done BIT NOT NULL DEFAULT 0, "
    "created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME())"
)


def connect(database=None, autocommit=False):
    import pyodbc  # imported lazily so unit tests do not need the ODBC driver

    server = os.environ["SQL_SERVER"]
    database = database or os.environ["SQL_DATABASE"]
    trust = os.getenv("SQL_TRUST_CERT", "no")
    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};DATABASE={database};"
        f"Encrypt=yes;TrustServerCertificate={trust};Connection Timeout=30;"
    )
    if os.getenv("DB_AUTH", "sql") == "managed_identity":
        from azure.identity import ManagedIdentityCredential

        cred = ManagedIdentityCredential(client_id=os.getenv("AZURE_CLIENT_ID"))
        raw = cred.get_token("https://database.windows.net/.default").token
        raw = raw.encode("utf-16-le")
        token = struct.pack(f"<I{len(raw)}s", len(raw), raw)
        return pyodbc.connect(conn_str, attrs_before={1256: token}, autocommit=autocommit)
    conn_str += f"UID={os.environ['SQL_USER']};PWD={os.environ['SQL_PASSWORD']};"
    return pyodbc.connect(conn_str, autocommit=autocommit)


def _connect_retry(**kwargs):
    """Serverless SQL auto-pauses; the first connection after a pause can fail."""
    last = None
    for _ in range(8):
        try:
            return connect(**kwargs)
        except Exception as exc:  # noqa: BLE001
            last = exc
            time.sleep(8)
    raise last


def init():
    """Local dev only (DB_INIT=true): create database + table if missing."""
    if os.getenv("DB_INIT", "false").lower() != "true":
        return
    name = os.environ["SQL_DATABASE"]
    if not re.fullmatch(r"[A-Za-z0-9_]+", name):
        raise ValueError("invalid database name")
    conn = _connect_retry(database="master", autocommit=True)
    conn.execute(f"IF DB_ID(N'{name}') IS NULL CREATE DATABASE [{name}]")
    conn.close()
    conn = _connect_retry(autocommit=True)
    conn.execute(SCHEMA)
    conn.close()


def ping():
    conn = _connect_retry()
    conn.execute("SELECT 1").fetchone()
    conn.close()


def list_tasks():
    conn = _connect_retry()
    rows = conn.execute(
        "SELECT TOP 100 id, title, done, created_at FROM dbo.tasks ORDER BY id DESC"
    ).fetchall()
    conn.close()
    return [
        {"id": r.id, "title": r.title, "done": bool(r.done), "created_at": r.created_at.isoformat()}
        for r in rows
    ]


def add_task(title):
    conn = _connect_retry()
    row = conn.execute(
        "INSERT INTO dbo.tasks (title) OUTPUT INSERTED.id VALUES (?)", title
    ).fetchone()
    conn.commit()
    conn.close()
    return row.id
