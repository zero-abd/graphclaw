"""Python runtime helper for coordinator routing.

The Jac walker remains available for Jac-native entrypoints, but the CLI/channel
runtime in `main.jac` executes inside Python blocks and should call a plain
Python helper rather than trying to `.spawn()` a walker instance.
"""
from __future__ import annotations

import asyncio
from typing import Optional

from graphclaw.agents.base import AgentResult, BaseAgent
from graphclaw.agents.builder import BuilderAgent
from graphclaw.agents.devops import DevOpsAgent
from graphclaw.agents.planner import PlannerAgent
from graphclaw.agents.researcher import ResearcherAgent
from graphclaw.mcp.tooling import attach_mcp_runtime
from graphclaw.skills.tooling import attach_skill_runtime
from graphclaw.tools.web import WebFetchTool, WebSearchTool


_AGENT_KEYWORDS = {
    "devops": ("deploy", "infra", "docker", "kubernetes", "k8s", "ci", "cd", "base44", "loveable", "railway", "vercel"),
    "planner": ("plan", "roadmap", "milestone", "priorit", "break down", "todo", "schedule"),
    "builder": ("code", "implement", "build", "fix", "bug", "refactor", "edit", "write", "test"),
    "researcher": ("research", "search", "find", "look up", "compare", "summarize", "investigate"),
}


def _select_agent_class(query: str):
    lowered = query.lower()
    for name, keywords in _AGENT_KEYWORDS.items():
        if any(keyword in lowered for keyword in keywords):
            return {
                "devops": DevOpsAgent,
                "planner": PlannerAgent,
                "builder": BuilderAgent,
                "researcher": ResearcherAgent,
            }[name]
    return BaseAgent


def _identity_prefix(assistant_name: str) -> str:
    return (
        f"You are {assistant_name}. Graphclaw is your underlying runtime/platform name, "
        f"but when the user asks your name or addresses you directly, you should use {assistant_name}. "
        "Honor user-provided naming preferences unless they ask you to change it again."
    )


async def run_coordinator(
    query: str,
    channel: str = "cli",
    chat_id: str = "local",
    user_id: str = "user",
    model: Optional[str] = None,
    assistant_name: str = "Graphclaw",
) -> AgentResult:
    agent_cls = _select_agent_class(query)
    agent = agent_cls(query=query, channel=channel, chat_id=chat_id, user_id=user_id, model=model)
    prefix = _identity_prefix(assistant_name)
    if isinstance(agent, BaseAgent) and agent_cls is BaseAgent:
        agent.system_prompt = (
            prefix + " " +
            "You are a helpful multi-agent AI assistant. "
            "Answer directly and clearly. Use tools when helpful, and be honest about uncertainty."
        )
        agent.tools = [WebSearchTool(), WebFetchTool()]
        attach_skill_runtime(agent)
        attach_mcp_runtime(agent)
    else:
        agent.system_prompt = prefix + " " + agent.system_prompt
    return await agent.run()
