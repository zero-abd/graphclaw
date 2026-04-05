"""Planner agent — task decomposition and project planning."""
from __future__ import annotations
from graphclaw.agents.base import BaseAgent
from graphclaw.mcp.tooling import attach_mcp_runtime
from graphclaw.tools.filesystem import ReadFileTool, WriteFileTool
from graphclaw.config.loader import load_config
from graphclaw.skills.tooling import attach_skill_runtime


class PlannerAgent(BaseAgent):
    name = "planner"
    system_prompt = (
        "You are a technical project planner. Break complex goals into actionable tasks. "
        "Consider dependencies, risks, and priorities. Output structured plans with clear "
        "milestones. You can read and write plan files in the workspace."
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        ws = load_config().workspace
        self.tools = [ReadFileTool(ws), WriteFileTool(ws)]
        attach_skill_runtime(self)
        attach_mcp_runtime(self)
