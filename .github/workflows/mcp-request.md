---
name: MCP Request Intake
description: Creates a new GitHub issue from the MCP Server Request template when triggered by webhook (repository_dispatch) or manual invocation (workflow_dispatch).
on:
  workflow_dispatch:
    inputs:
      server_url:
        description: "Public HTTPS MCP endpoint"
        required: true
      request_reason:
        description: "Why this MCP server should be reviewed"
        required: true
  repository_dispatch:
    types: [mcp-request]
permissions:
  contents: read
  issues: read
safe-outputs:
  create-issue:
    max: 1
    labels: [mcp-request, pending-review]
  add-comment:
    max: 2
tools:
  github:
    toolsets: [issues]
---

# MCP Request Intake

You are an MCP request intake agent. Your job is to create a well-formed GitHub
issue so the MCP review pipeline can process the submission.

## Step 1: Extract payload

Read the trigger payload to extract these fields. For `workflow_dispatch`, read
from `github.event.inputs`. For `repository_dispatch`, read from
`github.event.client_payload`. Copy the provided values exactly, trimming only
surrounding whitespace. Only use the defaults below when a field is genuinely
missing or blank:

| Field | Default |
|-------|---------|
| `server_url` | `""` (empty — must be supplied by the caller) |
| `request_reason` | `"No request reason provided — please update this issue."` |

## Step 2: Create the issue

Use the `create-issue` safe output with:

- **Title**: `[MCP Request] <server_identifier>` where `server_identifier` is the
  hostname from `server_url` (do not include query parameters)
- **Labels**: `mcp-request`, `pending-review`
- **Body** (use this exact Markdown structure):

```
## MCP Server Registration Request

### MCP Endpoint
<server_url>

### Request Reason
<request_reason>

---
*This issue was automatically created by the MCP request intake workflow.*
```

## Step 3: Welcome comment

After creating the issue, post a comment on it:

```
👋 Your MCP server request has been received!

**Next steps:**
- Automated security and semantic scans will begin shortly
- You will be notified of the results in this issue
- Expected review time: ~10 minutes

If you need to update any information, please edit the issue body directly.
```

## Error handling

If `server_url` is empty, still create the issue (so the requester has a ticket to
update) but add a comment warning:
```
⚠️ No MCP endpoint was provided. Please update this issue with a valid HTTPS URL
before the automated scan begins.
```

If `server_url` is provided but does not start with `https://`, create the issue
but add a comment warning:
```
⚠️ The MCP endpoint does not start with `https://`. Please update the issue with a
valid HTTPS URL before the automated scan begins.
```
