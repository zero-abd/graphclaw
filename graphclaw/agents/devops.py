"""DevOps agent — CI/CD, infrastructure, and skill management."""
from __future__ import annotations
import json
from typing import Any
from graphclaw.agents.base import BaseAgent
from graphclaw.mcp.tooling import attach_mcp_runtime
from graphclaw.tools.filesystem import ReadFileTool, WriteFileTool, ListDirTool
from graphclaw.tools.platform_builders import builder_platform_tools
from graphclaw.tools.shell import ShellTool
from graphclaw.tools.web import WebSearchTool, WebFetchTool
from graphclaw.skills.loader import (
    build_skills_summary,
    install_skill,
    search_clawhub,
    update_all_skills,
    update_skill,
)
from graphclaw.skills.tooling import attach_skill_runtime
from graphclaw.config.loader import load_config


class _SearchClawHubTool:
    name = "search_clawhub"
    description = "Search ClawHub (clawhub.ai) for manual skill browsing. If you need approval-aware discovery and installation, use request_skill_install instead."
    parameters = {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "Search query"},
        },
        "required": ["query"],
    }

    async def execute(self, **kwargs: Any) -> str:
        results = await search_clawhub(kwargs["query"])
        return json.dumps(results, indent=2)


class _InstallSkillTool:
    name = "install_skill"
    description = "Install a skill from ClawHub by slug or from a GitHub URL only when the user has already explicitly approved or requested that exact skill. Use request_skill_install for discovery plus approval."
    parameters = {
        "type": "object",
        "properties": {
            "source": {"type": "string", "description": "ClawHub slug or GitHub URL"},
        },
        "required": ["source"],
    }

    async def execute(self, **kwargs: Any) -> str:
        return await install_skill(kwargs["source"])


class _UpdateSkillTool:
    name = "update_skill"
    description = "Update one installed OpenClaw/ClawHub skill tracked in .clawhub/lock.json."
    parameters = {
        "type": "object",
        "properties": {
            "slug": {"type": "string", "description": "Installed skill slug"},
        },
        "required": ["slug"],
    }

    async def execute(self, **kwargs: Any) -> str:
        return await update_skill(kwargs["slug"])


class _UpdateAllSkillsTool:
    name = "update_all_skills"
    description = "Update all OpenClaw/ClawHub skills tracked in .clawhub/lock.json."
    parameters = {"type": "object", "properties": {}}

    async def execute(self, **kwargs: Any) -> str:
        return await update_all_skills()


class DevOpsAgent(BaseAgent):
    name = "devops"
    system_prompt = (
        "You are a DevOps and infrastructure specialist. You manage deployments, CI/CD pipelines, "
        "containers, and cloud services. You can also search and install skills from ClawHub "
        "(clawhub.ai) — the OpenClaw skills registry. Use shell commands for system operations. "
        "Primary skills are OpenClaw-style SKILL.md bundles that you should read and follow before "
        "inventing a custom workflow. Legacy native Python skills remain fallback-only. "
        "If no installed skill is strong enough, use request_skill_install so the user can approve the install; "
        "do not rely on raw search_clawhub results alone for that approval flow. "
        "Use Lovable plus Playwright MCP when the user wants a real published website link, and use Base44's official MCP server when they want AI-driven Base44 app creation. "
        "If platform MCP servers are missing, configure them first with configure_platform_mcp_servers. "
        "If the user gives Loveable login credentials, save them with the credential tool before attempting browser-driven publish or progress updates. "
        "Do not ask for a Loveable API key; the Lovable flow should use lovable.dev login email and password only.\n"
        "Always verify before making destructive changes."
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        ws = load_config().workspace
        self.system_prompt = (
            self.system_prompt
            + "\n\nInstalled workspace/shared skills (OpenClaw-style):\n"
            + build_skills_summary()
            + "\n\nPrefer those SKILL.md skills before inventing custom workflows. If a skill is newly installed or updated, tell the user to start a new session so the skill snapshot refreshes."
        )
        self.tools = [
            ReadFileTool(ws), WriteFileTool(ws), ListDirTool(ws),
            ShellTool(ws), WebSearchTool(), WebFetchTool(),
            *builder_platform_tools(channel=self.channel, chat_id=self.chat_id, user_id=self.user_id),
            _SearchClawHubTool(), _InstallSkillTool(), _UpdateSkillTool(), _UpdateAllSkillsTool(),
        ]
        attach_skill_runtime(self)
        attach_mcp_runtime(self)
