import json
import os
import socketserver
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler
from pathlib import Path

from tests.workflow_harness import REPO_ROOT, WORKFLOW_IDS, run_command


class WorkflowCompilationTests(unittest.TestCase):
    def test_compile_json_validation_succeeds(self) -> None:
        result = run_command("gh", "aw", "compile", "--json", "--no-emit")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(
            {entry["workflow"] for entry in payload},
            {f"{workflow_id}.md" for workflow_id in WORKFLOW_IDS},
        )
        self.assertTrue(all(entry["valid"] for entry in payload))

    def test_compile_keeps_lockfiles_up_to_date(self) -> None:
        lockfiles_before = {
            workflow_id: (REPO_ROOT / ".github" / "workflows" / f"{workflow_id}.lock.yml").read_text(encoding="utf-8")
            for workflow_id in WORKFLOW_IDS
        }

        result = run_command("gh", "aw", "compile")
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

        lockfiles_after = {
            workflow_id: (REPO_ROOT / ".github" / "workflows" / f"{workflow_id}.lock.yml").read_text(encoding="utf-8")
            for workflow_id in WORKFLOW_IDS
        }
        self.assertEqual(lockfiles_after, lockfiles_before)

    def test_every_workflow_has_a_lockfile(self) -> None:
        for workflow_id in WORKFLOW_IDS:
            self.assertTrue((REPO_ROOT / ".github" / "workflows" / f"{workflow_id}.lock.yml").exists())


class _ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True


class _McpFixtureHandler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length) or b"{}")
        method = payload.get("method")

        if method == "initialize":
            response = {
                "jsonrpc": "2.0",
                "id": payload.get("id"),
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "serverInfo": {"name": "fixture-server", "version": "1.0.0"},
                },
            }
        else:
            response = {
                "jsonrpc": "2.0",
                "id": payload.get("id"),
                "result": {
                    "tools": [
                        {
                            "name": "get_weather",
                            "description": "Return a current weather report for a requested city.",
                            "inputSchema": {
                                "type": "object",
                                "properties": {
                                    "city": {"type": "string"},
                                },
                            },
                        }
                    ]
                },
            }

        body = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        return


class WorkflowScriptTests(unittest.TestCase):
    def test_scan_script_generates_an_approved_verdict(self) -> None:
        server = _ThreadingTCPServer(("127.0.0.1", 0), _McpFixtureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        try:
            with tempfile.TemporaryDirectory() as output_dir:
                target = f"http://127.0.0.1:{server.server_address[1]}"
                result = subprocess.run(
                    [
                        "bash",
                        str(REPO_ROOT / "scripts" / "scan-mcp.sh"),
                        target,
                        "--output-dir",
                        output_dir,
                    ],
                    cwd=REPO_ROOT,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

                verdict = json.loads(Path(output_dir, "verdict.json").read_text(encoding="utf-8"))
                self.assertEqual(verdict["verdict"], "approved")
                self.assertEqual(verdict["summary"]["tests_passed"], "3/3")
        finally:
            server.shutdown()
            server.server_close()

    def test_deploy_script_uses_expected_azure_cli_commands(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            bin_dir = Path(temp_dir, "bin")
            bin_dir.mkdir()
            log_file = Path(temp_dir, "az.log")
            fake_az = Path(bin_dir, "az")
            fake_az.write_text(
                """#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path

log_path = Path(os.environ["AZ_LOG_FILE"])
with log_path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(sys.argv[1:]) + "\\n")

args = sys.argv[1:]
if args[:2] == ["account", "show"]:
    sys.exit(0)
if args[:2] == ["account", "set"]:
    sys.exit(0)
if args[:3] == ["apic", "api", "show"]:
    sys.exit(1)
sys.exit(0)
""",
                encoding="utf-8",
            )
            fake_az.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            env["AZ_LOG_FILE"] = str(log_file)

            result = subprocess.run(
                [
                    "bash",
                    str(REPO_ROOT / "scripts" / "deploy-to-apic.sh"),
                    "--server-name",
                    "Contoso Weather API",
                    "--server-url",
                    "https://example.com/mcp",
                    "--description",
                    "Weather service",
                    "--subscription",
                    "sub-123",
                    "--resource-group",
                    "rg-demo",
                    "--apic-service",
                    "apic-demo",
                ],
                cwd=REPO_ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("contoso-weather-api", result.stdout)

            calls = [json.loads(line) for line in log_file.read_text(encoding="utf-8").splitlines()]
            self.assertIn(["account", "show"], calls)
            self.assertIn(["account", "set", "--subscription", "sub-123"], calls)
            self.assertTrue(any(call[:4] == ["apic", "api", "create", "--resource-group"] for call in calls))
            self.assertTrue(any(call[:4] == ["apic", "environment", "create", "--resource-group"] for call in calls))
            self.assertTrue(any(call[:5] == ["apic", "api", "deployment", "create", "--resource-group"] for call in calls))


if __name__ == "__main__":
    unittest.main()
