"""Builder agent — specialized for code writing and file operations."""
from __future__ import annotations
from graphclaw.agents.base import BaseAgent
from graphclaw.tools.filesystem import ReadFileTool, WriteFileTool, EditFileTool, ListDirTool
from graphclaw.tools.shell import ShellTool
from graphclaw.tools.web import WebSearchTool, WebFetchTool
from graphclaw.config.loader import load_config


class BuilderAgent(BaseAgent):
    name = "builder"
    system_prompt = (
        "You are a senior software engineer. You write clean, tested, production-quality code. "
        "You have access to file system tools, a shell, and web search. "
        "Always read existing code before modifying. Write tests when appropriate. "
        "Use git for version control. Explain your changes clearly."
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        ws = load_config().workspace
        self.tools = [
            ReadFileTool(ws), WriteFileTool(ws), EditFileTool(ws),
            ListDirTool(ws), ShellTool(ws),
            WebSearchTool(), WebFetchTool(),
        ]
