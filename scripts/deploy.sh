#!/usr/bin/env bash
# Deploys the whole stack, module by module: what-if first, then deploy.
# Usage: scripts/deploy.sh <dev|prod>
set -euo pipefail
ENV_NAME="${1:?usage: scripts/deploy.sh <dev|prod>}"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$ENV_NAME"

for v in ALERT_EMAIL SQL_ADMIN_LOGIN SQL_ADMIN_OBJECT_ID; do
  if [ "${!v}" = "CHANGE_ME" ]; then
    echo "ERROR: set $v (see infra/parameters/${ENV_NAME}.env or ${ENV_NAME}.local.env)"; exit 1
  fi
done

echo ">> Subscription: $SUBSCRIPTION_ID   Resource group: $RG   Region: $LOCATION"
az group create -n "$RG" -l "$LOCATION" --tags project="$PROJECT" env="$ENV_NAME" owner="$OWNER" ttl="$TTL" -o none

deploy() {  # deploy <name> <template> <param...>
  local name="$1" tpl="$2"; shift 2
  echo; echo "=== WHAT-IF: $name"
  az deployment group what-if -g "$RG" -f "$ROOT/infra/$tpl" --parameters "$@"
  if [ -t 0 ] && [ -z "${CI:-}" ]; then
    read -r -p "Deploy '$name'? [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] || { echo "Stopped."; exit 1; }
  fi
  echo "=== DEPLOY: $name"
  az deployment group create -g "$RG" -n "$name" -f "$ROOT/infra/$tpl" --parameters "$@" \
    --query properties.provisioningState -o tsv
}
out() { az deployment group show -g "$RG" -n "$1" --query "properties.outputs.$2.value" -o tsv; }

deploy policy policy.json environment="$ENV_NAME" allowedLocations="[\"$LOCATION\",\"global\"]"
deploy identity identity.json name="$ID_NAME" location="$LOCATION" tags="$TAGS_JSON"
ID_ID="$(out identity id)"; ID_PRINCIPAL="$(out identity principalId)"; ID_CLIENT="$(out identity clientId)"

deploy monitoring monitoring.json workspaceName="$LAW_NAME" appInsightsName="$AI_NAME" actionGroupName="$AG_NAME" \
  alertEmail="$ALERT_EMAIL" dailyCapGb="$LOG_DAILY_CAP_GB" location="$LOCATION" tags="$TAGS_JSON"
WORKSPACE_ID="$(out monitoring workspaceId)"; AI_CONN="$(out monitoring appInsightsConnectionString)"; AG_ID="$(out monitoring actionGroupId)"

deploy storage storage.json name="$ST_NAME" workspaceId="$WORKSPACE_ID" principalId="$ID_PRINCIPAL" location="$LOCATION" tags="$TAGS_JSON"
BLOB_URL="$(out storage blobEndpoint)"

deploy acr acr.json name="$ACR_NAME" principalId="$ID_PRINCIPAL" location="$LOCATION" tags="$TAGS_JSON"
deploy keyvault keyvault.json name="$KV_NAME" principalId="$ID_PRINCIPAL" secretValue="$AI_CONN" location="$LOCATION" tags="$TAGS_JSON"
SECRET_URI="$(out keyvault secretUri)"

deploy sql sql.json serverName="$SQL_SERVER_NAME" databaseName="$SQL_DB_NAME" aadAdminLogin="$SQL_ADMIN_LOGIN" \
  aadAdminObjectId="$SQL_ADMIN_OBJECT_ID" aadAdminType="$SQL_ADMIN_TYPE" workspaceId="$WORKSPACE_ID" \
  useFreeOffer="$USE_SQL_FREE_OFFER" location="$LOCATION" tags="$TAGS_JSON"
SQL_FQDN="$(out sql serverFqdn)"; SQL_DB_ID="$(out sql databaseId)"

# Keep whatever image is currently running so re-deploying infra never rolls the app back.
IMAGE="$PLACEHOLDER_IMAGE"; PORT=80
if CUR="$(az containerapp show -g "$RG" -n "$APP_NAME" --query 'properties.template.containers[0].image' -o tsv 2>/dev/null)" && [ -n "$CUR" ]; then
  IMAGE="$CUR"
  [ "$IMAGE" != "$PLACEHOLDER_IMAGE" ] && PORT=8000
fi

deploy app app.json environmentName="$CAE_NAME" appName="$APP_NAME" workspaceName="$LAW_NAME" identityId="$ID_ID" \
  identityClientId="$ID_CLIENT" acrName="$ACR_NAME" image="$IMAGE" targetPort="$PORT" sqlServerFqdn="$SQL_FQDN" \
  sqlDatabase="$SQL_DB_NAME" storageAccountUrl="$BLOB_URL" keyVaultSecretUri="$SECRET_URI" enableChaos="$ENABLE_CHAOS" \
  minReplicas="$MIN_REPLICAS" location="$LOCATION" tags="$TAGS_JSON"
APP_ID="$(out app appId)"

deploy alerts alerts.json appName="$APP_NAME" containerAppId="$APP_ID" sqlDatabaseId="$SQL_DB_ID" actionGroupId="$AG_ID" tags="$TAGS_JSON"

echo; echo "Infrastructure ready in $RG."
echo "Next: scripts/post_deploy.sh $ENV_NAME  (SQL access for the app identity), then scripts/release.sh $ENV_NAME <tag>"
