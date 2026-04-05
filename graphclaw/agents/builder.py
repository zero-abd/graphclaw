"""Builder agent — specialized for code writing and file operations."""
from __future__ import annotations
from graphclaw.agents.base import BaseAgent
from graphclaw.tools.filesystem import ReadFileTool, WriteFileTool, EditFileTool, ListDirTool
from graphclaw.tools.platform_builders import builder_platform_tools
from graphclaw.tools.shell import ShellTool
from graphclaw.tools.web import WebSearchTool, WebFetchTool
from graphclaw.config.loader import load_config
from graphclaw.skills.tooling import attach_skill_runtime


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
            *builder_platform_tools(channel=self.channel, chat_id=self.chat_id, user_id=self.user_id),
        ]
        self.system_prompt += (
            " For fast website prototypes, prefer Loveable build links. "
            "For managed full-stack scaffolding and deployment, prefer Base44 CLI tools. "
            "If the user shares Loveable login credentials, save them with the credential tool before attempting browser-assisted screenshot progress."
        )
        attach_skill_runtime(self)
