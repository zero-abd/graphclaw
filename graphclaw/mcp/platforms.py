"""Helpers for recommended MCP platform integrations."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from graphclaw.config.loader import load_config, save_config
from graphclaw.config.schema import MCPServerConfig
from graphclaw.mcp.runtime import call_tool, configured_servers, refresh_server_cache


def recommended_platform_servers() -> dict[str, MCPServerConfig]:
    artifact_dir = Path.home() / ".graphclaw" / "artifacts" / "playwright-mcp"
    artifact_dir.mkdir(parents=True, exist_ok=True)
    return {
        "playwright": MCPServerConfig(
            enabled=True,
            command="npx",
            args=[
                "@playwright/mcp@latest",
                "--headless",
                "--isolated",
                f"--output-dir={artifact_dir}",
            ],
        ),
        "base44": MCPServerConfig(
            enabled=True,
            url="https://app.base44.com/mcp",
        ),
        "base44-docs": MCPServerConfig(
            enabled=True,
            url="https://docs.base44.com/mcp",
        ),
    }


def ensure_recommended_platform_servers() -> dict[str, Any]:
    cfg = load_config(force_reload=True)
    added: list[str] = []
    for name, server in recommended_platform_servers().items():
        if name not in cfg.mcp_servers:
            cfg.mcp_servers[name] = server
            added.append(name)
    save_config(cfg)
    return {
        "added": added,
        "servers": {name: server.model_dump() for name, server in cfg.mcp_servers.items()},
    }


def _tool_exists(server_name: str, tool_name: str) -> bool:
    from graphclaw.mcp.runtime import list_cached_tools

    return any(tool.get("name") == tool_name for tool in list_cached_tools(server_name))


async def ensure_server_catalog(server_name: str) -> dict[str, Any]:
    if server_name not in configured_servers():
        raise ValueError(f"MCP server '{server_name}' is not configured")
    return await refresh_server_cache(server_name)


def playwright_output_dir(server_name: str = "playwright") -> Path | None:
    server = configured_servers().get(server_name)
    if not server:
        return None
    args = list(getattr(server, "args", []) or [])
    for idx, arg in enumerate(args):
        if arg.startswith("--output-dir="):
            return Path(arg.split("=", 1)[1]).expanduser()
        if arg == "--output-dir" and idx + 1 < len(args):
            return Path(args[idx + 1]).expanduser()
    return None


async def playwright_call(tool_name: str, arguments: dict[str, Any] | None = None, server_name: str = "playwright") -> dict[str, Any]:
    await ensure_server_catalog(server_name)
    return await call_tool(server_name, tool_name, arguments or {})


def mcp_result_text(result: dict[str, Any]) -> str:
    lines: list[str] = []
    for item in result.get("content", []) or []:
        if isinstance(item, dict) and item.get("text"):
            lines.append(str(item["text"]))
    if result.get("structuredContent") and not lines:
        return json.dumps(result["structuredContent"], indent=2)
    return "\n".join(lines).strip()


async def maybe_call_first(server_name: str, candidates: list[tuple[str, dict[str, Any]]]) -> tuple[str, dict[str, Any]]:
    await ensure_server_catalog(server_name)
    for tool_name, arguments in candidates:
        if _tool_exists(server_name, tool_name):
            return tool_name, await call_tool(server_name, tool_name, arguments)
    raise ValueError(f"None of the candidate tools exist on MCP server '{server_name}': {[name for name, _ in candidates]}")


async def base44_create_app(prompt: str, *, server_name: str = "base44") -> dict[str, Any]:
    candidates = [
        ("create_base44_app", {"description": prompt}),
        ("create_base44_app", {"prompt": prompt}),
        ("create_base44_app", {"task": prompt}),
    ]
    tool_name, result = await maybe_call_first(server_name, candidates)
    return {"tool": tool_name, "result": result}


async def base44_edit_app(app_id: str, prompt: str, *, server_name: str = "base44") -> dict[str, Any]:
    candidates = [
        ("edit_base44_app", {"app_id": app_id, "description": prompt}),
        ("edit_base44_app", {"appId": app_id, "description": prompt}),
        ("edit_base44_app", {"app_id": app_id, "prompt": prompt}),
        ("edit_base44_app", {"appId": app_id, "prompt": prompt}),
    ]
    tool_name, result = await maybe_call_first(server_name, candidates)
    return {"tool": tool_name, "result": result}
