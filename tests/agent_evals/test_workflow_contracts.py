import json


def test_request_workflow_contract(agent):
    result = agent.run('{"workflow":"mcp-request","scenario":"intake"}')
    contract = json.loads(result.output)

    assert contract["mentions_create_issue"]
    assert contract["mentions_https_validation"]
    assert contract["mentions_workflow_dispatch"]
    assert contract["mentions_repository_dispatch"]
    assert result.trace.converged()
    assert result.trace.no_prompt_injection()


def test_review_workflow_contract(agent):
    result = agent.run('{"workflow":"mcp-review","scenario":"review"}')
    contract = json.loads(result.output)

    assert contract["mentions_scan_script"]
    assert contract["mentions_pending_review_removal"]
    assert contract["mentions_requires_manual_review"]
    assert contract["mentions_approved_label"]
    assert result.trace.total_cost_usd < 1.0
    assert result.trace.no_loops(max_repeats=2)


def test_deploy_workflow_contract(agent):
    result = agent.run('{"workflow":"mcp-deploy","scenario":"deploy"}')
    contract = json.loads(result.output)

    assert contract["mentions_deploy_script"]
    assert contract["mentions_secret_verification"]
    assert contract["mentions_approved_label"]
    assert contract["mentions_deployed_label"]
    assert result.trace.total_latency_ms < 30000
    assert result.trace.no_pii_leaked()
