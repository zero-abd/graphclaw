import from graphclaw.config.loader { load_config, save_config }

sv import from graphclaw { __version__ }
sv import from graphclaw.memory.backend {
    _iter_live_memories,
    _load_memories,
    get_assistant_name,
    get_profile,
    list_sessions,
    set_assistant_name
}
sv import from graphclaw.skills.loader { list_skills }
sv import from graphclaw.update_manager { get_update_status }

obj OverviewResponse {
    has app_name: str = "Graphclaw Control";
    has version: str = "0.1.0";
    has assistant_name: str = "Graphclaw";
    has workspace: str = "";
    has default_model: str = "";
    has default_provider: str = "openrouter";
    has dream_enabled: bool = True;
    has dream_interval_hours: int = 2;
    has update_available: bool = False;
    has current_commit: str = "";
    has latest_commit: str = "";
    has session_count: int = 0;
    has memory_count: int = 0;
    has skill_count: int = 0;
    has channel_summary: list[str] = [];
    has recent_session_labels: list[str] = [];
    has skill_labels: list[str] = [];
}

obj MemoryNodeView {
    has id: str = "";
    has kind: str = "node";
    has label: str = "";
}

obj MemoryEdgeView {
    has source: str = "";
    has target: str = "";
    has label: str = "related_to";
}

obj MemoryResponse {
    has assistant_name: str = "Graphclaw";
    has profile_json: str = "{}";
    has node_count: int = 0;
    has edge_count: int = 0;
    has nodes: list[MemoryNodeView] = [];
    has edges: list[MemoryEdgeView] = [];
}

obj DashboardSaveResponse {
    has success: bool = True;
    has message: str = "Saved dashboard settings.";
}


def:pub dashboard_overview() -> OverviewResponse {
    response = OverviewResponse();
    ::py::
    cfg = load_config(force_reload=True)
    sessions = list_sessions()
    memories = list(_iter_live_memories())
    skills = list_skills()
    update_status = get_update_status(fetch=False)

    response.version = __version__
    response.assistant_name = get_assistant_name()
    response.workspace = cfg.workspace
    response.default_model = cfg.agents.model
    response.default_provider = str(cfg.providers.get("default_provider", "openrouter"))
    response.dream_enabled = bool(cfg.agents.dream.enabled)
    response.dream_interval_hours = int(cfg.agents.dream.interval_hours)
    response.update_available = bool(update_status.get("available", False))
    response.current_commit = str(update_status.get("current", ""))[:7]
    response.latest_commit = str(update_status.get("latest", ""))[:7]
    response.session_count = len(sessions)
    response.memory_count = len(memories)
    response.skill_count = len(skills)
    response.channel_summary = [
        f"{name}: {'enabled' if bool(entry.get('enabled')) else 'disabled'}"
        for name, entry in cfg.channels.items()
    ]
    response.recent_session_labels = [
        f"{session.get('channel', 'cli')} · {str(session.get('session_id', ''))[:8]} · turns {session.get('turn_count', 0)}"
        for session in sessions[-8:]
    ]
    response.skill_labels = [
        f"{skill.get('name', skill.get('slug', 'skill'))} · {skill.get('type', '')}"
        for skill in skills[:12]
    ]
    ::py::
    return response;
}


def:pub dashboard_memory() -> MemoryResponse {
    response = MemoryResponse();
    ::py::
    import json

    memories = _load_memories()[:200]
    sessions = list_sessions()[:50]
    profile = get_profile()

    response.assistant_name = get_assistant_name()
    response.profile_json = json.dumps(profile, indent=2) if profile else "{}"

    if profile:
        response.nodes.append(MemoryNodeView(id="profile", kind="profile", label=profile.get("assistant_name") or profile.get("display_name") or "Profile"))

    for memory in memories:
        memory_id = str(memory.get("id", ""))
        response.nodes.append(MemoryNodeView(id=memory_id, kind="memory", label=str(memory.get("content", ""))[:80]))
        for relation in memory.get("relationships", []) or []:
            target = relation.get("to")
            if target:
                response.edges.append(MemoryEdgeView(source=memory_id, target=str(target), label=str(relation.get("relationship", "related_to"))))

    for session in sessions:
        session_id = str(session.get("session_id", ""))
        response.nodes.append(MemoryNodeView(id=session_id, kind="session", label=f"Session {session_id[:8]}"))
        for turn in session.get("turns", [])[:20]:
            turn_id = str(turn.get("turn_id", ""))
            response.nodes.append(MemoryNodeView(id=turn_id, kind="turn", label=f"{turn.get('role', 'turn')}: {str(turn.get('content', ''))[:60]}"))
            response.edges.append(MemoryEdgeView(source=session_id, target=turn_id, label="has_turn"))

    response.node_count = len(response.nodes)
    response.edge_count = len(response.edges)
    ::py::
    return response;
}


def:pub dashboard_save_settings(
    assistant_name: str = "",
    default_provider: str = "",
    default_model: str = "",
    dream_enabled: bool = True,
    dream_interval_hours: int = 2,
) -> DashboardSaveResponse {
    response = DashboardSaveResponse();
    ::py::
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
    response.success = True
    response.message = "Saved dashboard settings."
    ::py::
    return response;
}
