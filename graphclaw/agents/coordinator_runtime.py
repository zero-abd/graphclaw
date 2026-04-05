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


async def run_coordinator(
    query: str,
    channel: str = "cli",
    chat_id: str = "local",
    user_id: str = "user",
    model: Optional[str] = None,
) -> AgentResult:
    agent_cls = _select_agent_class(query)
    agent = agent_cls(query=query, channel=channel, chat_id=chat_id, user_id=user_id, model=model)
    if isinstance(agent, BaseAgent) and agent_cls is BaseAgent:
        agent.system_prompt = (
            "You are Graphclaw, a helpful multi-agent AI assistant. "
            "Answer directly and clearly. Use tools when helpful, and be honest about uncertainty."
        )
        agent.tools = [WebSearchTool(), WebFetchTool()]
    return await agent.run()

