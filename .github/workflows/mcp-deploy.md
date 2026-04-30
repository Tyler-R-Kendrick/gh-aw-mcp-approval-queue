---
name: MCP Deploy to Azure APIC
description: Deploys an approved MCP server to the Azure API Center MCP registry when the 'approved' label is added to an mcp-request issue.
on:
  workflow_dispatch:
    inputs:
      issue_number:
        description: "Issue number of the approved MCP request to deploy"
        required: true
  issues:
    types: [labeled]
if: github.event_name == 'workflow_dispatch' || (github.event.label.name == 'approved' && contains(github.event.issue.labels.*.name, 'mcp-request'))
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

You are the MCP deployment agent. When an approved `mcp-request` issue is ready
for deployment, you deploy the MCP server to the Azure API Center registry,
update the issue with the deployment result, and close it on success.

## Step 1: Resolve the target issue

Resolve `issue_number` and `issue_text` using the trigger type:

- If `${{ github.event_name }}` is `issues`, use `${{ github.event.issue.number }}`
  as `issue_number` and `${{ steps.sanitized.outputs.text }}` as `issue_text`.
- If `${{ github.event_name }}` is `workflow_dispatch`, read
  `${{ github.event.inputs.issue_number || '' }}` as `issue_number`.
  It must be a positive integer. Then use the GitHub issues tool to fetch that
  issue and build `issue_text` from its title and body.

If the manual input is missing, invalid, or the issue cannot be loaded, call
`noop` with a brief explanation and stop.

## Step 2: Verify pre-conditions

Read the resolved issue and confirm all of the following:
- Issue has label `mcp-request`
- Issue has label `approved`
- Issue does **not** have label `rejected`
- Issue does **not** have label `deployed`
- Issue is still open

If any condition fails, call `noop` explaining why deployment was skipped and stop.

## Step 3: Verify required secrets

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

## Step 4: Parse deployment parameters

For issue-triggered runs, gh-aw automatically injects a `sanitized` step, so
`${{ steps.sanitized.outputs.text }}` is available. For manual runs, use the
resolved `issue_text` you built from the fetched issue title and body.

From `issue_text`, extract:
- `server_url` — use the "### MCP Endpoint" section when it is present and non-empty; otherwise fall back to the legacy "### Runtime URL" section
- `request_reason` — use the "### Request Reason" section when it is present and non-empty; otherwise fall back to the legacy "### Description" section

Normalize `server_url` before deriving the deployment parameters:
1. Trim surrounding whitespace.
2. If the value is wrapped in a single pair of Markdown delimiters such as
   `<...>`, `(...)`, or `` `...` ``, strip that outer wrapper.
3. If the remaining value is non-empty and has no URI scheme, prepend
   `https://`.
4. Use the normalized value for `server_url`, `server_name`, and the deployment
   command.

Derive `server_name` from `server_url` using this exact rule:
1. Start with the endpoint hostname.
2. If the URL path is not empty or `/`, append the path segments separated by `-`.
3. Exclude query parameters and fragments.
4. Use the resulting readable identifier for display and for `deploy-to-apic.sh`.

Use `request_reason` as the deployment description.

## Step 5: Deploy to Azure API Center

Run the deployment script:

```bash
bash scripts/deploy-to-apic.sh \
  --server-name    "<server_name>"           \
  --server-url     "<server_url>"            \
  --description    "<request_reason>"        \
  --subscription   "$AZURE_SUBSCRIPTION_ID"  \
  --resource-group "$AZURE_RESOURCE_GROUP"   \
  --apic-service   "$AZURE_APIC_SERVICE"
```

Capture stdout and stderr. The script exits 0 on success, non-zero on failure.

## Step 6: Handle the deployment result

When using safe outputs:
- Set `item_number` to `issue_number` for `add_comment` and `add_labels`
- Set `issue_number` to `issue_number` for `close_issue`

### On success (exit code 0)

1. Add label `deployed` to `issue_number`
2. Post comment on `issue_number`:

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

3. Close `issue_number` with comment: `✅ Deployment complete. This MCP server request is resolved.`

### On failure (non-zero exit code)

1. Add label `deployment-failed` to `issue_number`
2. Post comment on `issue_number`:

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

Please review the configuration and re-trigger by rerunning this workflow
manually or by removing and re-adding the `approved` label once the
configuration is fixed.
````

Do **not** close the issue on failure — it requires human intervention.
