# Your step-by-step guide

Follow the parts in order. Every part ends with a **Checkpoint**: do not move on until it is true.
This guide is set up as a **3-day sprint** (see the plan below). Cloud spend if you follow the teardown rules: a few dollars at most.

## The three cost rules (read first)

1. **Budget before resources.** Part 3 creates a budget alert before anything else exists.
2. **Everything in a resource group, always tagged, always deletable.** `scripts/teardown.sh` removes an environment completely.
3. **Nothing runs overnight.** Dev is created and destroyed by the pipeline in about 15 minutes. Prod-like exists only while you capture evidence.

Budgets only *notify*; they do not stop spending. Check **Cost Management → Cost analysis** after every session in the first week.

## The 3-day sprint plan

The scaffold already contains the app, templates, scripts and pipeline, so your time goes into running, fixing and documenting. The main risk is debugging time: the templates were syntax-checked but never deployed to live Azure, so expect a few first-deploy errors.

### What is cut or deferred in the sprint

| Item | Sprint decision |
|---|---|
| Part 5 (template study) | Skim only. Be able to explain identity → roles → app. |
| Part 6 (manual dev deploy) | **Skipped** unless you need it to debug. Go straight to the pipeline. |
| Part 10 (prod-like environment) | **Deferred.** Mention `prod.env` in the README. |
| Part 11 blog post | **Deferred.** Do README + LinkedIn post now, full blog later. |
| Part 12 (stretch goals) | **Deferred.** List them under "What I would improve." |
| Part 9 (rollback demo) | Do it only if time allows. It is quick once the pipeline is green. |

**Kept (this is what carries the hiring value):** budget and guardrails, pipeline with Trivy and `what-if`, managed identity, the alert-firing demo, the rollback demo (if time), and a README with screenshots and real cost numbers.

### Before you start the clock (tonight, about 30 minutes)

- [ ] Parts 1 and 2 done: tools installed, `az login` works, providers registered (this can take minutes), repo pushed to GitHub.
- [ ] Docker Desktop running; WSL2 set up if you are on Windows.
- [ ] Budget deployed (Part 3).

### Day 1: Foundation and local (about 5 to 6 hours)

- [ ] Part 4: local Docker run, tests and linter pass
- [ ] Part 5 (skim only): set `infra/parameters/dev.local.env`
- [ ] Part 7 setup: service principal, federated credentials, GitHub environments, secrets
- [ ] Trigger the **first pipeline run before you stop**. If it fails, you start Day 2 with the error already in hand.

### Day 2: Get it green, then break it (about 6 to 7 hours)

- [ ] Morning: fix pipeline and template errors until one full run passes (what-if → deploy → SQL grant → release → smoke test → teardown). Screenshot the green graph.
- [ ] Afternoon: Part 8. Run with `keep = true`, do the chaos demo, capture the alert, dashboard and cost-cap screenshots, then tear down.
- [ ] If time remains: Part 9 (rollback demo).

### Day 3: Evidence and presentation (about 4 to 5 hours)

- [ ] Fill in `README.md` with screenshots, diagram and real numbers from Cost analysis
- [ ] Update `docs/cost-log.md`
- [ ] Record the 2 to 3 minute demo video
- [ ] Write the LinkedIn post and your resume bullets (Part 11, steps 2, 4 and 5)
- [ ] Run `scripts/teardown.sh` and the end-of-session checklist at the bottom

### Speed tips and risks

- Use `keep = false` for most runs so nothing idles while you debug.
- Paste the exact failing log lines when you ask for help. Fixing a template or script from the error is faster than reading docs.
- **Likely first-deploy failures:** the SQL free-offer API version and the alert metric names (see the troubleshooting table). If the free-offer property keeps failing, set `USE_SQL_FREE_OFFER="false"`, move on, and tear down quickly to limit cost.
- **Protect your AZ-400 revision time.** This project overlaps with pipelines, IaC and monitoring, so Day 2 doubles as exam practice, but do not let debugging consume your revision.

---

## What is in this folder

| Path | Purpose |
|---|---|
| `app/` | Flask task-tracker API, multi-stage `Dockerfile`, unit tests |
| `docker-compose.yml` | Local stack: app + SQL Server + Azurite (storage emulator), $0 |
| `infra/*.json` | ARM modules: identity, monitoring, storage, acr, keyvault, sql, app, alerts, policy, budget |
| `infra/parameters/dev.env`, `prod.env` | Per-environment settings |
| `scripts/` | `deploy`, `post_deploy`, `release`, `smoke_test`, `chaos`, `teardown` |
| `.github/workflows/ci-cd.yml` | Pipeline: test → build+scan → deploy → release → smoke test → teardown |
| `docs/` | Architecture diagram, cost log, evidence checklist, blog outline |

**Windows users:** the scripts are Bash. Use **WSL2 (Ubuntu)** with Docker Desktop's WSL integration. Run every command below inside WSL.

---

## Part 1: Prepare your machine

Install: Azure CLI, Docker Desktop, Git, Python 3.12, VS Code, and a GitHub account.

```bash
az login
az account show --query "{name:name, id:id}" -o table      # confirm it is your PERSONAL subscription
az extension add --name containerapp --upgrade -y

# Register the resource providers once (some may already be registered)
for p in Microsoft.App Microsoft.ContainerRegistry Microsoft.Sql Microsoft.OperationalInsights \
         Microsoft.Insights Microsoft.KeyVault Microsoft.Storage Microsoft.ManagedIdentity \
         Microsoft.Consumption Microsoft.PolicyInsights Microsoft.Authorization; do
  az provider register --namespace $p
done
az provider show -n Microsoft.App --query registrationState -o tsv   # wait for "Registered"
```

Optional but useful for Part 6 (running the SQL grant script from your own machine): install **ODBC Driver 18 for SQL Server** and `pip install pyodbc azure-identity`.

**Checkpoint:** `az account show` shows the right subscription and Microsoft.App is `Registered`.

## Part 2: Create the GitHub repository

```bash
cd azure-observable-app
git init -b main
git add . && git commit -m "Initial scaffold"
# Create an empty PUBLIC repo on github.com (public = free Actions minutes), then:
git remote add origin https://github.com/<YOUR_USER>/azure-observable-app.git
git push -u origin main
```

The first pipeline run will fail because secrets do not exist yet. That is expected. Do not worry about it.

**Checkpoint:** the code is on GitHub and `.env` / `*.local.env` are NOT in the repo.

## Part 3: Cost guardrails first

```bash
az deployment sub create --location westeurope \
  --template-file infra/budget.json \
  --parameters startDate=$(date +%Y-%m-01) amount=10 contactEmails='["you@example.com"]'
```

Verify in the portal: **Cost Management → Budgets**. You should see four alerts (50%, 80%, 100% actual, 100% forecast). Budget emails can lag by many hours.

Also (optional, 2 minutes): **Subscriptions → your subscription → Cost alerts → Add a "Cost anomaly" alert**.

**Checkpoint:** the budget shows in the portal with your email.

## Part 4: Run it locally with Docker (free)

```bash
cp .env.example .env              # change the SA password if you like
docker compose up --build
```

In another terminal:

```bash
curl localhost:8000/health
curl localhost:8000/ready
curl -X POST localhost:8000/tasks -H 'Content-Type: application/json' -d '{"title":"first task"}'
curl localhost:8000/tasks
echo "hello" > /tmp/a.txt && curl -F file=@/tmp/a.txt localhost:8000/uploads
curl localhost:8000/uploads
```

Run the unit tests and the linter:

```bash
cd app && pip install -r requirements-dev.txt && ruff check . && pytest -q && cd ..
docker compose down -v
```

Learning goals: read `app/Dockerfile` and be able to explain **why it is multi-stage**, why the process runs as a **non-root user**, and why `/health` (liveness) and `/ready` (dependencies) are separate.

**Checkpoint:** tasks and uploads work locally; tests pass.

## Part 5: Read the ARM templates, then configure dev

> **Sprint mode:** skim the templates (about 20 minutes) and focus on configuring `dev.local.env`.

Open each file in `infra/` and read it in this order: `identity` → `monitoring` → `storage` → `acr` → `keyvault` → `sql` → `app` → `alerts` → `policy` → `budget`. Be ready to explain:

- Why a **user-assigned managed identity** is created first (so roles can be granted *before* the app exists).
- How **no passwords** appear anywhere: ACR pull, Key Vault, Storage and SQL all use the identity.
- Which settings are **cost guardrails** (`dailyCapGb`, SQL free offer + auto-pause, Basic ACR, scale to zero, no private endpoints).

Get your identity details and set them locally (this file is git-ignored):

```bash
az ad signed-in-user show --query "{upn:userPrincipalName, oid:id}" -o tsv
cat > infra/parameters/dev.local.env <<'EOT'
ALERT_EMAIL="you@example.com"
SQL_ADMIN_LOGIN="<your UPN from above>"
SQL_ADMIN_OBJECT_ID="<your oid from above>"
SQL_ADMIN_TYPE="User"
EOT
```

Pick `LOCATION` in `dev.env` (default `westeurope`). If a service is unavailable there, choose another region and use it consistently.

**Checkpoint:** you can explain the identity → role assignment → app flow in your own words.

## Part 6: First manual deployment of dev

> **Sprint mode: skip this part** and go to Part 7 unless you need a manual deploy to debug. The pipeline runs the same scripts.

```bash
./scripts/deploy.sh dev
```

For each module you will see a **what-if** preview, then a prompt. Read the preview. This is the habit the pipeline will automate. Takes about 10 to 15 minutes.

Then grant the app identity access to the database and ship the first image:

```bash
./scripts/post_deploy.sh dev          # creates the table + contained DB user for the identity
./scripts/release.sh dev v1           # builds, pushes to ACR, new revision, smoke test, traffic shift
```

(No local ODBC driver? Skip `post_deploy.sh` for now and let the pipeline do it in Part 7. Portal alternative: SQL database → Query editor, sign in with Entra, and run `sql/schema.sql` plus `CREATE USER [id-obsapp-dev] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [id-obsapp-dev]; ALTER ROLE db_datawriter ADD MEMBER [id-obsapp-dev];`)

Find the URL and test it:

```bash
source scripts/lib.sh dev
az containerapp show -g $RG -n $APP_NAME --query properties.configuration.ingress.fqdn -o tsv
```

Look around in the portal: resource group, tags, Container App → Revisions, Application Insights → Live metrics, SQL database → Overview (free offer status).

Now tear it down and confirm the cost impact:

```bash
./scripts/teardown.sh dev
```

**Checkpoint:** the app answered from Azure, the smoke test passed, and the resource group is gone. Add a line to `docs/cost-log.md`.

## Part 7: Build the pipeline

Create a service principal for GitHub with passwordless OIDC login:

```bash
SUB=$(az account show --query id -o tsv)
TENANT=$(az account show --query tenantId -o tsv)
APP_ID=$(az ad app create --display-name "gh-obsapp-deployer" --query appId -o tsv)
az ad sp create --id $APP_ID
SP_OBJ=$(az ad sp show --id $APP_ID --query id -o tsv)

# Contributor creates resources; User Access Administrator lets templates assign roles;
# Resource Policy Contributor lets it assign the policy.
for role in "Contributor" "User Access Administrator" "Resource Policy Contributor"; do
  az role assignment create --assignee-object-id $SP_OBJ --assignee-principal-type ServicePrincipal \
    --role "$role" --scope /subscriptions/$SUB
done

REPO="<YOUR_USER>/azure-observable-app"
for envname in dev prod; do
  az ad app federated-credential create --id $APP_ID --parameters "{
    \"name\": \"gh-env-$envname\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$REPO:environment:$envname\",
    \"audiences\": [\"api://AzureADTokenExchange\"]}"
done
echo "AZURE_CLIENT_ID=$APP_ID  AZURE_TENANT_ID=$TENANT  AZURE_SUBSCRIPTION_ID=$SUB"
echo "SQL_ADMIN_LOGIN=gh-obsapp-deployer  SQL_ADMIN_OBJECT_ID=$SP_OBJ"
```

(Trade-off to mention in your write-up: on a personal subscription this broad scope is acceptable; in a company you would scope it to a resource group and use a custom role.)

In GitHub: **Settings → Environments** → create `dev` and `prod`. On `prod`, add yourself as **Required reviewer** (this is your manual approval gate). Then **Settings → Secrets and variables → Actions → Secrets**, add:
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ALERT_EMAIL`, `SQL_ADMIN_LOGIN`, `SQL_ADMIN_OBJECT_ID`.

Run it: **Actions → ci-cd → Run workflow → dev**. Watch each stage. Expected: test → build-scan → deploy (what-if, deploy, SQL grant, release, smoke test) → teardown.

Pipeline failures you may hit: see the troubleshooting table at the end.

**Checkpoint:** a green run, and afterwards `az group list -o table` shows no leftover `rg-obsapp-dev`. Screenshot the green pipeline graph into `docs/evidence/`.

## Part 8: Monitoring and the "break it on purpose" demo

This is the part recruiters remember. Budget about 1 hour of Azure time, then tear down.

1. **Run workflow → dev → keep = true.** The environment stays up.
2. In `dev.env` the app scales to zero. For the restart demo set `MIN_REPLICAS="1"` in `dev.local.env` and re-run `./scripts/deploy.sh dev` (the running image is preserved).
3. Get the URL (Part 6), then break things:
   ```bash
   ./scripts/chaos.sh https://<fqdn> error     # 60 failing requests -> HTTP 5xx alert
   ./scripts/chaos.sh https://<fqdn> crash     # kills the container -> restart alert
   ```
4. Wait 5 to 10 minutes. Check your email and **Monitor → Alerts**. Screenshot the fired alert and the email.
5. Build a view: **Application Insights → Workbooks** (or pin tiles to a dashboard): requests, failed requests, response time, plus a Log Analytics query on `ContainerAppConsoleLogs_CL`. Screenshot it.
6. Save screenshots in `docs/evidence/`, then `./scripts/teardown.sh dev`.

Also look at **Log Analytics → Usage and estimated costs** and confirm the daily cap is set. That screenshot supports your cost story.

**Checkpoint:** screenshots of a fired alert, the dashboard, and the cost cap are saved.

## Part 9: Release safety and rollback demo

> **Sprint mode:** optional, do it on Day 2 if time allows.

1. Run the workflow with **keep = true** so a good revision (`v-good`) is live.
2. Make the app unhealthy on purpose: in `app/main.py` change `/ready` to always return `503`, commit, and push to `main`.
3. Run the workflow again (with keep = true). The release script creates a new revision at 0% traffic, the smoke test **fails**, the revision is deactivated, and **traffic stays on the good revision**. Screenshot the red job and the Revisions blade showing 100% on the old revision.
4. Revert the commit, run once more with keep = false to tear down.

**Checkpoint:** you can explain the difference between this (revision traffic splitting on Container Apps) and a deployment-slot swap on App Service, and why you chose it (cost).

## Part 10: Production-like environment (optional, brief)

> **Sprint mode: deferred.** Do this after the 3 days.

Run the workflow with **environment = prod**. The `prod` environment pauses for your approval, then deploys with one warm replica and chaos disabled. Capture one dashboard screenshot, then run `./scripts/teardown.sh prod`. Never leave it running.

## Part 11: Make it hire-worthy

> **Sprint mode:** do steps 1, 2, 4 and 5 now. Step 3 (blog post) can come after the 3 days; a short LinkedIn post is enough for now.

1. **README:** replace placeholders in `README.md` (architecture diagram, pipeline diagram, evidence screenshots, real cost numbers from Cost analysis, "What I would improve").
2. **Record a 2 to 3 minute screen video**: local compose → pipeline run → alert firing → rollback. Link it at the top of the README.
3. **Write the blog post** using `docs/blog-outline.md`, then a short LinkedIn post linking to the repo.
4. **Resume bullets** (adapt with your real numbers):
   - Built an end-to-end Azure delivery pipeline (ARM, Docker, GitHub Actions, OIDC) that provisions, tests, scans, releases and tears down a containerized app with Azure SQL, Storage and Key Vault.
   - Implemented passwordless access with managed identities, Trivy image scanning, `what-if` change previews and automated rollback on failed smoke tests.
   - Added monitoring (Log Analytics, App Insights, metric alerts) and cost guardrails (budgets, policy, ephemeral environments); kept the stack under $X/month.
5. **Interview talking points:** why ephemeral environments, why managed identity over connection strings, what `what-if` prevents, how rollback works, what you would change for production (private endpoints, Premium ACR, higher SQL tier, Bicep modules, approval policies).

## Part 12: Stretch goals (in this order)

> **Sprint mode: deferred.** List these under "What I would improve" in the README.

1. Rewrite the templates in **Bicep** with real modules and compare it with this ARM version in your write-up. A single orchestrating template removes the need for the output-passing in `deploy.sh`.
2. Add a scheduled workflow that exports a SQL backup (`.bacpac`) to the storage account.
3. Add a "Require a tag" policy and a cost-by-tag screenshot from Cost analysis.
4. Add liveness and readiness probes to the Container App.

---

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `what-if` rejects the SQL `useFreeLimit` property | The preview API version differs by region/CLI. Update `apiVersion` in `infra/sql.json` (the Azure docs for `Microsoft.Sql/servers/databases` list current versions), or set `USE_SQL_FREE_OFFER="false"` temporarily and accept serverless costs for a short run. |
| Metric alert deployment fails on a metric or dimension name | Open the Container App → Metrics blade, confirm the exact metric name (`Requests`, `RestartCount`) and dimension (`statusCodeCategory`), and adjust `infra/alerts.json`. |
| Role-assignment or Key Vault reference fails on first deploy | Role propagation can lag a minute. Re-run `./scripts/deploy.sh <env>`; it is idempotent. |
| `AuthorizationFailed` creating a role assignment or policy | The deploying identity lacks User Access Administrator / Resource Policy Contributor (see Part 7). |
| `post_deploy.sh` times out connecting | Firewall rule propagation or serverless resume; the script retries about 3 minutes. Re-run it. |
| Smoke test says `/ready` fails | The DB user is missing: run `post_deploy.sh`. Check Container App → Log stream for the error. |
| Name already exists (Key Vault, workspace) | Run `./scripts/teardown.sh <env>` which purges soft-deleted vaults and force-deletes the workspace. |
| Image pull fails | The identity needs AcrPull (created by `acr.json`); confirm the ACR name and that the image was pushed. |
| Trivy fails the build | Read the finding. Bump the base image or a pinned package. Only suppress with an explained `.trivyignore` entry. |

## End-of-session safety checklist

```bash
az group list --query "[?starts_with(name,'rg-obsapp')].name" -o tsv    # should print nothing unless you meant it
az keyvault list-deleted -o table                                      # purge leftovers if any
```
Then look at Cost analysis (group by Resource group / Tag `project`) and note the number in `docs/cost-log.md`.
