"""Per-user platform credential storage for browser-assisted integrations."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


def _credentials_path() -> Path:
    path = Path.home() / ".graphclaw" / "credentials" / "platform-logins.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _read_payload() -> dict[str, Any]:
    path = _credentials_path()
    if not path.exists():
        return {"services": {}}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"services": {}}
    if not isinstance(payload, dict):
        return {"services": {}}
    payload.setdefault("services", {})
    return payload


def _write_payload(payload: dict[str, Any]) -> None:
    path = _credentials_path()
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except Exception:
        pass


def _user_key(channel: str, chat_id: str, user_id: str) -> str:
    return f"{channel}:{chat_id}:{user_id}"


def save_service_credentials(
    service: str,
    *,
    channel: str,
    chat_id: str,
    user_id: str,
    username: str,
    password: str,
) -> None:
    payload = _read_payload()
    payload.setdefault("services", {}).setdefault(service, {})[_user_key(channel, chat_id, user_id)] = {
        "username": username,
        "password": password,
    }
    _write_payload(payload)


def get_service_credentials(
    service: str,
    *,
    channel: str,
    chat_id: str,
    user_id: str,
) -> dict[str, str] | None:
    payload = _read_payload()
    item = payload.get("services", {}).get(service, {}).get(_user_key(channel, chat_id, user_id))
    if not isinstance(item, dict):
        return None
    username = str(item.get("username", "") or "").strip()
    password = str(item.get("password", "") or "")
    if not username or not password:
        return None
    return {"username": username, "password": password}


def clear_service_credentials(
    service: str,
    *,
    channel: str,
    chat_id: str,
    user_id: str,
) -> bool:
    payload = _read_payload()
    service_map = payload.get("services", {}).get(service, {})
    removed = service_map.pop(_user_key(channel, chat_id, user_id), None) is not None
    _write_payload(payload)
    return removed
