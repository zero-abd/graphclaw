"""Shared OpenClaw-style skill tools and prompt helpers for all agents."""
from __future__ import annotations

import json
from typing import Any

from graphclaw.skills.loader import (
    build_recommended_skills_summary,
    invoke_skill_async,
    list_skills,
    recommend_skills,
)


class ListSkillsTool:
    name = "list_available_skills"
    description = "List all installed OpenClaw-style skills visible to the current runtime."
    parameters = {"type": "object", "properties": {}}

    async def execute(self, **kwargs: Any) -> str:
        return json.dumps(list_skills(), indent=2)


class RecommendSkillsTool:
    name = "recommend_skills"
    description = "Semantically rank installed skills for the current task using compact skill metadata."
    parameters = {
        "type": "object",
        "properties": {
            "task": {"type": "string", "description": "Task or request to match against installed skills"},
            "limit": {"type": "integer", "description": "Maximum number of skill matches to return", "default": 3},
        },
        "required": ["task"],
    }

    async def execute(self, **kwargs: Any) -> str:
        limit = int(kwargs.get("limit", 3) or 3)
        return json.dumps(recommend_skills(str(kwargs.get("task", "")), limit=limit), indent=2)


class InvokeSkillTool:
    name = "invoke_skill"
    description = "Read an installed OpenClaw/ClawHub SKILL.md skill for the current task, or invoke a legacy native skill when explicitly requested."
    parameters = {
        "type": "object",
        "properties": {
            "slug": {"type": "string", "description": "Installed skill slug"},
            "function_name": {
                "type": "string",
                "description": "Legacy native function to call (omit to list available functions)",
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


def attach_skill_runtime(agent: Any) -> None:
    """Attach shared skill tools and task-aware prompt guidance to an agent instance."""
    existing = {getattr(tool, "name", "") for tool in getattr(agent, "tools", [])}
    shared_tools = [ListSkillsTool(), RecommendSkillsTool(), InvokeSkillTool()]
    for tool in shared_tools:
        if tool.name not in existing:
            agent.tools.append(tool)
            existing.add(tool.name)

    query = str(getattr(agent, "query", "") or "").strip()
    if not query:
        return

    agent.system_prompt = (
        agent.system_prompt
        + "\n\nInstalled skills most relevant to this task:\n"
        + build_recommended_skills_summary(query)
        + "\n\nUse recommend_skills if you need to re-rank the options, and use invoke_skill to read the matching SKILL.md before improvising your own workflow."
    )
