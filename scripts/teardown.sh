#!/usr/bin/env bash
# Deletes the environment and purges soft-deleted leftovers so the names can be reused.
# Usage: scripts/teardown.sh <dev|prod>
set -euo pipefail
ENV_NAME="${1:?usage: scripts/teardown.sh <dev|prod>}"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$ENV_NAME"

if [ "$(az group exists -n "$RG")" != "true" ]; then echo "$RG does not exist. Nothing to do."; exit 0; fi
if [ -t 0 ] && [ -z "${CI:-}" ]; then
  read -r -p "DELETE resource group $RG and everything in it? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

echo ">> Force-deleting Log Analytics workspace (skips the 14-day soft-delete)"
az monitor log-analytics workspace delete -g "$RG" -n "$LAW_NAME" --force true --yes -o none || true
echo ">> Deleting resource group $RG"
az group delete -n "$RG" --yes -o none
echo ">> Purging soft-deleted Key Vault $KV_NAME"
az keyvault purge --name "$KV_NAME" --location "$LOCATION" -o none || true
echo "Done. Remaining resource groups for this project:"
az group list --query "[?starts_with(name,'rg-${PROJECT}')].name" -o tsv
