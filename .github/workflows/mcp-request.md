---
name: MCP Request Intake
description: Creates a new GitHub issue from the MCP Server Request template when triggered by webhook (repository_dispatch) or manual invocation (workflow_dispatch).
on:
  workflow_dispatch:
    inputs:
      server_name:
        description: "MCP server name"
        required: false
        default: ""
      server_url:
        description: "MCP server runtime URL (HTTPS)"
        required: false
        default: ""
      description:
        description: "What the MCP server does"
        required: false
        default: ""
      tools_overview:
        description: "Comma-separated list of tools the server exposes"
        required: false
        default: ""
      owner_team:
        description: "GitHub team or @username responsible for the server"
        required: false
        default: ""
      data_classification:
        description: "Data classification (Public/Internal/Confidential/Restricted)"
        required: false
        default: "Internal"
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
    max: 1
tools:
  github:
    toolsets: [default]
---

# MCP Request Intake

You are an MCP request intake agent. Your job is to create a well-formed GitHub
issue so the MCP review pipeline can process the submission.

## Step 1: Extract payload

Read the trigger payload to extract these fields. For `workflow_dispatch`, read
from `github.event.inputs`. For `repository_dispatch`, read from
`github.event.client_payload`. Use the following defaults for any missing field:

| Field | Default |
|-------|---------|
| `server_name` | `"Unknown MCP Server"` |
| `server_url` | `"https://PLACEHOLDER.example.com/mcp"` |
| `description` | `"No description provided — please update this issue."` |
| `tools_overview` | `"Not provided — please list your MCP tools."` |
| `owner_team` | `"@unknown"` |
| `data_classification` | `"Internal"` |

## Step 2: Create the issue

Use the `create_issue` safe output with:

- **Title**: `[MCP Request] <server_name>`
- **Labels**: `mcp-request`, `pending-review`
- **Body** (use this exact Markdown structure):

```
## MCP Server Registration Request

### Server Name
<server_name>

### Runtime URL
<server_url>

### Description
<description>

### Tools Overview
<tools_overview>

### Owning Team / Contact
<owner_team>

### Data Classification
<data_classification>

### Security Checklist
- [x] The server does not log or store raw user prompts
- [x] The server uses HTTPS/TLS for all transport
- [x] Authentication is required to invoke tools
- [x] No credentials, secrets, or tokens are hardcoded
- [x] The server has been tested locally against the MCP specification

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

If `server_url` is provided but does not start with `https://`, still create the
issue but add a comment warning:
```
⚠️ The Runtime URL does not start with `https://`. Please update the issue with a
valid HTTPS URL before the automated scan begins.
```
