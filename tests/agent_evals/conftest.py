"""agenteval fixtures for workflow contract checks."""

import pytest

from tests.workflow_harness import workflow_contract_agent


@pytest.fixture
def agent(agent_runner):
    return agent_runner.wrap(workflow_contract_agent, name="workflow_contract_agent")
