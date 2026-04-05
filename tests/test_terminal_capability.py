from __future__ import annotations

import importlib
import sys
from pathlib import Path
from types import SimpleNamespace

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

import graphclaw.agents.coordinator_runtime as coordinator_runtime_mod
import graphclaw.agents.planner as planner_mod
import graphclaw.agents.researcher as researcher_mod
from graphclaw.agents.base import AgentResult

coordinator_runtime = importlib.reload(coordinator_runtime_mod)
planner = importlib.reload(planner_mod)
researcher = importlib.reload(researcher_mod)


def _fake_config(workspace: str = '/tmp/graphclaw-workspace'):
    return SimpleNamespace(workspace=workspace)


def test_terminal_queries_route_to_builder():
    assert coordinator_runtime._select_agent_class('run this command in the terminal for me').__name__ == 'BuilderAgent'
    assert coordinator_runtime._select_agent_class('open powershell and fix the bug').__name__ == 'BuilderAgent'


def test_default_coordinator_agent_gets_shell_and_filesystem_tools(monkeypatch):
    monkeypatch.setattr(coordinator_runtime, 'load_config', lambda: _fake_config())
    monkeypatch.setattr(coordinator_runtime, 'attach_skill_runtime', lambda agent: None)
    monkeypatch.setattr(coordinator_runtime, 'attach_mcp_runtime', lambda agent: None)

    captured = {}

    async def fake_run(self):
        captured['tools'] = [tool.name for tool in self.tools]
        captured['system_prompt'] = self.system_prompt
        return AgentResult(content='ok')

    monkeypatch.setattr(coordinator_runtime.BaseAgent, 'run', fake_run)

    result = __import__('asyncio').run(coordinator_runtime.run_coordinator('hello there'))

    assert result.content == 'ok'
    assert captured['tools'] == [
        'read_file', 'write_file', 'edit_file', 'list_dir', 'shell', 'web_search', 'web_fetch'
    ]
    assert 'execute terminal commands' in captured['system_prompt']


def test_planner_agent_includes_shell_tool(monkeypatch):
    monkeypatch.setattr(planner, 'load_config', lambda: _fake_config())
    monkeypatch.setattr(planner, 'attach_skill_runtime', lambda agent: None)
    monkeypatch.setattr(planner, 'attach_mcp_runtime', lambda agent: None)

    agent = planner.PlannerAgent(query='plan release')

    assert [tool.name for tool in agent.tools] == ['read_file', 'write_file', 'list_dir', 'shell']


def test_researcher_agent_includes_shell_and_local_context_tools(monkeypatch):
    monkeypatch.setattr(researcher, 'load_config', lambda: _fake_config())
    monkeypatch.setattr(researcher, 'attach_skill_runtime', lambda agent: None)
    monkeypatch.setattr(researcher, 'attach_mcp_runtime', lambda agent: None)

    agent = researcher.ResearcherAgent(query='investigate test failures')

    assert [tool.name for tool in agent.tools] == ['read_file', 'list_dir', 'shell', 'web_search', 'web_fetch']
