"""Shared local-dashboard data shaping helpers."""
from __future__ import annotations

import json
from dataclasses import dataclass, field

from graphclaw import __version__
from graphclaw.config.loader import load_config, save_config
from graphclaw.memory.backend import (
    _iter_live_memories,
    _load_memories,
    get_assistant_name,
    get_profile,
    list_sessions,
    set_assistant_name,
)
from graphclaw.skills.loader import list_skills
from graphclaw.update_manager import get_update_status


@dataclass
class OverviewResponse:
    app_name: str = "Graphclaw Control"
    version: str = "0.1.0"
    assistant_name: str = "Graphclaw"
    workspace: str = ""
    default_model: str = ""
    default_provider: str = "openrouter"
    dream_enabled: bool = True
    dream_interval_hours: int = 2
    update_available: bool = False
    current_commit: str = ""
    latest_commit: str = ""
    session_count: int = 0
    memory_count: int = 0
    skill_count: int = 0
    channel_summary: list[str] = field(default_factory=list)
    recent_session_labels: list[str] = field(default_factory=list)
    skill_labels: list[str] = field(default_factory=list)


@dataclass
class MemoryNodeView:
    id: str = ""
    kind: str = "node"
    label: str = ""


@dataclass
class MemoryEdgeView:
    source: str = ""
    target: str = ""
    label: str = "related_to"


@dataclass
class MemoryResponse:
    assistant_name: str = "Graphclaw"
    profile_json: str = "{}"
    node_count: int = 0
    edge_count: int = 0
    nodes: list[MemoryNodeView] = field(default_factory=list)
    edges: list[MemoryEdgeView] = field(default_factory=list)


@dataclass
class DashboardSaveResponse:
    success: bool = True
    message: str = "Saved dashboard settings."


def dashboard_overview() -> OverviewResponse:
    cfg = load_config(force_reload=True)
    sessions = list_sessions()
    memories = list(_iter_live_memories())
    skills = list_skills()
    update_status = get_update_status(fetch=False)

    return OverviewResponse(
        version=__version__,
        assistant_name=get_assistant_name(),
        workspace=cfg.workspace,
        default_model=cfg.agents.model,
        default_provider=str(cfg.providers.get("default_provider", "openrouter")),
        dream_enabled=bool(cfg.agents.dream.enabled),
        dream_interval_hours=int(cfg.agents.dream.interval_hours),
        update_available=bool(update_status.get("available", False)),
        current_commit=str(update_status.get("current", ""))[:7],
        latest_commit=str(update_status.get("latest", ""))[:7],
        session_count=len(sessions),
        memory_count=len(memories),
        skill_count=len(skills),
        channel_summary=[
            f"{name}: {'enabled' if bool(entry.get('enabled')) else 'disabled'}"
            for name, entry in cfg.channels.items()
        ],
        recent_session_labels=[
            f"{session.get('channel', 'cli')} · {str(session.get('session_id', ''))[:8]} · turns {session.get('turn_count', 0)}"
            for session in sessions[-8:]
        ],
        skill_labels=[
            f"{skill.get('name', skill.get('slug', 'skill'))} · {skill.get('type', '')}"
            for skill in skills[:12]
        ],
    )


def dashboard_memory() -> MemoryResponse:
    memories = _load_memories()[:200]
    sessions = list_sessions()[:50]
    profile = get_profile()
    response = MemoryResponse(
        assistant_name=get_assistant_name(),
        profile_json=json.dumps(profile, indent=2) if profile else "{}",
    )

    if profile:
        response.nodes.append(
            MemoryNodeView(
                id="profile",
                kind="profile",
                label=profile.get("assistant_name") or profile.get("display_name") or "Profile",
            )
        )

    for memory in memories:
        memory_id = str(memory.get("id", ""))
        response.nodes.append(
            MemoryNodeView(id=memory_id, kind="memory", label=str(memory.get("content", ""))[:80])
        )
        for relation in memory.get("relationships", []) or []:
            target = relation.get("to")
            if target:
                response.edges.append(
                    MemoryEdgeView(
                        source=memory_id,
                        target=str(target),
                        label=str(relation.get("relationship", "related_to")),
                    )
                )

    for session in sessions:
        session_id = str(session.get("session_id", ""))
        response.nodes.append(MemoryNodeView(id=session_id, kind="session", label=f"Session {session_id[:8]}"))
        for turn in session.get("turns", [])[:20]:
            turn_id = str(turn.get("turn_id", ""))
            response.nodes.append(
                MemoryNodeView(
                    id=turn_id,
                    kind="turn",
                    label=f"{turn.get('role', 'turn')}: {str(turn.get('content', ''))[:60]}",
                )
            )
            response.edges.append(MemoryEdgeView(source=session_id, target=turn_id, label="has_turn"))

    response.node_count = len(response.nodes)
    response.edge_count = len(response.edges)
    return response


def dashboard_save_settings(
    assistant_name: str = "",
    default_provider: str = "",
    default_model: str = "",
    dream_enabled: bool = True,
    dream_interval_hours: int = 2,
) -> DashboardSaveResponse:
    cfg = load_config(force_reload=True)
    if assistant_name.strip():
        set_assistant_name(assistant_name)
    if default_provider.strip():
        cfg.providers["default_provider"] = default_provider.strip()
    if default_model.strip():
        cfg.agents.model = default_model.strip()
    cfg.agents.dream.enabled = bool(dream_enabled)
    cfg.agents.dream.interval_hours = int(dream_interval_hours)
    save_config(cfg)
    return DashboardSaveResponse(success=True, message="Saved dashboard settings.")
