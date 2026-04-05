"""Workspace-backed memory/session helpers used by the Jac wrappers.

This keeps Graphclaw runnable on the current Jac toolchain while preserving the
same high-level memory/session API surface for the rest of the app.
"""
from __future__ import annotations

import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List

from graphclaw.config.loader import ensure_workspace, load_config


MEMORY_FILE = "memories.json"
PROFILE_FILE = "profile.json"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _workspace() -> Path:
    ensure_workspace()
    workspace = Path(load_config().workspace)
    _ensure_core_memory_graph(workspace)
    return workspace


def _ensure_core_memory_graph(workspace: Path) -> None:
    workspace.mkdir(parents=True, exist_ok=True)
    memory_dir = workspace / "memory"
    memory_dir.mkdir(parents=True, exist_ok=True)
    profile_path = memory_dir / PROFILE_FILE
    memories_path = memory_dir / MEMORY_FILE

    cfg = load_config()
    now = _now()
    profile = _load_json(profile_path, {})
    if not isinstance(profile, dict):
        profile = {}

    assistant_name = str(profile.get("assistant_name") or "Graphclaw").strip() or "Graphclaw"
    identity = str(
        profile.get("identity")
        or "A cool-headed graph-native operator who stays sharp, observant, and always a little ahead of the room."
    ).strip()
    soul = str(
        profile.get("soul")
        or "Dry wit, effortless confidence, low drama, high competence, and a habit of saying more with less."
    ).strip()
    cadence = str(
        profile.get("cadence")
        or "Short, clean answers by default. Expand only when asked, when risk is high, or when extra detail genuinely helps."
    ).strip()

    profile_changed = False
    profile_defaults = {
        "created_at": now,
        "assistant_name": assistant_name,
        "display_name": assistant_name,
        "identity": identity,
        "soul": soul,
        "cadence": cadence,
        "timezone": "UTC",
        "preferred_model": cfg.agents.model,
        "dream_interval_hours": int(cfg.agents.dream.interval_hours),
    }
    for key, value in profile_defaults.items():
        if profile.get(key) in {None, ""}:
            profile[key] = value
            profile_changed = True

    memories = _load_json(memories_path, [])
    if not isinstance(memories, list):
        memories = []

    memories_changed = False

    def upsert_system_memory(
        system_key: str,
        content: str,
        *,
        topics: List[str],
        relationship: str = "",
    ) -> str:
        nonlocal memories_changed
        existing = next(
            (item for item in memories if str(item.get("system_key", "")) == system_key),
            None,
        )
        normalized_topics = sorted({topic.strip().lower() for topic in topics if topic.strip()})
        if existing is None:
            existing = {
                "id": str(uuid.uuid4()),
                "content": content,
                "mem_type": "Reference",
                "confidence": 1.0,
                "decay_rate": 0.0,
                "created_at": now,
                "updated_at": now,
                "last_validated_at": now,
                "source_session": "",
                "agent": "system",
                "tombstoned": False,
                "topics": normalized_topics,
                "relationships": [],
                "system_key": system_key,
                "bootstrap_relationship": relationship,
            }
            memories.append(existing)
            memories_changed = True
            return str(existing["id"])

        desired = {
            "content": content,
            "mem_type": "Reference",
            "agent": "system",
            "tombstoned": False,
            "topics": normalized_topics,
            "system_key": system_key,
            "bootstrap_relationship": relationship,
        }
        for key, value in desired.items():
            if existing.get(key) != value:
                existing[key] = value
                existing["updated_at"] = now
                existing["last_validated_at"] = now
                memories_changed = True
        return str(existing["id"])

    root_id = upsert_system_memory(
        "assistant_root",
        f"{assistant_name} root node",
        topics=["assistant", "root", "identity"],
    )
    name_id = upsert_system_memory(
        "assistant_name",
        f"Name: {assistant_name}",
        topics=["assistant", "identity", "name"],
        relationship="has_name",
    )
    identity_id = upsert_system_memory(
        "assistant_identity",
        f"Identity: {identity}",
        topics=["assistant", "identity"],
        relationship="has_identity",
    )
    soul_id = upsert_system_memory(
        "assistant_soul",
        f"Soul: {soul}",
        topics=["assistant", "soul"],
        relationship="has_soul",
    )
    dream_id = upsert_system_memory(
        "assistant_dream_cadence",
        f"Dream cadence: every {int(cfg.agents.dream.interval_hours)} hours",
        topics=["assistant", "dream", "maintenance"],
        relationship="runs_dream_cycle",
    )
    conversation_cadence_id = upsert_system_memory(
        "assistant_conversation_cadence",
        f"Conversation cadence: {cadence}",
        topics=["assistant", "cadence", "conversation"],
        relationship="speaks_with_cadence",
    )
    skills_root_id = upsert_system_memory(
        "assistant_skills_root",
        "Skills root",
        topics=["assistant", "skills"],
        relationship="has_skills",
    )
    inherent_skills_id = upsert_system_memory(
        "assistant_skills_inherent",
        "Inherent skills",
        topics=["assistant", "skills", "inherent"],
        relationship="has_skill_group",
    )
    clawhub_skills_id = upsert_system_memory(
        "assistant_skills_clawhub",
        "ClawHub skills",
        topics=["assistant", "skills", "clawhub"],
        relationship="has_skill_group",
    )
    workspace_skills_id = upsert_system_memory(
        "assistant_skills_workspace",
        "Workspace skills",
        topics=["assistant", "skills", "workspace"],
        relationship="has_skill_group",
    )
    shared_skills_id = upsert_system_memory(
        "assistant_skills_shared",
        "Shared skills",
        topics=["assistant", "skills", "shared"],
        relationship="has_skill_group",
    )
    mcp_root_id = upsert_system_memory(
        "assistant_mcp_root",
        "MCP root",
        topics=["assistant", "mcp"],
        relationship="has_mcp",
    )
    mcp_servers_id = upsert_system_memory(
        "assistant_mcp_servers",
        "Configured MCP servers",
        topics=["assistant", "mcp", "servers"],
        relationship="has_mcp_group",
    )
    mcp_tools_id = upsert_system_memory(
        "assistant_mcp_tools",
        "MCP tools",
        topics=["assistant", "mcp", "tools"],
        relationship="has_mcp_group",
    )
    mcp_resources_id = upsert_system_memory(
        "assistant_mcp_resources",
        "MCP resources",
        topics=["assistant", "mcp", "resources"],
        relationship="has_mcp_group",
    )
    mcp_prompts_id = upsert_system_memory(
        "assistant_mcp_prompts",
        "MCP prompts",
        topics=["assistant", "mcp", "prompts"],
        relationship="has_mcp_group",
    )

    root_node = next(
        (item for item in memories if str(item.get("system_key", "")) == "assistant_root"),
        None,
    )
    if root_node is not None:
        relationships = _ensure_memory_relationships(root_node)
        desired_relationships = [
            {"to": name_id, "relationship": "has_name", "weight": 1.0},
            {"to": identity_id, "relationship": "has_identity", "weight": 1.0},
            {"to": soul_id, "relationship": "has_soul", "weight": 1.0},
            {"to": dream_id, "relationship": "runs_dream_cycle", "weight": 1.0},
            {"to": conversation_cadence_id, "relationship": "speaks_with_cadence", "weight": 1.0},
            {"to": skills_root_id, "relationship": "has_skills", "weight": 1.0},
            {"to": mcp_root_id, "relationship": "has_mcp", "weight": 1.0},
        ]
        for relation in desired_relationships:
            if relation not in relationships:
                relationships.append(relation)
                root_node["updated_at"] = now
                memories_changed = True

    skills_root_node = next(
        (item for item in memories if str(item.get("system_key", "")) == "assistant_skills_root"),
        None,
    )
    if skills_root_node is not None:
        relationships = _ensure_memory_relationships(skills_root_node)
        desired_relationships = [
            {"to": inherent_skills_id, "relationship": "has_skill_group", "weight": 1.0},
            {"to": clawhub_skills_id, "relationship": "has_skill_group", "weight": 1.0},
            {"to": workspace_skills_id, "relationship": "has_skill_group", "weight": 1.0},
            {"to": shared_skills_id, "relationship": "has_skill_group", "weight": 1.0},
        ]
        for relation in desired_relationships:
            if relation not in relationships:
                relationships.append(relation)
                skills_root_node["updated_at"] = now
                memories_changed = True

    try:
        from graphclaw.skills.loader import list_skills

        skill_group_ids = {
            "bundled": inherent_skills_id,
            "local": workspace_skills_id,
            "shared": shared_skills_id,
            "clawhub": clawhub_skills_id,
            "git": clawhub_skills_id,
        }
        for skill in list_skills():
            slug = str(skill.get("slug", "")).strip()
            if not slug:
                continue
            source = str(skill.get("source", "local")).strip() or "local"
            group_id = skill_group_ids.get(source, workspace_skills_id)
            skill_id = upsert_system_memory(
                f"assistant_skill_{slug}",
                f"Skill: {slug}",
                topics=["assistant", "skills", source, str(skill.get("type", "skill"))],
                relationship="has_skill",
            )
            group_node = next((item for item in memories if str(item.get("id")) == group_id), None)
            if group_node is not None:
                relationships = _ensure_memory_relationships(group_node)
                relation = {"to": skill_id, "relationship": "has_skill", "weight": 1.0}
                if relation not in relationships:
                    relationships.append(relation)
                    group_node["updated_at"] = now
                    memories_changed = True
    except Exception:
        pass

    mcp_root_node = next(
        (item for item in memories if str(item.get("system_key", "")) == "assistant_mcp_root"),
        None,
    )
    if mcp_root_node is not None:
        relationships = _ensure_memory_relationships(mcp_root_node)
        desired_relationships = [
            {"to": mcp_servers_id, "relationship": "has_mcp_group", "weight": 1.0},
            {"to": mcp_tools_id, "relationship": "has_mcp_group", "weight": 1.0},
            {"to": mcp_resources_id, "relationship": "has_mcp_group", "weight": 1.0},
            {"to": mcp_prompts_id, "relationship": "has_mcp_group", "weight": 1.0},
        ]
        for relation in desired_relationships:
            if relation not in relationships:
                relationships.append(relation)
                mcp_root_node["updated_at"] = now
                memories_changed = True

    try:
        from graphclaw.mcp.runtime import _read_cache as read_mcp_cache, configured_servers

        def slugify(raw: str) -> str:
            cleaned = re.sub(r"[^a-z0-9]+", "_", raw.lower()).strip("_")
            return cleaned or "item"

        mcp_cache = read_mcp_cache().get("servers", {})
        configured = configured_servers()
        for server_name in sorted(set(configured.keys()) | set(mcp_cache.keys())):
            server_slug = slugify(server_name)
            server_id = upsert_system_memory(
                f"assistant_mcp_server_{server_slug}",
                f"MCP server: {server_name}",
                topics=["assistant", "mcp", "server"],
                relationship="has_mcp_server",
            )
            group_node = next((item for item in memories if str(item.get("id")) == mcp_servers_id), None)
            if group_node is not None:
                relationships = _ensure_memory_relationships(group_node)
                relation = {"to": server_id, "relationship": "has_mcp_server", "weight": 1.0}
                if relation not in relationships:
                    relationships.append(relation)
                    group_node["updated_at"] = now
                    memories_changed = True

            server_cache = mcp_cache.get(server_name, {})
            for bucket_name, group_id, item_key, relation_name in [
                ("tools", mcp_tools_id, "name", "has_mcp_tool"),
                ("resources", mcp_resources_id, "uri", "has_mcp_resource"),
                ("prompts", mcp_prompts_id, "name", "has_mcp_prompt"),
            ]:
                for entry in server_cache.get(bucket_name, [])[:24]:
                    raw_name = str(entry.get(item_key, "") or entry.get("name", "")).strip()
                    if not raw_name:
                        continue
                    item_slug = slugify(f"{server_name}_{bucket_name}_{raw_name}")
                    item_id = upsert_system_memory(
                        f"assistant_mcp_{bucket_name[:-1]}_{item_slug}",
                        f"{bucket_name[:-1].capitalize()}: {raw_name}",
                        topics=["assistant", "mcp", bucket_name[:-1]],
                        relationship=relation_name,
                    )
                    for parent_id in (group_id, server_id):
                        parent_node = next((item for item in memories if str(item.get("id")) == parent_id), None)
                        if parent_node is None:
                            continue
                        relationships = _ensure_memory_relationships(parent_node)
                        relation = {"to": item_id, "relationship": relation_name, "weight": 1.0}
                        if relation not in relationships:
                            relationships.append(relation)
                            parent_node["updated_at"] = now
                            memories_changed = True
    except Exception:
        pass

    if profile.get("root_memory_id") != root_id:
        profile["root_memory_id"] = root_id
        profile_changed = True

    if profile_changed:
        _save_json(profile_path, profile)
    if memories_changed:
        _save_json(memories_path, memories)


def _memory_dir() -> Path:
    path = _workspace() / "memory"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _session_dir() -> Path:
    path = _workspace() / "sessions"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _save_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def _memory_path() -> Path:
    return _memory_dir() / MEMORY_FILE


def _profile_path() -> Path:
    return _memory_dir() / PROFILE_FILE


def _session_path(session_id: str) -> Path:
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", session_id)
    return _session_dir() / f"{safe}.json"


def _load_memories() -> List[Dict[str, Any]]:
    data = _load_json(_memory_path(), [])
    return data if isinstance(data, list) else []


def _save_memories(memories: List[Dict[str, Any]]) -> None:
    _save_json(_memory_path(), memories)


def _load_session(session_id: str) -> Dict[str, Any] | None:
    data = _load_json(_session_path(session_id), None)
    return data if isinstance(data, dict) else None


def _save_session(session: Dict[str, Any]) -> None:
    _save_json(_session_path(str(session["session_id"])), session)


def _effective_confidence(memory: Dict[str, Any]) -> float:
    confidence = float(memory.get("confidence", 1.0))
    decay_rate = float(memory.get("decay_rate", 0.01))
    last_validated_at = memory.get("last_validated_at") or memory.get("updated_at") or _now()
    try:
        last = datetime.fromisoformat(last_validated_at)
        if last.tzinfo is None:
            last = last.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        days = max((now - last).total_seconds(), 0.0) / 86400.0
        return max(0.0, min(1.0, confidence - (decay_rate * days)))
    except Exception:
        return max(0.0, min(1.0, confidence))


def _memory_topics(memory: Dict[str, Any]) -> List[str]:
    topics = memory.get("topics", [])
    if not isinstance(topics, list):
        return []
    return [str(topic).strip().lower() for topic in topics if str(topic).strip()]


def _iter_live_memories() -> Iterable[Dict[str, Any]]:
    for memory in _load_memories():
        if not memory.get("tombstoned"):
            yield memory


def _ensure_memory_relationships(memory: Dict[str, Any]) -> List[Dict[str, Any]]:
    rels = memory.get("relationships", [])
    if not isinstance(rels, list):
        rels = []
        memory["relationships"] = rels
    return rels


def list_sessions(unconsolidated_only: bool = False) -> List[Dict[str, Any]]:
    sessions: List[Dict[str, Any]] = []
    for path in sorted(_session_dir().glob("*.json")):
        data = _load_json(path, None)
        if not isinstance(data, dict):
            continue
        if unconsolidated_only and data.get("consolidated"):
            continue
        sessions.append(data)
    sessions.sort(key=lambda item: item.get("started_at", ""))
    return sessions


def start_session(
    channel: str,
    chat_id: str,
    user_id: str = "",
    agent: str = "coordinator",
    model: str = "",
    session_id: str = "",
) -> str:
    resolved_session_id = session_id or str(uuid.uuid4())
    session = {
        "session_id": resolved_session_id,
        "channel": channel,
        "chat_id": chat_id,
        "user_id": user_id,
        "agent": agent,
        "model": model,
        "started_at": _now(),
        "turns": [],
        "turn_count": 0,
        "consolidated": False,
    }
    _save_session(session)
    return resolved_session_id


def append_turn(
    session_id: str,
    role: str,
    content: str,
    tool_name: str = "",
    tool_result: str = "",
    token_count: int = 0,
) -> str | None:
    session = _load_session(session_id)
    if not session:
        return None

    turn_id = str(uuid.uuid4())
    turn = {
        "turn_id": turn_id,
        "role": role,
        "content": content,
        "tool_name": tool_name,
        "tool_result": tool_result,
        "timestamp": _now(),
        "token_count": token_count,
    }
    session.setdefault("turns", []).append(turn)
    session["turn_count"] = len(session["turns"])
    session["consolidated"] = False
    _save_session(session)
    return turn_id


def store_memory(
    content: str,
    mem_type: str = "User",
    confidence: float = 1.0,
    source_session: str = "",
    agent: str = "",
    topics: List[str] | None = None,
) -> str:
    normalized = content.strip()
    if not normalized:
        raise ValueError("memory content cannot be empty")

    memories = _load_memories()
    now = _now()
    new_topics = {topic.strip().lower() for topic in (topics or []) if topic.strip()}

    for memory in memories:
        if memory.get("content", "").strip() == normalized and not memory.get("tombstoned"):
            memory["confidence"] = max(float(memory.get("confidence", 1.0)), float(confidence))
            memory["updated_at"] = now
            memory["last_validated_at"] = now
            if source_session:
                memory["source_session"] = source_session
            if agent:
                memory["agent"] = agent
            if new_topics:
                memory["topics"] = sorted(set(_memory_topics(memory)) | new_topics)
            _save_memories(memories)
            return str(memory["id"])

    memory_id = str(uuid.uuid4())
    memories.append(
        {
            "id": memory_id,
            "content": normalized,
            "mem_type": mem_type,
            "confidence": float(confidence),
            "decay_rate": 0.01,
            "created_at": now,
            "updated_at": now,
            "last_validated_at": now,
            "source_session": source_session,
            "agent": agent,
            "tombstoned": False,
            "topics": sorted(new_topics),
            "relationships": [],
        }
    )
    _save_memories(memories)
    return memory_id


def link_memories(from_id: str, to_id: str, relationship: str = "related_to", weight: float = 1.0) -> bool:
    memories = _load_memories()
    lookup = {memory.get("id"): memory for memory in memories}
    if from_id not in lookup or to_id not in lookup:
        return False
    rels = _ensure_memory_relationships(lookup[from_id])
    pair = {"to": to_id, "relationship": relationship, "weight": float(weight)}
    if pair not in rels:
        rels.append(pair)
        lookup[from_id]["updated_at"] = _now()
        _save_memories(memories)
    return True


def tag_memory(memory_id: str, topic_name: str) -> bool:
    topic = topic_name.strip().lower()
    if not topic:
        return False
    memories = _load_memories()
    for memory in memories:
        if memory.get("id") == memory_id and not memory.get("tombstoned"):
            topics = set(_memory_topics(memory))
            topics.add(topic)
            memory["topics"] = sorted(topics)
            memory["updated_at"] = _now()
            _save_memories(memories)
            return True
    return False


def revalidate_memory(memory_id: str) -> bool:
    memories = _load_memories()
    for memory in memories:
        if memory.get("id") == memory_id and not memory.get("tombstoned"):
            memory["last_validated_at"] = _now()
            memory["updated_at"] = memory["last_validated_at"]
            _save_memories(memories)
            return True
    return False


def tombstone_memory(memory_id: str) -> bool:
    memories = _load_memories()
    for memory in memories:
        if memory.get("id") == memory_id and not memory.get("tombstoned"):
            memory["tombstoned"] = True
            memory["updated_at"] = _now()
            _save_memories(memories)
            return True
    return False




def get_profile() -> Dict[str, Any]:
    profile = _load_json(_profile_path(), {})
    return profile if isinstance(profile, dict) else {}


def get_assistant_name(default: str = "Graphclaw") -> str:
    profile = get_profile()
    name = str(profile.get("assistant_name", "")).strip()
    return name or default


def set_assistant_name(name: str) -> str:
    cleaned = re.sub(r"\s+", " ", name).strip().strip("\"'")
    cleaned = re.sub(r"[^A-Za-z0-9 _.-]", "", cleaned).strip()
    if not cleaned:
        raise ValueError("assistant name cannot be empty")
    if len(cleaned) > 40:
        cleaned = cleaned[:40].rstrip()
    profile = get_profile()
    profile.setdefault("created_at", _now())
    profile["assistant_name"] = cleaned
    profile["display_name"] = cleaned
    _save_json(_profile_path(), profile)
    _ensure_core_memory_graph(_workspace())
    return cleaned


def extract_assistant_name_change(text: str) -> str | None:
    patterns = [
        r"(?:from now on[, ]*)?your name is ([A-Za-z0-9 _.-]{1,40})",
        r"go by ([A-Za-z0-9 _.-]{1,40})",
        r"i(?:'| a)?ll call you ([A-Za-z0-9 _.-]{1,40})",
        r"call yourself ([A-Za-z0-9 _.-]{1,40})",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE)
        if match:
            return set_assistant_name(match.group(1))
    return None

def upsert_profile(display_name: str = "", timezone_name: str = "UTC", preferred_model: str = "") -> Dict[str, Any]:
    profile = _load_json(_profile_path(), {})
    if not isinstance(profile, dict):
        profile = {}
    profile.setdefault("created_at", _now())
    if display_name:
        profile["display_name"] = display_name
    if timezone_name:
        profile["timezone"] = timezone_name
    if preferred_model:
        profile["preferred_model"] = preferred_model
    _save_json(_profile_path(), profile)
    return profile


def recall(
    query: str,
    limit: int = 10,
    semantic: bool = False,
    mem_type: str = "",
    min_confidence: float = 0.1,
) -> List[Dict[str, Any]]:
    query_lower = query.lower().strip()
    matches: List[Dict[str, Any]] = []
    for memory in _iter_live_memories():
        if mem_type and memory.get("mem_type") != mem_type:
            continue
        confidence = _effective_confidence(memory)
        if confidence < min_confidence:
            continue
        content = str(memory.get("content", ""))
        if query_lower and query_lower not in content.lower() and not semantic:
            continue
        matches.append(
            {
                "id": memory.get("id", ""),
                "content": content,
                "mem_type": memory.get("mem_type", "User"),
                "confidence": confidence,
                "topics": _memory_topics(memory),
            }
        )
    matches.sort(key=lambda item: item["confidence"], reverse=True)
    return matches[:limit]


def recall_by_type(mem_type: str, limit: int = 20) -> List[Dict[str, Any]]:
    return recall(query="", limit=limit, semantic=False, mem_type=mem_type, min_confidence=0.0)


def recall_by_topic(topic_name: str, limit: int = 20) -> List[Dict[str, Any]]:
    topic = topic_name.strip().lower()
    matches: List[Dict[str, Any]] = []
    for memory in _iter_live_memories():
        if topic and topic not in _memory_topics(memory):
            continue
        matches.append(
            {
                "id": memory.get("id", ""),
                "content": memory.get("content", ""),
                "confidence": _effective_confidence(memory),
                "mem_type": memory.get("mem_type", "User"),
                "topics": _memory_topics(memory),
            }
        )
    matches.sort(key=lambda item: item["confidence"], reverse=True)
    return matches[:limit]


def recall_session(session_id: str, last_n: int = 50) -> List[Dict[str, Any]]:
    session = _load_session(session_id)
    if not session:
        return []
    turns = session.get("turns", [])[-last_n:]
    result: List[Dict[str, Any]] = []
    for turn in turns:
        if not isinstance(turn, dict):
            continue
        result.append(
            {
                "role": turn.get("role", ""),
                "content": turn.get("content", ""),
                "timestamp": turn.get("timestamp", ""),
            }
        )
    return result


def get_memory_context(max_chars: int = 4000) -> str:
    live = list(_iter_live_memories())
    live.sort(key=_effective_confidence, reverse=True)
    lines: List[str] = []
    total = 0
    for memory in live:
        line = f"[{memory.get('mem_type', 'User')}] {memory.get('content', '')}".strip()
        if not line:
            continue
        if total + len(line) > max_chars:
            break
        lines.append(line)
        total += len(line)
    return "\n".join(lines)


def _extract_topics(text: str) -> List[str]:
    tokens = [token.lower() for token in re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", text)]
    stopwords = {
        "the", "and", "that", "with", "from", "this", "have", "your", "into", "about", "there",
        "would", "could", "should", "what", "when", "where", "while", "they", "them", "their",
        "project", "graphclaw", "assistant", "please", "thanks",
    }
    seen: List[str] = []
    for token in tokens:
        if token in stopwords or token in seen:
            continue
        seen.append(token)
        if len(seen) >= 3:
            break
    return seen


def consolidate_session(session_id: str) -> str | None:
    session = _load_session(session_id)
    if not session or session.get("consolidated"):
        return None

    turns = session.get("turns", [])
    if not turns:
        session["consolidated"] = True
        _save_session(session)
        return None

    saved = 0
    for turn in turns:
        if not isinstance(turn, dict):
            continue
        role = turn.get("role", "")
        content = str(turn.get("content", "")).strip()
        if role not in {"user", "assistant"} or not content:
            continue
        mem_type = "Project" if role == "assistant" else "User"
        store_memory(
            content=content[:500],
            mem_type=mem_type,
            confidence=0.6 if role == "assistant" else 0.7,
            source_session=session_id,
            agent=session.get("agent", "coordinator"),
            topics=_extract_topics(content),
        )
        saved += 1

    session["consolidated"] = True
    _save_session(session)
    return f"Consolidated {saved} turns from session {session_id}."


def consolidate_all(max_sessions: int = 10) -> List[str]:
    summaries: List[str] = []
    for session in list_sessions(unconsolidated_only=True)[:max_sessions]:
        summary = consolidate_session(str(session.get("session_id", "")))
        if summary:
            summaries.append(summary)
    return summaries


def dream_run(max_memories: int = 100, dry_run: bool = False) -> Dict[str, Any]:
    consolidate_all(max_sessions=20)

    memories = _load_memories()
    live = [memory for memory in memories if not memory.get("tombstoned")][:max_memories]

    tombstoned = 0
    revalidated = 0
    linked = 0
    tagged = 0

    for memory in live:
        if _effective_confidence(memory) <= 0.0:
            tombstoned += 1
            if not dry_run:
                memory["tombstoned"] = True
                memory["updated_at"] = _now()

    live = [memory for memory in live if not memory.get("tombstoned")]

    for memory in live:
        if 0.2 <= _effective_confidence(memory) <= 0.6:
            revalidated += 1
            if not dry_run:
                memory["last_validated_at"] = _now()
                memory["updated_at"] = memory["last_validated_at"]

        if not _memory_topics(memory):
            tags = _extract_topics(str(memory.get("content", "")))
            if tags:
                tagged += len(tags)
                if not dry_run:
                    memory["topics"] = tags
                    memory["updated_at"] = _now()

    for index, memory in enumerate(live):
        for other in live[index + 1:index + 4]:
            if memory.get("content") == other.get("content"):
                continue
            rels = _ensure_memory_relationships(memory)
            pair = {"to": other.get("id", ""), "relationship": "related_to", "weight": 0.5}
            if pair not in rels:
                linked += 1
                if not dry_run:
                    rels.append(pair)
                    memory["updated_at"] = _now()

    if not dry_run:
        _save_memories(memories)

    return {
        "tombstoned": tombstoned,
        "merged": 0,
        "revalidated": revalidated,
        "linked": linked,
        "tagged": tagged,
        "timestamp": _now(),
    }
