# gh-aw-mcp-approval-queue
A POC to demonstrate CI/CD for approval of MCPs.

## Validate the workflows locally

```bash
bash scripts/setup-gh-aw.sh
gh aw compile
python3 -m pip install -r requirements-test.txt
python3 -m pytest tests/test_workflow_deterministic.py -v
python3 -m pytest tests/agent_evals -v --agenteval-report=json --agenteval-report-dir=/tmp/agenteval-reports
```

The repository also includes a GitHub Actions workflow that runs the same compile,
deterministic, and agenteval-based checks on pushes and pull requests.
