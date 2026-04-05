"""User-approved skill acquisition flow for missing capabilities."""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from graphclaw.skills.loader import install_skill, recommend_skills, search_installable_skills

STRONG_INSTALLED_THRESHOLD = 0.75
INSTALL_PROPOSAL_THRESHOLD = 0.60
PENDING_TTL_SECONDS = 1800


def _state_path() -> Path:
    path = Path.home() / ".graphclaw" / "state" / "skill-install-approvals.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _read_state() -> dict[str, Any]:
    path = _state_path()
    if not path.exists():
        return {"pending": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"pending": {}}
    if not isinstance(data, dict):
        return {"pending": {}}
    data.setdefault("pending", {})
    return data


def _write_state(payload: dict[str, Any]) -> None:
    _state_path().write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _approval_key(channel: str, chat_id: str, user_id: str) -> str:
    return f"{channel}:{chat_id}:{user_id}"


def _purge_expired(state: dict[str, Any]) -> dict[str, Any]:
    now = time.time()
    pending = state.get("pending", {})
    state["pending"] = {
        key: value
        for key, value in pending.items()
        if float(value.get("expires_at", 0)) > now
    }
    return state


def _affirmative(text: str) -> bool:
    normalized = text.strip().lower()
    return normalized in {
        "y", "yes", "yeah", "yep", "ok", "okay", "sure", "do it", "install it",
        "approve", "approved", "go ahead", "please do", "yes install", "install",
    }


def _negative(text: str) -> bool:
    normalized = text.strip().lower()
    return normalized in {"n", "no", "nah", "nope", "decline", "cancel", "dont", "don't", "skip"}


async def propose_skill_install(
    task: str,
    *,
    channel: str,
    chat_id: str,
    user_id: str,
    limit: int = 3,
) -> str:
    installed = recommend_skills(task, limit=1)
    if (
        installed
        and installed[0].get("confidence", 0.0) >= STRONG_INSTALLED_THRESHOLD
        and int(installed[0].get("keyword_overlap", 0) or 0) >= 2
    ):
        best = installed[0]
        return (
            f"A strong installed skill already exists for this task: `{best['slug']}` "
            f"({best['confidence']:.2f}). Use `invoke_skill` on it instead of installing a new one."
        )

    candidates = await search_installable_skills(task, limit=limit)
    if candidates and isinstance(candidates[0], dict) and candidates[0].get("error"):
        return f"ClawHub search failed: {candidates[0]['error']}"
    if not candidates:
        return "I couldn't find a strong installed skill or a strong ClawHub skill for this task."

    best = candidates[0]
    if float(best.get("confidence", 0.0) or 0.0) < INSTALL_PROPOSAL_THRESHOLD:
        return (
            "I found some ClawHub skills, but none matched strongly enough to recommend installing automatically. "
            "Try refining the task or search ClawHub manually."
        )

    state = _purge_expired(_read_state())
    state["pending"][_approval_key(channel, chat_id, user_id)] = {
        "slug": best["slug"],
        "source": best["slug"],
        "reason": best.get("reason", ""),
        "task": task,
        "created_at": time.time(),
        "expires_at": time.time() + PENDING_TTL_SECONDS,
    }
    _write_state(state)
    return (
        f"I couldn't find a strong installed skill for this task. I found `{best['slug']}` on ClawHub "
        f"({best.get('reason', best.get('description', 'good match'))}). "
        "Reply `yes` to install it, or `no` to continue without installing anything."
    )


async def maybe_handle_skill_install_reply(
    text: str,
    *,
    channel: str,
    chat_id: str,
    user_id: str,
) -> dict[str, Any] | None:
    state = _purge_expired(_read_state())
    key = _approval_key(channel, chat_id, user_id)
    pending = state.get("pending", {}).get(key)
    if not pending:
        _write_state(state)
        return None

    if not (_affirmative(text) or _negative(text)):
        _write_state(state)
        return None

    state["pending"].pop(key, None)
    _write_state(state)

    slug = str(pending.get("slug", "") or "").strip()
    original_task = str(pending.get("task", "") or "").strip()

    if _negative(text):
        return {
            "handled": True,
            "message": f"Okay — I won't install `{slug}`. I'll continue without adding a new skill.",
            "resume_query": (
                f"The user declined installing the ClawHub skill `{slug}`. "
                f"Continue without installing new skills.\n\nOriginal user task:\n{original_task}"
            ),
        }

    install_result = await install_skill(str(pending.get("source", slug)))
    if not install_result.startswith("Installed") and "already installed" not in install_result:
        return {
            "handled": True,
            "message": f"I tried to install `{slug}`, but it failed: {install_result}",
            "resume_query": None,
        }

    return {
        "handled": True,
        "message": f"Installed `{slug}`. Continuing with your original task now.",
        "resume_query": (
            f"The user approved installing the ClawHub skill `{slug}` and it is installed now. "
            f"Use it if it helps.\n\nOriginal user task:\n{original_task}"
        ),
    }
