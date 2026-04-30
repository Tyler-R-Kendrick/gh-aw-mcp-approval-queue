---
name: MCP Deploy to Azure APIC
description: Deploys an approved MCP server to the Azure API Center MCP registry when the 'approved' label is added to an mcp-request issue.
on:
  issues:
    types: [labeled]
if: github.event.label.name == 'approved' && contains(github.event.issue.labels.*.name, 'mcp-request')
permissions:
  contents: read
  issues: read
secrets:
  AZURE_CLIENT_ID:
    value: ${{ secrets.AZURE_CLIENT_ID }}
    description: "Azure service principal application (client) ID"
  AZURE_CLIENT_SECRET:
    value: ${{ secrets.AZURE_CLIENT_SECRET }}
    description: "Azure service principal client secret"
  AZURE_TENANT_ID:
    value: ${{ secrets.AZURE_TENANT_ID }}
    description: "Azure Active Directory tenant ID"
  AZURE_SUBSCRIPTION_ID:
    value: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    description: "Target Azure subscription ID"
  AZURE_RESOURCE_GROUP:
    value: ${{ secrets.AZURE_RESOURCE_GROUP }}
    description: "Resource group containing the API Center service"
  AZURE_APIC_SERVICE:
    value: ${{ secrets.AZURE_APIC_SERVICE }}
    description: "Name of the Azure API Center service"
tools:
  bash:
    - "bash scripts/deploy-to-apic.sh *"
    - "az *"
    - "cat *"
    - "jq *"
network:
  allowed:
    - defaults
    - management.azure.com
    - login.microsoftonline.com
safe-outputs:
  add-labels:
    max: 2
  add-comment:
    max: 2
  close-issue:
    max: 1
timeout-minutes: 15
---

# MCP Deploy to Azure APIC

You are the MCP deployment agent. When the `approved` label is added to an
`mcp-request` issue, you deploy the MCP server to the Azure API Center registry,
update the issue with the deployment result, and close it on success.

## Step 1: Verify pre-conditions

Read the issue and confirm all of the following:
- Issue has label `mcp-request`
- Issue has label `approved`
- Issue does **not** have label `rejected`
- Issue does **not** have label `deployed`

If any condition fails, call `noop` explaining why deployment was skipped and stop.

## Step 2: Verify required secrets

Confirm that each of these secrets is non-empty (they are injected as environment
variables with the same names):
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_RESOURCE_GROUP`
- `AZURE_APIC_SERVICE`

If any required secret is missing, post a comment explaining which secrets are
missing and what the repository admin should configure, then stop without closing
the issue.

## Step 3: Parse deployment parameters

gh-aw automatically injects a `sanitized` step for all issue-triggered workflows,
so `${{ steps.sanitized.outputs.text }}` is always available and contains the
issue title and body with security-safe sanitization applied.

From `${{ steps.sanitized.outputs.text }}`, extract:
- `server_name` — from "### Server Name" section
- `server_url` — from "### Runtime URL" section
- `description` — from "### Description" section
- `owner_team` — from "### Owning Team / Contact" section

## Step 4: Deploy to Azure API Center

Run the deployment script:

```bash
bash scripts/deploy-to-apic.sh \
  --server-name    "<server_name>"           \
  --server-url     "<server_url>"            \
  --description    "<description>"           \
  --subscription   "$AZURE_SUBSCRIPTION_ID"  \
  --resource-group "$AZURE_RESOURCE_GROUP"   \
  --apic-service   "$AZURE_APIC_SERVICE"
```

Capture stdout and stderr. The script exits 0 on success, non-zero on failure.

## Step 5: Handle the deployment result

### On success (exit code 0)

1. Add label `deployed`
2. Post comment:

```markdown
## 🚀 Deployment Successful

**MCP Server:** <server_name>
**Runtime URL:** <server_url>
**Registry:** Azure API Center (`<AZURE_APIC_SERVICE>`)
**Resource Group:** `<AZURE_RESOURCE_GROUP>`

Your MCP server is now registered in the organization's MCP registry and
available for discovery by AI agents.

---
*Workflow run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}*
```

3. Close the issue with comment: `✅ Deployment complete. This MCP server request is resolved.`

### On failure (non-zero exit code)

1. Add label `deployment-failed`
2. Post comment:

````markdown
## ❌ Deployment Failed

The deployment to Azure API Center failed. Error output:

```
<error output here>
```

**Common causes:**
- Missing or incorrect Azure credentials (check repository secrets)
- APIC service `<AZURE_APIC_SERVICE>` does not exist in the subscription
- Service principal lacks `Contributor` access to `<AZURE_RESOURCE_GROUP>`

Please review the configuration and re-trigger by removing and re-adding the
`approved` label, or contact <owner_team> for assistance.
````

Do **not** close the issue on failure — it requires human intervention.
