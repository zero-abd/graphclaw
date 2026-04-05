"""Researcher agent — web research and knowledge synthesis."""
from __future__ import annotations
from graphclaw.agents.base import BaseAgent
from graphclaw.config.loader import load_config
from graphclaw.mcp.tooling import attach_mcp_runtime
from graphclaw.tools.filesystem import ListDirTool, ReadFileTool
from graphclaw.tools.shell import ShellTool
from graphclaw.tools.web import WebSearchTool, WebFetchTool
from graphclaw.skills.tooling import attach_skill_runtime


class ResearcherAgent(BaseAgent):
    name = "researcher"
    system_prompt = (
        "You are a research specialist. Search the web, inspect local project context, and synthesize findings "
        "into clear, factual summaries. Always cite sources. Cross-reference multiple sources "
        "when possible. Flag uncertainty or conflicting information. Use terminal commands when they help you "
        "inspect the local environment or reproduce behavior."
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        ws = load_config().workspace
        self.tools = [ReadFileTool(ws), ListDirTool(ws), ShellTool(ws), WebSearchTool(), WebFetchTool()]
        attach_skill_runtime(self)
        attach_mcp_runtime(self)
