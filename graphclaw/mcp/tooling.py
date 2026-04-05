"""Agent tools for Graphclaw MCP servers."""
from __future__ import annotations

import json
from typing import Any

from graphclaw.mcp.runtime import (
    build_mcp_summary,
    call_tool,
    get_prompt,
    list_cached_prompts,
    list_cached_resources,
    list_cached_tools,
    list_server_summaries,
    read_resource,
    refresh_all_servers_cache,
    refresh_server_cache,
)


class ListMCPServersTool:
    name = "list_mcp_servers"
    description = "List configured MCP servers."
    parameters = {"type": "object", "properties": {}}

    async def execute(self, **kwargs: Any) -> str:
        return json.dumps(list_server_summaries(), indent=2)


class RefreshMCPServerCatalogTool:
    name = "refresh_mcp_catalog"
    description = "Connect to configured MCP servers and refresh the cached catalog of tools, resources, and prompts."
    parameters = {
        "type": "object",
        "properties": {
            "server": {"type": "string", "description": "Optional one server name to refresh", "default": ""},
        },
    }

    async def execute(self, **kwargs: Any) -> str:
        server = str(kwargs.get("server", "") or "").strip()
        payload = await refresh_server_cache(server) if server else await refresh_all_servers_cache()
        return json.dumps(payload, indent=2)


class ListMCPToolsTool:
    name = "list_mcp_tools"
    description = "List cached MCP tools discovered from configured servers."
    parameters = {
        "type": "object",
        "properties": {
            "server": {"type": "string", "description": "Optional server name filter", "default": ""},
        },
    }

    async def execute(self, **kwargs: Any) -> str:
        server = str(kwargs.get("server", "") or "").strip() or None
        return json.dumps(list_cached_tools(server), indent=2)


class CallMCPToolTool:
    name = "call_mcp_tool"
    description = "Call a tool exposed by a configured MCP server."
    parameters = {
        "type": "object",
        "properties": {
            "server": {"type": "string", "description": "Configured MCP server name"},
            "tool_name": {"type": "string", "description": "MCP tool name"},
            "arguments": {"type": "object", "description": "Arguments for the MCP tool", "default": {}},
        },
        "required": ["server", "tool_name"],
    }

    async def execute(self, **kwargs: Any) -> str:
        result = await call_tool(
            str(kwargs.get("server", "")),
            str(kwargs.get("tool_name", "")),
            kwargs.get("arguments", {}) or {},
        )
        return json.dumps(result, indent=2)


class ListMCPResourcesTool:
    name = "list_mcp_resources"
    description = "List cached MCP resources discovered from configured servers."
    parameters = {
        "type": "object",
        "properties": {
            "server": {"type": "string", "description": "Optional server name filter", "default": ""},
        },
    }

    async def execute(self, **kwargs: Any) -> str:
        server = str(kwargs.get("server", "") or "").strip() or None
        return json.dumps(list_cached_resources(server), indent=2)


class ReadMCPResourceTool:
    name = "read_mcp_resource"
    description = "Read a resource exposed by a configured MCP server."
    parameters = {
        "type": "object",
        "properties": {
            "server": {"type": "string", "description": "Configured MCP server name"},
            "uri": {"type": "string", "description": "Resource URI"},
        },
        "required": ["server", "uri"],
    }

    async def execute(self, **kwargs: Any) -> str:
        result = await read_resource(str(kwargs.get("server", "")), str(kwargs.get("uri", "")))
        return json.dumps(result, indent=2)


class ListMCPPromptsTool:
    name = "list_mcp_prompts"
    description = "List cached MCP prompts discovered from configured servers."
    parameters = {
        "type": "object",
        "properties": {
            "server": {"type": "string", "description": "Optional server name filter", "default": ""},
        },
    }

    async def execute(self, **kwargs: Any) -> str:
        server = str(kwargs.get("server", "") or "").strip() or None
        return json.dumps(list_cached_prompts(server), indent=2)


class GetMCPPromptTool:
    name = "get_mcp_prompt"
    description = "Resolve a prompt exposed by a configured MCP server."
    parameters = {
        "type": "object",
        "properties": {
            "server": {"type": "string", "description": "Configured MCP server name"},
            "prompt_name": {"type": "string", "description": "Prompt name"},
            "arguments": {"type": "object", "description": "Prompt arguments as string values", "default": {}},
        },
        "required": ["server", "prompt_name"],
    }

    async def execute(self, **kwargs: Any) -> str:
        args = {str(k): str(v) for k, v in (kwargs.get("arguments", {}) or {}).items()}
        result = await get_prompt(str(kwargs.get("server", "")), str(kwargs.get("prompt_name", "")), args)
        return json.dumps(result, indent=2)


def attach_mcp_runtime(agent: Any) -> None:
    existing = {getattr(tool, "name", "") for tool in getattr(agent, "tools", [])}
    shared = [
        ListMCPServersTool(),
        RefreshMCPServerCatalogTool(),
        ListMCPToolsTool(),
        CallMCPToolTool(),
        ListMCPResourcesTool(),
        ReadMCPResourceTool(),
        ListMCPPromptsTool(),
        GetMCPPromptTool(),
    ]
    added = False
    for tool in shared:
        if tool.name not in existing:
            agent.tools.append(tool)
            added = True
    if not added and "No MCP servers are configured." == build_mcp_summary():
        return
    agent.system_prompt = (
        agent.system_prompt
        + "\n\nConfigured MCP servers:\n"
        + build_mcp_summary()
        + "\n\nIf MCP servers are configured, use refresh_mcp_catalog first when you need a fresh view, "
        + "then inspect tools/resources/prompts and call them through the MCP tools instead of guessing."
    )
