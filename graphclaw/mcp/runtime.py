"""Runtime support for connecting to external MCP servers."""
from __future__ import annotations

import json
import os
import re
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, AsyncIterator

from graphclaw.config.loader import load_config


def _substitute_env(value: str) -> str:
    def repl(match: re.Match[str]) -> str:
        return os.environ.get(match.group(1), "")

    return re.sub(r"\$\{([^}]+)\}", repl, value)


def _cache_path() -> Path:
    path = Path.home() / ".graphclaw" / "state" / "mcp-cache.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _read_cache() -> dict[str, Any]:
    path = _cache_path()
    if not path.exists():
        return {"servers": {}}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"servers": {}}
    if not isinstance(payload, dict):
        return {"servers": {}}
    payload.setdefault("servers", {})
    return payload


def _write_cache(payload: dict[str, Any]) -> None:
    _cache_path().write_text(json.dumps(payload, indent=2), encoding="utf-8")


def configured_servers() -> dict[str, Any]:
    cfg = load_config()
    servers = {}
    for name, entry in (cfg.mcp_servers or {}).items():
        if getattr(entry, "enabled", True):
            servers[name] = entry
    return servers


def _server_summary(name: str, server: Any) -> dict[str, Any]:
    transport = "streamable_http" if getattr(server, "url", "") else "stdio"
    return {
        "name": name,
        "transport": transport,
        "url": getattr(server, "url", ""),
        "command": getattr(server, "command", ""),
        "args": list(getattr(server, "args", []) or []),
    }


@asynccontextmanager
async def open_session(server_name: str) -> AsyncIterator[Any]:
    servers = configured_servers()
    if server_name not in servers:
        raise ValueError(f"MCP server '{server_name}' is not configured")
    server = servers[server_name]

    try:
        from mcp import ClientSession
        from mcp.client.stdio import StdioServerParameters, stdio_client
        from mcp.client.streamable_http import streamablehttp_client
    except ImportError as exc:
        raise RuntimeError("MCP support is not installed. Reinstall Graphclaw with the new mcp dependency.") from exc

    if getattr(server, "url", ""):
        headers = {k: _substitute_env(v) for k, v in dict(getattr(server, "headers", {}) or {}).items()}
        async with streamablehttp_client(_substitute_env(server.url), headers=headers or None) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                yield session
        return

    command = str(getattr(server, "command", "") or "").strip()
    if not command:
        raise ValueError(f"MCP server '{server_name}' must define either url or command")
    params = StdioServerParameters(
        command=command,
        args=[_substitute_env(item) for item in list(getattr(server, "args", []) or [])],
        env={k: _substitute_env(v) for k, v in dict(getattr(server, "env", {}) or {}).items()} or None,
        cwd=_substitute_env(getattr(server, "cwd", "") or "") or None,
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            yield session


def _tool_to_dict(tool: Any) -> dict[str, Any]:
    if hasattr(tool, "model_dump"):
        return tool.model_dump(mode="json")
    return {
        "name": getattr(tool, "name", ""),
        "description": getattr(tool, "description", ""),
        "inputSchema": getattr(tool, "inputSchema", {}),
    }


def _resource_to_dict(resource: Any) -> dict[str, Any]:
    if hasattr(resource, "model_dump"):
        return resource.model_dump(mode="json")
    return {"name": getattr(resource, "name", ""), "uri": str(getattr(resource, "uri", ""))}


def _prompt_to_dict(prompt: Any) -> dict[str, Any]:
    if hasattr(prompt, "model_dump"):
        return prompt.model_dump(mode="json")
    return {"name": getattr(prompt, "name", ""), "description": getattr(prompt, "description", "")}


async def refresh_server_cache(server_name: str) -> dict[str, Any]:
    async with open_session(server_name) as session:
        tools_res = await session.list_tools()
        resources_res = await session.list_resources()
        prompts_res = await session.list_prompts()

    entry = {
        "server": server_name,
        "summary": _server_summary(server_name, configured_servers()[server_name]),
        "tools": [_tool_to_dict(tool) for tool in getattr(tools_res, "tools", []) or []],
        "resources": [_resource_to_dict(resource) for resource in getattr(resources_res, "resources", []) or []],
        "prompts": [_prompt_to_dict(prompt) for prompt in getattr(prompts_res, "prompts", []) or []],
    }
    payload = _read_cache()
    payload.setdefault("servers", {})[server_name] = entry
    _write_cache(payload)
    return entry


async def refresh_all_servers_cache() -> dict[str, Any]:
    payload = _read_cache()
    payload["servers"] = {}
    for name in configured_servers():
        try:
            payload["servers"][name] = await refresh_server_cache(name)
        except Exception as exc:
            payload["servers"][name] = {
                "server": name,
                "summary": _server_summary(name, configured_servers()[name]),
                "error": str(exc),
                "tools": [],
                "resources": [],
                "prompts": [],
            }
    _write_cache(payload)
    return payload


def list_server_summaries() -> list[dict[str, Any]]:
    return [_server_summary(name, server) for name, server in configured_servers().items()]


def list_cached_tools(server_name: str | None = None) -> list[dict[str, Any]]:
    payload = _read_cache()
    servers = payload.get("servers", {})
    if server_name:
        return list(servers.get(server_name, {}).get("tools", []))
    items: list[dict[str, Any]] = []
    for name, data in servers.items():
        for tool in data.get("tools", []):
            item = dict(tool)
            item.setdefault("server", name)
            items.append(item)
    return items


def list_cached_resources(server_name: str | None = None) -> list[dict[str, Any]]:
    payload = _read_cache()
    servers = payload.get("servers", {})
    if server_name:
        return list(servers.get(server_name, {}).get("resources", []))
    items: list[dict[str, Any]] = []
    for name, data in servers.items():
        for resource in data.get("resources", []):
            item = dict(resource)
            item.setdefault("server", name)
            items.append(item)
    return items


def list_cached_prompts(server_name: str | None = None) -> list[dict[str, Any]]:
    payload = _read_cache()
    servers = payload.get("servers", {})
    if server_name:
        return list(servers.get(server_name, {}).get("prompts", []))
    items: list[dict[str, Any]] = []
    for name, data in servers.items():
        for prompt in data.get("prompts", []):
            item = dict(prompt)
            item.setdefault("server", name)
            items.append(item)
    return items


def build_mcp_summary(limit: int = 20) -> str:
    servers = list_server_summaries()
    if not servers:
        return "No MCP servers are configured."
    payload = _read_cache().get("servers", {})
    lines = []
    for server in servers:
        cached = payload.get(server["name"], {})
        tool_count = len(cached.get("tools", []))
        resource_count = len(cached.get("resources", []))
        prompt_count = len(cached.get("prompts", []))
        line = (
            f"- {server['name']} [{server['transport']}]"
            f" tools={tool_count} resources={resource_count} prompts={prompt_count}"
        )
        if cached.get("error"):
            line += f" error={cached['error']}"
        lines.append(line)
    all_tools = list_cached_tools()[:limit]
    for tool in all_tools:
        lines.append(f"  - tool {tool.get('server')}::{tool.get('name')}: {tool.get('description', '')}")
    return "\n".join(lines)


async def call_tool(server_name: str, tool_name: str, arguments: dict[str, Any] | None = None) -> dict[str, Any]:
    async with open_session(server_name) as session:
        result = await session.call_tool(tool_name, arguments or {})
    if hasattr(result, "model_dump"):
        return result.model_dump(mode="json")
    return {"result": str(result)}


async def read_resource(server_name: str, uri: str) -> dict[str, Any]:
    async with open_session(server_name) as session:
        result = await session.read_resource(uri)
    if hasattr(result, "model_dump"):
        return result.model_dump(mode="json")
    return {"result": str(result)}


async def get_prompt(server_name: str, prompt_name: str, arguments: dict[str, str] | None = None) -> dict[str, Any]:
    async with open_session(server_name) as session:
        result = await session.get_prompt(prompt_name, arguments or {})
    if hasattr(result, "model_dump"):
        return result.model_dump(mode="json")
    return {"result": str(result)}
