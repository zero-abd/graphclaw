"""Builder agent — specialized for code writing and file operations."""
from __future__ import annotations
from graphclaw.agents.base import BaseAgent
from graphclaw.tools.filesystem import ReadFileTool, WriteFileTool, EditFileTool, ListDirTool
from graphclaw.tools.platform_builders import builder_platform_tools
from graphclaw.tools.shell import ShellTool
from graphclaw.tools.web import WebSearchTool, WebFetchTool
from graphclaw.config.loader import load_config
from graphclaw.mcp.tooling import attach_mcp_runtime
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
            " For fast website prototypes, prefer Lovable plus Playwright MCP so you can publish and return the real shareable URL instead of only a prompt link. "
            "For Base44, prefer the official Base44 MCP server for AI app creation and use the CLI tools only for local code-first project workflows. "
            "If platform MCP servers are missing, configure them with configure_platform_mcp_servers first. "
            "If the user shares Loveable login credentials, save them with the credential tool before attempting browser-assisted progress."
        )
        attach_skill_runtime(self)
        attach_mcp_runtime(self)
