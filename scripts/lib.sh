#!/usr/bin/env bash
# Shared helpers. Usage: source scripts/lib.sh <dev|prod>
# Loads the environment file and derives every resource name deterministically,
# so scripts never need to look names up.
ENV_NAME="${1:?environment name required (dev|prod)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set -a
# shellcheck disable=SC1090
source "$ROOT/infra/parameters/${ENV_NAME}.env"
if [ -f "$ROOT/infra/parameters/${ENV_NAME}.local.env" ]; then
  # shellcheck disable=SC1090
  source "$ROOT/infra/parameters/${ENV_NAME}.local.env"
fi
set +a

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
RG="rg-${PROJECT}-${ENV_NAME}"
if command -v sha1sum >/dev/null 2>&1; then HASHER="sha1sum"; else HASHER="shasum"; fi
SUFFIX="$(printf '%s' "${SUBSCRIPTION_ID}${RG}" | $HASHER | cut -c1-6)"
NAME_BASE="${PROJECT}-${ENV_NAME}"

ID_NAME="id-${NAME_BASE}"
LAW_NAME="log-${NAME_BASE}"
AI_NAME="appi-${NAME_BASE}"
AG_NAME="ag-${NAME_BASE}"
ST_NAME="$(printf 'st%s%s%s' "${PROJECT//-/}" "${ENV_NAME}" "${SUFFIX}" | cut -c1-24)"
ACR_NAME="$(printf 'acr%s%s%s' "${PROJECT//-/}" "${ENV_NAME}" "${SUFFIX}" | cut -c1-50)"
KV_NAME="$(printf 'kv-%s-%s' "${NAME_BASE}" "${SUFFIX}" | cut -c1-24)"
SQL_SERVER_NAME="sql-${NAME_BASE}-${SUFFIX}"
SQL_DB_NAME="sqldb-tasks"
CAE_NAME="cae-${NAME_BASE}"
APP_NAME="ca-${NAME_BASE}"
TAGS_JSON="{\"project\":\"${PROJECT}\",\"env\":\"${ENV_NAME}\",\"owner\":\"${OWNER}\",\"ttl\":\"${TTL}\"}"
PLACEHOLDER_IMAGE="mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
