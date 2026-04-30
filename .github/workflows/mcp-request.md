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
steps:
  - name: Extract MCP request payload
    id: request_payload
    shell: bash
    env:
      INPUT_SERVER_URL: ${{ github.event.inputs.server_url }}
      INPUT_REQUEST_REASON: ${{ github.event.inputs.request_reason }}
    run: |
      python3 - <<'PY'
      import json
      import os
      from pathlib import Path
      from urllib.parse import urlparse

      def cleaned(value: object) -> str:
          return value.strip() if isinstance(value, str) else ""

      event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
      client_payload = event.get("client_payload") or {}

      server_url = cleaned(os.environ.get("INPUT_SERVER_URL")) or cleaned(client_payload.get("server_url"))
      request_reason = (
          cleaned(os.environ.get("INPUT_REQUEST_REASON"))
          or cleaned(client_payload.get("request_reason"))
          or "No request reason provided — please update this issue."
      )

      issue_title = "[MCP Request]"
      if server_url:
          parsed = urlparse(server_url)
          identifier_parts = [cleaned(parsed.hostname), *[segment for segment in parsed.path.split("/") if segment]]
          server_identifier = "-".join(part for part in identifier_parts if part)
          if server_identifier:
              issue_title = f"[MCP Request] {server_identifier}"

      with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as handle:
          for key, value in {
              "server_url": server_url,
              "request_reason": request_reason,
              "issue_title": issue_title,
          }.items():
              handle.write(f"{key}<<__GH_AW_EOF__\n{value}\n__GH_AW_EOF__\n")
      PY
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

The workflow runtime has already expanded the trigger payload into these values:

- `server_url`: `${{ steps.request_payload.outputs.server_url }}`
- `request_reason`: `${{ steps.request_payload.outputs.request_reason }}`
- `issue_title`: `${{ steps.request_payload.outputs.issue_title }}`

Use those exact values. Trim only surrounding whitespace. Only use the defaults
below when a field is genuinely missing or blank after trimming:

| Field | Default |
|-------|---------|
| `server_url` | `""` (empty — must be supplied by the caller) |
| `request_reason` | `"No request reason provided — please update this issue."` |
| `issue_title` | `"[MCP Request]"` |

## Step 2: Create the issue

Use the `create-issue` safe output with:

- **Title**: `<issue_title>`
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
