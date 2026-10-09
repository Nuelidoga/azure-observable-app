#!/usr/bin/env bash
# Creates the schema and grants the app's managed identity access to the database.
# Needs: Azure CLI login as the SQL Entra admin, Python 3 with `pip install pyodbc azure-identity`,
# and the Microsoft ODBC Driver 18 for SQL Server. Usage: scripts/post_deploy.sh <dev|prod>
set -euo pipefail
ENV_NAME="${1:?usage: scripts/post_deploy.sh <dev|prod>}"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$ENV_NAME"

MY_IP="$(curl -fsS https://api.ipify.org)"
RULE="tmp-operator-ip"
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER_NAME" -n "$RULE" \
  --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" -o none
cleanup() { az sql server firewall-rule delete -g "$RG" -s "$SQL_SERVER_NAME" -n "$RULE" -y -o none || true; }
trap cleanup EXIT

CLIENT_ID="$(az identity show -g "$RG" -n "$ID_NAME" --query clientId -o tsv)"
python3 "$ROOT/scripts/grant_sql_access.py" \
  --server "${SQL_SERVER_NAME}.database.windows.net" --database "$SQL_DB_NAME" \
  --identity-name "$ID_NAME" --client-id "$CLIENT_ID" --schema "$ROOT/sql/schema.sql"
