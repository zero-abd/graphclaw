"""DevOps agent — CI/CD, infrastructure, and skill management."""
from __future__ import annotations
import json
from typing import Any
from graphclaw.agents.base import BaseAgent
from graphclaw.tools.filesystem import ReadFileTool, WriteFileTool, ListDirTool
from graphclaw.tools.shell import ShellTool
from graphclaw.tools.web import WebSearchTool, WebFetchTool
from graphclaw.skills.loader import (
    install_skill,
    invoke_skill_async,
    list_skills,
    search_clawhub,
)
from graphclaw.config.loader import load_config


class _SearchClawHubTool:
    name = "search_clawhub"
    description = "Search ClawHub (clawhub.ai) for available skills/plugins."
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
    description = "Install a skill from ClawHub by slug or from a GitHub URL."
    parameters = {
        "type": "object",
        "properties": {
            "source": {"type": "string", "description": "ClawHub slug or GitHub URL"},
        },
        "required": ["source"],
    }

    async def execute(self, **kwargs: Any) -> str:
        return await install_skill(kwargs["source"])


class _ListSkillsTool:
    name = "list_available_skills"
    description = "List all installed skills and their status."
    parameters = {"type": "object", "properties": {}}

    async def execute(self, **kwargs: Any) -> str:
        skills = list_skills()
        return json.dumps(skills, indent=2)


class _InvokeSkillTool:
    name = "invoke_skill"
    description = (
        "Read an installed OpenClaw/ClawHub SKILL.md skill for the current task, or invoke a legacy native skill when explicitly requested."
    )
    parameters = {
        "type": "object",
        "properties": {
            "slug": {"type": "string", "description": "Installed skill slug"},
            "function_name": {
                "type": "string",
                "description": "Native function to call (omit to list available functions)",
                "default": "",
            },
            "arguments": {
                "type": "object",
                "description": "Arguments to pass to the native skill function",
                "default": {},
            },
            "task": {
                "type": "string",
                "description": "Optional task description when reading a ClawHub SKILL.md",
                "default": "",
            },
        },
        "required": ["slug"],
    }

    async def execute(self, **kwargs: Any) -> str:
        arguments = kwargs.get("arguments", {}) or {}
        if kwargs.get("task"):
            arguments["task"] = kwargs["task"]
        return await invoke_skill_async(
            kwargs["slug"],
            kwargs.get("function_name", ""),
            **arguments,
        )


class DevOpsAgent(BaseAgent):
    name = "devops"
    system_prompt = (
        "You are a DevOps and infrastructure specialist. You manage deployments, CI/CD pipelines, "
        "containers, and cloud services. You can also search and install skills from ClawHub "
        "(clawhub.ai) — the OpenClaw skills registry. Use shell commands for system operations. "
        "Skills come in two types:\n"
        "1. Native skills: Python functions you can call directly\n"
        "2. ClawHub skills: SKILL.md files with step-by-step instructions to follow\n"
        "Always verify before making destructive changes."
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        ws = load_config().workspace
        self.tools = [
            ReadFileTool(ws), WriteFileTool(ws), ListDirTool(ws),
            ShellTool(ws), WebSearchTool(), WebFetchTool(),
            _SearchClawHubTool(), _InstallSkillTool(), _ListSkillsTool(), _InvokeSkillTool(),
        ]
