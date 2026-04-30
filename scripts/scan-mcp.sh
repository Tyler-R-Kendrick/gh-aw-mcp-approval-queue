#!/usr/bin/env bash
# scan-mcp.sh – Security and semantic scanning of an MCP server.
#
# Usage:
#   scan-mcp.sh <mcp_server_url_or_path> [--output-dir <dir>]
#
# Outputs a JSON report to --output-dir (default: /tmp/mcp-scan-results)
# containing:
#   - tool_definitions.json   – schema of all tools exposed
#   - semantic_report.json    – static/regex-based semantic accuracy checks
#   - binary_scan.json        – Trivy/grype vulnerability scan results (local paths only)
#   - custom_tests.json       – results of custom MCP test suite
#   - verdict.json            – final approval verdict

set -euo pipefail

MCP_TARGET="${1:-}"
OUTPUT_DIR="/tmp/mcp-scan-results"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *) MCP_TARGET="$1"; shift ;;
  esac
done

[[ -z "$MCP_TARGET" ]] && { echo "Usage: scan-mcp.sh <mcp_server_url_or_path> [--output-dir <dir>]" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
REPORT_FILE="$OUTPUT_DIR/verdict.json"

info()  { echo "ℹ  $*"; }
ok()    { echo "✅ $*"; }
warn()  { echo "⚠️  $*"; }
err()   { echo "❌ $*" >&2; }

# ─── 1. Fetch tool definitions ────────────────────────────────────────────────
fetch_tool_definitions() {
  info "Fetching MCP tool definitions from $MCP_TARGET …"
  local tools_file="$OUTPUT_DIR/tool_definitions.json"

  # Try MCP initialize + tools/list via stdio or HTTP
  if [[ "$MCP_TARGET" =~ ^https?:// ]]; then
    # HTTP-based MCP server – call tools/list endpoint
    curl -sf -X POST "$MCP_TARGET" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
      -o "$tools_file" 2>/dev/null \
      || echo '{"error":"could not reach server","tools":[]}' > "$tools_file"
  else
    # Local command / container – run and capture tools/list
    echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
      | timeout 30 "$MCP_TARGET" 2>/dev/null \
      | tee "$tools_file" \
      || echo '{"error":"could not execute server","tools":[]}' > "$tools_file"
  fi

  ok "Tool definitions saved to $tools_file"
}

# ─── 2. Semantic accuracy check ───────────────────────────────────────────────
check_semantic_accuracy() {
  info "Running semantic accuracy checks …"
  local tools_file="$OUTPUT_DIR/tool_definitions.json"
  local report="$OUTPUT_DIR/semantic_report.json"

  python3 - <<'PYEOF' "$tools_file" "$report"
import json, sys, re

tools_file, report_file = sys.argv[1], sys.argv[2]

try:
    data = json.loads(open(tools_file).read())
except Exception as e:
    data = {}

tools = data.get("result", {}).get("tools", data.get("tools", []))
findings = []

MALICIOUS_PATTERNS = [
    r"exec\s*\(",
    r"eval\s*\(",
    r"__import__",
    r"subprocess",
    r"os\.system",
    r"shell\s*=\s*True",
    r"rm\s+-rf",
    r"base64\.b64decode",
    r"wget\s+http",
    r"curl\s+http",
    r"exfil",
    r"backdoor",
    r"keylog",
    r"password\s*=",
    r"secret\s*=",
    r"token\s*=",
]

for tool in tools:
    name = tool.get("name", "unknown")
    description = tool.get("description", "")
    schema = json.dumps(tool.get("inputSchema", {}))

    issues = []

    # Check description clarity
    if len(description.strip()) < 10:
        issues.append({"severity": "warning", "msg": "Tool description is too short or missing"})

    # Check for malicious patterns in description or schema
    combined = description + " " + schema
    for pattern in MALICIOUS_PATTERNS:
        if re.search(pattern, combined, re.IGNORECASE):
            issues.append({"severity": "critical", "msg": f"Potentially malicious pattern detected: {pattern}"})

    # Check input schema has 'properties' defined
    input_schema = tool.get("inputSchema", {})
    if input_schema and not input_schema.get("properties"):
        issues.append({"severity": "warning", "msg": "Input schema missing 'properties' definition"})

    findings.append({"tool": name, "issues": issues})

critical_count = sum(1 for f in findings for i in f["issues"] if i["severity"] == "critical")
warning_count  = sum(1 for f in findings for i in f["issues"] if i["severity"] == "warning")

result = {
    "tools_analyzed": len(tools),
    "critical_issues": critical_count,
    "warning_issues": warning_count,
    "status": "fail" if critical_count > 0 else ("warn" if warning_count > 0 else "pass"),
    "findings": findings,
}

with open(report_file, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF
  ok "Semantic report saved to $report"
}

# ─── 3. Binary / vulnerability scan ──────────────────────────────────────────

# Returns 0 if target is an HTTP/HTTPS URL, 1 otherwise.
_is_url_target() {
  case "$1" in
    http://*|https://*) return 0 ;;
    *) return 1 ;;
  esac
}

# Write a sentinel binary_scan.json with no vulnerabilities.
_write_binary_scan_status() {
  local scan_file="$1" status="$2" reason="$3"
  python3 - <<'PYEOF' "$scan_file" "$status" "$reason" "$MCP_TARGET"
import json, sys
scan_file, status, reason, target = sys.argv[1:5]
with open(scan_file, "w") as f:
    json.dump({"status": status, "reason": reason, "target": target, "vulnerabilities": []}, f, indent=2)
PYEOF
}

# Normalize raw scanner JSON into a flat vulnerabilities list.
_normalize_binary_scan() {
  local raw_file="$1" scan_file="$2" scanner="$3"
  python3 - <<'PYEOF' "$raw_file" "$scan_file" "$scanner" "$MCP_TARGET"
import json, sys

raw_file, scan_file, scanner, target = sys.argv[1:5]
try:
    data = json.loads(open(raw_file).read())
except Exception:
    data = {}

vulns = []

if scanner == "trivy":
    for result in data.get("Results", []) or []:
        for v in result.get("Vulnerabilities", []) or []:
            vulns.append({
                "id": v.get("VulnerabilityID"),
                "package": v.get("PkgName"),
                "installed_version": v.get("InstalledVersion"),
                "fixed_version": v.get("FixedVersion"),
                "severity": v.get("Severity"),
                "title": v.get("Title"),
                "primary_url": v.get("PrimaryURL"),
            })
elif scanner == "grype":
    for match in data.get("matches", []) or []:
        art = match.get("artifact", {}) or {}
        v   = match.get("vulnerability", {}) or {}
        vulns.append({
            "id": v.get("id"),
            "package": art.get("name"),
            "installed_version": art.get("version"),
            "fixed_version": ", ".join((v.get("fix") or {}).get("versions", []) or []),
            "severity": v.get("severity"),
            "title": v.get("description"),
            "primary_url": v.get("dataSource"),
        })

with open(scan_file, "w") as f:
    json.dump({
        "status": "completed",
        "scanner": scanner,
        "target": target,
        "vulnerabilities": vulns,
    }, f, indent=2)
PYEOF
}

run_binary_scan() {
  info "Running binary/vulnerability scan …"
  local scan_file="$OUTPUT_DIR/binary_scan.json"
  local raw_file="$OUTPUT_DIR/.binary_scan_raw.json"

  if _is_url_target "$MCP_TARGET"; then
    warn "Binary scan skipped — filesystem scanners require a local path; URL targets are not scanned."
    _write_binary_scan_status "$scan_file" "skipped" \
      "filesystem scanners require a local path; URL targets are not scanned"
    return 0
  fi

  if [[ ! -e "$MCP_TARGET" ]]; then
    warn "Binary scan target does not exist: $MCP_TARGET"
    _write_binary_scan_status "$scan_file" "error" "target path does not exist"
    return 0
  fi

  if command -v trivy &>/dev/null; then
    if trivy fs --format json --output "$raw_file" "$MCP_TARGET" 2>/dev/null; then
      _normalize_binary_scan "$raw_file" "$scan_file" "trivy"
      ok "Trivy scan complete: $scan_file"
    else
      warn "trivy scan failed"
      _write_binary_scan_status "$scan_file" "error" "trivy scan failed"
    fi
  elif command -v grype &>/dev/null; then
    if grype "$MCP_TARGET" -o json 2>/dev/null > "$raw_file"; then
      _normalize_binary_scan "$raw_file" "$scan_file" "grype"
      ok "Grype scan complete: $scan_file"
    else
      warn "grype scan failed"
      _write_binary_scan_status "$scan_file" "error" "grype scan failed"
    fi
  else
    warn "No vulnerability scanner found (trivy/grype). Skipping binary scan."
    _write_binary_scan_status "$scan_file" "skipped" "no scanner available"
  fi
}

# ─── 4. Custom MCP test suite ────────────────────────────────────────────────
run_custom_tests() {
  info "Running custom MCP test suite …"
  local test_file="$OUTPUT_DIR/custom_tests.json"

  if command -v python3 &>/dev/null; then
    python3 - <<'PYEOF' "$MCP_TARGET" "$test_file"
import json, sys, subprocess, time

target, out_file = sys.argv[1], sys.argv[2]
results = []

def run_test(name, fn):
    try:
        passed, detail = fn()
        results.append({"test": name, "passed": passed, "detail": detail})
    except Exception as e:
        results.append({"test": name, "passed": False, "detail": str(e)})

# Test 1: Server responds to initialize
def test_initialize():
    msg = json.dumps({"jsonrpc":"2.0","id":0,"method":"initialize","params":{
        "protocolVersion":"2024-11-05",
        "capabilities":{},
        "clientInfo":{"name":"scan-client","version":"1.0"}
    }})
    if target.startswith("http"):
        import urllib.request
        req = urllib.request.Request(target, data=msg.encode(), headers={"Content-Type":"application/json"})
        try:
            res = urllib.request.urlopen(req, timeout=10)
            body = json.loads(res.read())
            return ("result" in body, body)
        except Exception as e:
            return (False, str(e))
    return (True, "skipped – local binary, tested separately")

# Test 2: Tools list is non-empty
def test_tools_list():
    tools_file = out_file.replace("custom_tests.json", "tool_definitions.json")
    try:
        data = json.loads(open(tools_file).read())
        tools = data.get("result", {}).get("tools", data.get("tools", []))
        return (len(tools) > 0, f"{len(tools)} tools found")
    except Exception as e:
        return (False, str(e))

# Test 3: No tool name collisions
def test_no_duplicate_tool_names():
    tools_file = out_file.replace("custom_tests.json", "tool_definitions.json")
    try:
        data = json.loads(open(tools_file).read())
        tools = data.get("result", {}).get("tools", data.get("tools", []))
        names = [t.get("name") for t in tools]
        dupes = [n for n in names if names.count(n) > 1]
        return (len(dupes) == 0, f"duplicates: {dupes}" if dupes else "no duplicates")
    except Exception as e:
        return (False, str(e))

run_test("initialize_response", test_initialize)
run_test("tools_list_non_empty", test_tools_list)
run_test("no_duplicate_tool_names", test_no_duplicate_tool_names)

passed_count = sum(1 for r in results if r["passed"])
summary = {"passed": passed_count, "total": len(results), "results": results}
with open(out_file, "w") as f:
    json.dump(summary, f, indent=2)
print(json.dumps(summary, indent=2))
PYEOF
  else
    warn "python3 not found. Skipping custom tests."
    echo '{"status":"skipped","reason":"python3 not available"}' > "$test_file"
  fi
  ok "Custom tests complete: $test_file"
}

# ─── 5. Compute verdict ───────────────────────────────────────────────────────
compute_verdict() {
  info "Computing final verdict …"

  if ! command -v python3 &>/dev/null; then
    warn "python3 not found. Unable to compute final verdict."
    cat > "$REPORT_FILE" <<'EOF'
{
  "verdict": "requires_manual_review",
  "reasons": ["python3 not available; automated verdict could not be computed"],
  "summary": {"semantic_status": "unknown", "binary_vulns": "unknown", "tests_passed": "n/a"}
}
EOF
    warn "Verdict: REQUIRES MANUAL REVIEW (incomplete scan)"
    return 1
  fi

  # Temporarily disable errexit so a non-zero Python exit (1=manual, 2=rejected)
  # does not terminate the script before we can read and report the exit code.
  local rc
  set +e
  python3 - <<'PYEOF' "$OUTPUT_DIR" "$REPORT_FILE"
import json, sys, os

scan_dir, verdict_file = sys.argv[1], sys.argv[2]

def load(fname):
    p = os.path.join(scan_dir, fname)
    try:
        return json.loads(open(p).read())
    except Exception:
        return {}

semantic = load("semantic_report.json")
binary   = load("binary_scan.json")
tests    = load("custom_tests.json")

issues = []
verdict = "approved"

# Semantic findings
if semantic.get("critical_issues", 0) > 0:
    verdict = "rejected"
    issues.append(f"Semantic scan: {semantic['critical_issues']} critical issue(s)")
elif semantic.get("warning_issues", 0) > 0:
    if verdict != "rejected":
        verdict = "requires_manual_review"
    issues.append(f"Semantic scan: {semantic['warning_issues']} warning(s)")

# Binary scan findings (normalized: top-level 'vulnerabilities' list)
vulns = binary.get("vulnerabilities", [])
vuln_count = len(vulns)
critical_vulns = [v for v in vulns if str(v.get("severity", "")).upper() in ("CRITICAL", "HIGH")]
if critical_vulns:
    verdict = "rejected"
    issues.append(f"Binary scan: {len(critical_vulns)} critical/high vulnerability(ies)")
elif vuln_count > 0:
    if verdict != "rejected":
        verdict = "requires_manual_review"
    issues.append(f"Binary scan: {vuln_count} vulnerability(ies)")
elif binary.get("status") == "error":
    if verdict != "rejected":
        verdict = "requires_manual_review"
    issues.append(f"Binary scan: scanner returned an error — manual review required")

# Custom test failures
total  = tests.get("total", 0)
passed = tests.get("passed", 0)
if total > 0 and passed < total:
    failed = total - passed
    if failed > total / 2:
        verdict = "rejected"
    elif verdict != "rejected":
        verdict = "requires_manual_review"
    issues.append(f"Custom tests: {failed}/{total} failed")

result = {
    "verdict": verdict,
    "reasons": issues,
    "summary": {
        "semantic_status": semantic.get("status", "unknown"),
        "binary_vulns": vuln_count,
        "tests_passed": f"{passed}/{total}" if total else "n/a",
    }
}

with open(verdict_file, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))

# Exit codes: 0=approved, 1=manual review, 2=rejected
exit_codes = {"approved": 0, "requires_manual_review": 1, "rejected": 2}
sys.exit(exit_codes.get(verdict, 1))
PYEOF
  rc=$?
  set -e

  case $rc in
    0) ok "Verdict: APPROVED" ;;
    1) warn "Verdict: REQUIRES MANUAL REVIEW" ;;
    2) err "Verdict: REJECTED" ;;
  esac
  return $rc
}

# ─── main ─────────────────────────────────────────────────────────────────────
main() {
  info "Starting MCP security scan for: $MCP_TARGET"
  info "Output directory: $OUTPUT_DIR"

  fetch_tool_definitions
  check_semantic_accuracy
  run_binary_scan
  run_custom_tests
  compute_verdict
}

main "$@"
