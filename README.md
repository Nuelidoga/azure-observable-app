# Observable Containerized App on Azure (ARM + Docker + CI/CD)

> **Demo video:** _link here_ · **Blog post:** _link here_

A small task-tracker API deployed to Azure entirely from code: modular ARM templates, a multi-stage
Docker image, a GitHub Actions pipeline with image scanning and `what-if` previews, passwordless access
via managed identity, monitoring with alerts, safe releases with automatic rollback, and strict cost
controls so the whole thing runs on a personal subscription for a few dollars a month.

## Architecture

_Paste the rendered diagram from `docs/architecture.md` or an exported image here._

| Layer | Service | Cost decision |
|---|---|---|
| Hosting | Azure Container Apps (Consumption) | Scales to zero; revisions replace paid deployment slots |
| Registry | Azure Container Registry (Basic) | Lives only as long as the environment |
| Database | Azure SQL Database (free offer, serverless auto-pause) | Entra-only auth, no passwords |
| Storage | Storage account (Standard LRS) | Blob uploads; shared-key access disabled |
| Secrets | Key Vault (RBAC) | App Insights connection string, read via managed identity |
| Monitoring | Log Analytics (daily cap), App Insights, metric alerts | 3 cheap metric alerts, 30-day retention |
| Governance | Budget alerts, Azure Policy (allowed regions), mandatory tags | Guardrails deployed first |

## Pipeline

`lint + unit tests` → `docker build + Trivy scan` → `ARM what-if` → `deploy` → `SQL access grant` →
`new revision at 0% traffic` → `smoke test` → `shift traffic (or roll back)` → `teardown (dev)`

## Run locally

```bash
cp .env.example .env && docker compose up --build
curl localhost:8000/health
```

## Deploy to Azure

See [GUIDE.md](GUIDE.md). Short version: set `infra/parameters/dev.local.env`, run `scripts/deploy.sh dev`, then `scripts/release.sh dev v1`, and `scripts/teardown.sh dev` when finished.

## Evidence

_Add screenshots from `docs/evidence/`: green pipeline, fired alert, dashboard, rollback, cost analysis._

## Cost

_Paste your real Cost analysis numbers (see `docs/cost-log.md`)._

## Key decisions and trade-offs

- **Container Apps revisions instead of App Service slots**: slots require a paid tier; revisions give blue/green and rollback for free.
- **Ephemeral environments**: dev is created and destroyed per pipeline run.
- **Managed identity everywhere**: no passwords or keys in the repo or the pipeline.
- **ARM modules deployed in order by a script**: ARM has no native module system without hosting templates; Bicep would remove this limitation.

## What I would improve for production

- Production-like environment with manual approval (workflow supports it; deferred)
- Bicep rewrite, scheduled SQL backups, tag-enforcement policy

- Private endpoints and VNet integration; SQL zone redundancy and a paid tier
- Premium ACR with geo-replication and content trust
- Longer log retention, Defender for Cloud, WAF in front of the app
- Liveness/readiness probes, autoscale tuning, canary traffic percentages
- Bicep modules and environment-scoped deployment stacks
