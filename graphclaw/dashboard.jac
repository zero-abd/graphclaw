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
    has native_skill_count: int = 0;
    has workflow_skill_count: int = 0;
    has workspace_skill_count: int = 0;
    has shared_skill_count: int = 0;
    has bundled_skill_count: int = 0;
    has managed_skill_count: int = 0;
    has assistant_identity: str = "";
    has assistant_soul: str = "";
    has root_ready: bool = False;
    has channel_summary: list[str] = [];
    has recent_session_labels: list[str] = [];
    has skill_labels: list[str] = [];
    has skill_inventory_labels: list[str] = [];
}

obj MemoryNodeView {
    has id: str = "";
    has kind: str = "node";
    has label: str = "";
    has system_key: str = "";
    has topics: list[str] = [];
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
    has core_edge_count: int = 0;
    has nodes: list[MemoryNodeView] = [];
    has edges: list[MemoryEdgeView] = [];
    has core_node_labels: list[str] = [];
}

obj DashboardSaveResponse {
    has success: bool = True;
    has message: str = "Saved dashboard settings.";
}


def:pub dashboard_overview() -> OverviewResponse {
    response = OverviewResponse();
    ::py::
    from pathlib import Path

    cfg = load_config(force_reload=True)
    sessions = list_sessions()
    memories = list(_iter_live_memories())
    skills = list_skills()
    update_status = get_update_status(fetch=False)
    profile = get_profile()

    workspace_skills_root = Path(cfg.workspace) / "skills"
    shared_skills_root = Path.home() / ".graphclaw" / "skills"
    native_skill_count = 0
    workflow_skill_count = 0
    workspace_skill_count = 0
    shared_skill_count = 0
    bundled_skill_count = 0
    managed_skill_count = 0
    skill_inventory_labels = []
    for skill in skills:
        skill_type = str(skill.get("type", "skill"))
        if skill_type == "native":
            native_skill_count += 1
        else:
            workflow_skill_count += 1

        source = str(skill.get("source", "local"))
        path_text = str(skill.get("path", ""))
        path = Path(path_text) if path_text else None
        location = "workspace"
        if source == "bundled":
            bundled_skill_count += 1
            location = "bundled"
        elif source in {"clawhub", "git"}:
            managed_skill_count += 1
        if path and str(path).startswith(str(shared_skills_root)):
            shared_skill_count += 1
            location = "shared"
        elif path and str(path).startswith(str(workspace_skills_root)):
            workspace_skill_count += 1
            location = "workspace"
        elif source == "bundled":
            location = "bundled"
        skill_inventory_labels.append(
            f"{skill.get('slug', 'skill')} · {skill_type} · {source} · {location}"
        )

    response.version = __version__
    response.assistant_name = get_assistant_name()
    response.assistant_identity = str(profile.get("identity", ""))
    response.assistant_soul = str(profile.get("soul", ""))
    response.root_ready = bool(profile.get("root_memory_id"))
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
    response.native_skill_count = native_skill_count
    response.workflow_skill_count = workflow_skill_count
    response.workspace_skill_count = workspace_skill_count
    response.shared_skill_count = shared_skill_count
    response.bundled_skill_count = bundled_skill_count
    response.managed_skill_count = managed_skill_count
    response.channel_summary = [
        f"{name}: {'enabled' if bool(entry.get('enabled')) else 'disabled'}"
        for name, entry in cfg.channels.items()
    ]
    response.recent_session_labels = [
        f"{session.get('channel', 'cli')} · {str(session.get('session_id', ''))[:8]} · turns {session.get('turn_count', 0)}"
        for session in sessions[-8:]
    ]
    response.skill_labels = [
        f"{skill.get('name', skill.get('slug', 'skill'))} · {skill.get('type', '')} · {skill.get('source', '')}"
        for skill in skills[:12]
    ]
    response.skill_inventory_labels = skill_inventory_labels[:24]
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
    core_node_ids = set()

    response.assistant_name = get_assistant_name()
    response.profile_json = json.dumps(profile, indent=2) if profile else "{}"

    if profile:
        response.nodes.append(MemoryNodeView(id="profile", kind="profile", label=profile.get("assistant_name") or profile.get("display_name") or "Profile"))

    for memory in memories:
        memory_id = str(memory.get("id", ""))
        topics = [str(topic) for topic in (memory.get("topics", []) or [])]
        system_key = str(memory.get("system_key", ""))
        response.nodes.append(
            MemoryNodeView(
                id=memory_id,
                kind="memory",
                label=str(memory.get("content", ""))[:80],
                system_key=system_key,
                topics=topics,
            )
        )
        if system_key.startswith("assistant_"):
            core_node_ids.add(memory_id)
            response.core_node_labels.append(str(memory.get("content", ""))[:80])
        for relation in memory.get("relationships", []) or []:
            target = relation.get("to")
            if target:
                response.edges.append(MemoryEdgeView(source=memory_id, target=str(target), label=str(relation.get("relationship", "related_to"))))
                if memory_id in core_node_ids:
                    response.core_edge_count += 1

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
