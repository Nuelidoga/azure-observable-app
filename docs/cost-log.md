# Cost log

Fill this in after every Azure session. The real numbers go in the README.

| Date | What I ran | How long | Cost analysis total (to date) | Notes |
|---|---|---|---|---|
| | first manual dev deploy | | | |
| | pipeline run (dev, ephemeral) | | | |
| | monitoring demo (keep = true) | | | |

## Estimate (verify in the Azure Pricing Calculator)

- ACR Basic: billed per day while it exists
- Container Apps: free monthly grant covers light use; scale to zero
- SQL: free offer allowance; auto-pause when exhausted
- Log Analytics: first 5 GB/month free; daily cap set to 0.5 GB
- Storage, Key Vault, metric alerts: pennies
