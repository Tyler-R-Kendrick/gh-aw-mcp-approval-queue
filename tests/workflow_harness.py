import json
import os
import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = REPO_ROOT / ".github" / "workflows"
WORKFLOW_IDS = ("mcp-request", "mcp-review", "mcp-deploy")


def run_command(*args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        args,
        cwd=REPO_ROOT,
        env=merged_env,
        text=True,
        capture_output=True,
        check=False,
    )


def workflow_path(workflow_id: str) -> Path:
    return WORKFLOW_DIR / f"{workflow_id}.md"


def workflow_text(workflow_id: str) -> str:
    return workflow_path(workflow_id).read_text(encoding="utf-8")


def workflow_contract(workflow_id: str) -> dict[str, object]:
    text = workflow_text(workflow_id)
    headings = re.findall(r"^##+\s+(.+)$", text, flags=re.MULTILINE)
    return {
        "workflow": workflow_id,
        "path": str(workflow_path(workflow_id).relative_to(REPO_ROOT)),
        "heading_count": len(headings),
        "headings": headings,
        "body_length": len(text),
        "mentions_create_issue": "create-issue" in text,
        "mentions_scan_script": "bash scripts/scan-mcp.sh" in text,
        "mentions_deploy_script": "bash scripts/deploy-to-apic.sh" in text,
        "mentions_https_validation": "https://" in text,
        "mentions_pending_review_removal": "Remove label `pending-review`" in text,
        "mentions_requires_manual_review": "requires-manual-review" in text,
        "mentions_approved_label": "`approved`" in text,
        "mentions_deployed_label": "`deployed`" in text,
        "mentions_secret_verification": "Verify required secrets" in text,
        "mentions_workflow_dispatch": "workflow_dispatch" in text,
        "mentions_repository_dispatch": "repository_dispatch" in text,
    }


def workflow_contract_agent(prompt: str) -> str:
    request = json.loads(prompt)
    workflow_id = request["workflow"]
    contract = workflow_contract(workflow_id)
    contract["scenario"] = request.get("scenario", workflow_id)
    return json.dumps(contract, sort_keys=True)
