---
name: gh-aw
description: Install and use GitHub Agentic Workflows (gh-aw) to create, compile, run, debug, and manage AI-powered workflows written in Markdown. Use when asked to create a new agentic workflow, compile a workflow to GitHub Actions YAML, trigger or monitor a workflow run, or work with any file under .github/workflows/*.md.
---

# gh-aw — GitHub Agentic Workflows

GitHub Agentic Workflows (`gh-aw`) is a GitHub CLI extension that lets you write
AI-powered automation in natural language Markdown, compiled to GitHub Actions YAML
and executed by an AI engine (Copilot, Claude, Codex, Gemini, or a custom engine).

## When to Use

- Creating or modifying a workflow file (`.github/workflows/<name>.md`)
- Compiling a workflow to its lock file (`.github/workflows/<name>.lock.yml`)
- Running, debugging, or auditing a workflow run
- Upgrading workflows to a newer gh-aw version
- Adding or updating shared workflow components under `.github/workflows/shared/`
- Any task that involves the `gh aw` CLI commands

## When Not to Use

- Writing standard GitHub Actions YAML that has no AI/agent step (use plain Actions)
- Modifying `.lock.yml` files directly (always edit the `.md` source and recompile)
- Tasks involving `gh skill` or agent skills in `.github/skills/` (separate concept)

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Workflow name | Yes | Short kebab-case identifier, e.g. `issue-triage` |
| Trigger description | Yes | What event should start the workflow |
| Task description | Yes | What the AI agent should do when triggered |
| Engine | No | `copilot` (default), `claude`, `codex`, `gemini` |

## Workflow

### Step 1: Install gh-aw

Check whether the extension is installed:

```bash
gh aw version
```

If missing, install it:

```bash
curl -sL https://raw.githubusercontent.com/github/gh-aw/main/install-gh-aw.sh | bash
```

Upgrade to the latest version if already installed:

```bash
gh extension upgrade aw
```

### Step 2: Read the canonical reference

Before authoring any workflow, always consult the latest schema:

```
https://raw.githubusercontent.com/github/gh-aw/main/.github/aw/github-agentic-workflows.md
```

### Step 3: Author the workflow file

Create `.github/workflows/<workflow-name>.md` with YAML frontmatter followed by a
Markdown body containing the AI agent's natural-language instructions.

**Minimal template:**

```markdown
---
name: My Workflow
description: One-sentence description of what this workflow does.
on:
  issues:
    types: [opened]
permissions:
  contents: read
  issues: read
safe-outputs:
  add-comment:
    max: 3
---

# My Workflow

Describe what the agent should do here in plain English.

Use GitHub context expressions like ${{ github.event.issue.number }}.
```

**Critical security rules (always enforce):**

- Agent job permissions must be **read-only**; never add `write` permissions.
- All GitHub write operations (comments, labels, PRs) must go through `safe-outputs`.
- Do **not** use `gh issue edit` or similar CLI calls directly — use `safe-outputs` instead.
- Constrain `network:` to the minimum required ecosystems or domains.

**Key frontmatter fields:**

| Field | Purpose |
|-------|---------|
| `on:` | Trigger(s) — required |
| `permissions:` | GitHub token scopes — read-only only |
| `engine:` | AI engine config (default: copilot) |
| `tools:` | Built-in tools: `github:`, `web-fetch`, `bash:`, `playwright` |
| `mcp-servers:` | Custom MCP server definitions |
| `safe-outputs:` | Approved write operations with rate limits |
| `network:` | Firewall allow-list (`defaults`, `github`, `node`, `python`, …) |
| `imports:` | Shared components in `owner/repo/path@ref` format |
| `steps:` | Pre-agent deterministic setup steps |
| `timeout-minutes:` | Per-step timeout (default: 20) |

**Omit fields that have sensible defaults** — in particular, do not include
`engine: copilot` or `timeout-minutes: 20` unless you need to override them.

### Step 4: Compile the workflow

```bash
# Compile one workflow
gh aw compile <workflow-name>

# Compile all workflows
gh aw compile

# Compile with all security scanners
gh aw compile --actionlint --zizmor --poutine
```

This produces `.github/workflows/<workflow-name>.lock.yml`.  
**Always recompile after changing any frontmatter field.**

### Step 5: Commit both files

```bash
git add .gitattributes \
        .github/workflows/<workflow-name>.md \
        .github/workflows/<workflow-name>.lock.yml
git commit -m "Add <workflow-name> agentic workflow"
git push
```

Ensure `.gitattributes` contains:

```
.github/workflows/*.lock.yml linguist-generated=true merge=ours
```

### Step 6: Trigger and monitor

```bash
# Run interactively on demand
gh aw run <workflow-name>

# Run on a specific branch
gh aw run <workflow-name> --ref main

# Check recent run status
gh aw status

# Download logs
gh aw logs <workflow-name>

# Deep audit of a specific run
gh aw audit <run-id>
```

## Validation

- [ ] `.github/workflows/<name>.md` exists with valid YAML frontmatter
- [ ] `.github/workflows/<name>.lock.yml` exists and is up to date
- [ ] `gh aw compile` reports no errors
- [ ] Agent job has only `read` permissions
- [ ] All GitHub writes use `safe-outputs:`
- [ ] `.gitattributes` includes the lock-file merge strategy line
- [ ] No secrets committed; secrets passed via `${{ secrets.* }}`

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| Editing `.lock.yml` directly | Edit `.md` source and recompile |
| Granting `issues: write` on the agent job | Use `safe-outputs: add-comment:` instead |
| Using `api.github.com` in `network.allowed` | Use `tools: github: toolsets: [default]` |
| Using `network: defaults` alone for package installs | Add ecosystem: `node`, `python`, `go`, etc. |
| Forgetting to recompile after frontmatter change | Run `gh aw compile` after every frontmatter edit |
| Using `gh workflow run` instead of `gh aw run` | Always use `gh aw run <name>` |
| Triggering with `/schedule` cron at midnight | Use fuzzy schedule: `schedule: daily on weekdays` |

## References

- Canonical reference: <https://raw.githubusercontent.com/github/gh-aw/main/.github/aw/github-agentic-workflows.md>
- Workflow creation guide: <https://raw.githubusercontent.com/github/gh-aw/main/.github/aw/create-agentic-workflow.md>
- Documentation site: <https://github.github.com/gh-aw/>
- Repository: <https://github.com/github/gh-aw>
