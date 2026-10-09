#!/usr/bin/env bash
# Safe release: push image, create a new revision with 0% traffic, smoke-test that revision
# directly, then shift traffic. On failure traffic stays on the previous revision.
# Usage: scripts/release.sh <dev|prod> <tag>      (IMAGE_LOCAL overrides the local image name)
set -euo pipefail
ENV_NAME="${1:?usage: scripts/release.sh <dev|prod> <tag>}"; TAG="${2:?image tag required}"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" "$ENV_NAME"

IMAGE_LOCAL="${IMAGE_LOCAL:-obsapp:${TAG}}"
IMAGE_REMOTE="${ACR_NAME}.azurecr.io/obsapp:${TAG}"

if ! docker image inspect "$IMAGE_LOCAL" >/dev/null 2>&1; then
  echo ">> Building $IMAGE_LOCAL"; docker build -t "$IMAGE_LOCAL" "$ROOT/app"
fi
az acr login -n "$ACR_NAME"
docker tag "$IMAGE_LOCAL" "$IMAGE_REMOTE"
docker push "$IMAGE_REMOTE"

PREV="$(az containerapp revision list -g "$RG" -n "$APP_NAME" --query "[?properties.trafficWeight==\`100\`].name | [0]" -o tsv || true)"
[ "$PREV" = "None" ] && PREV=""
echo ">> Previous live revision: ${PREV:-<none>}"

az containerapp ingress update -g "$RG" -n "$APP_NAME" --target-port 8000 -o none
SUFFIX="r${TAG}-$(date +%d%H%M%S)"
az containerapp update -g "$RG" -n "$APP_NAME" --image "$IMAGE_REMOTE" --revision-suffix "$SUFFIX" \
  --set-env-vars APP_VERSION="$TAG" -o none
NEW="${APP_NAME}--${SUFFIX}"

# Keep production traffic on the old revision while we test the new one.
if [ -n "$PREV" ]; then
  az containerapp ingress traffic set -g "$RG" -n "$APP_NAME" --revision-weight "${PREV}=100" -o none
fi

NEW_FQDN="$(az containerapp revision show -g "$RG" -n "$APP_NAME" --revision "$NEW" --query properties.fqdn -o tsv)"
echo ">> Smoke-testing new revision: https://$NEW_FQDN"
if "$ROOT/scripts/smoke_test.sh" "https://$NEW_FQDN"; then
  az containerapp ingress traffic set -g "$RG" -n "$APP_NAME" --revision-weight "${NEW}=100" -o none
  echo ">> Released: 100% of traffic now on $NEW"
else
  echo ">> Smoke test FAILED: rolling back (traffic stays on ${PREV:-nothing})"
  az containerapp revision deactivate -g "$RG" -n "$APP_NAME" --revision "$NEW" -o none || true
  exit 1
fi
