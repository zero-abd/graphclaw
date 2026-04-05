"""Managed update + rollback helpers for Graphclaw installs."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from graphclaw.config.loader import ensure_workspace


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _home_dir() -> Path:
    env_home = os.environ.get("GRAPHCLAW_HOME")
    if env_home:
        return Path(env_home)
    return Path.home() / ".graphclaw"


def source_dir() -> Path:
    return _home_dir() / "source"


def venv_dir() -> Path:
    return _home_dir() / "venv"


def state_dir() -> Path:
    path = _home_dir() / "state"
    path.mkdir(parents=True, exist_ok=True)
    return path


def rollback_file() -> Path:
    return state_dir() / "last-update.json"


def _pip_path() -> Path:
    if os.name == "nt":
        return venv_dir() / "Scripts" / "pip.exe"
    return venv_dir() / "bin" / "pip"


def _git(args: list[str], *, cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=str(cwd or source_dir()),
        text=True,
        capture_output=True,
        check=check,
    )


def _load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def _save_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")


def _repo_exists() -> bool:
    return (source_dir() / ".git").exists()


def _current_branch() -> str:
    if not _repo_exists():
        return "main"
    result = _git(["rev-parse", "--abbrev-ref", "HEAD"], check=False)
    branch = (result.stdout or "").strip()
    if not branch or branch == "HEAD":
        return "main"
    return branch


def _current_commit() -> str:
    if not _repo_exists():
        return ""
    result = _git(["rev-parse", "HEAD"], check=False)
    return (result.stdout or "").strip()


def _tracked_upstream() -> str:
    return "origin/main"


def _ensure_clean_repo() -> None:
    result = _git(["status", "--porcelain"], check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Unable to inspect git status")
    if result.stdout.strip():
        raise RuntimeError("Managed source has local changes; aborting update to avoid overwriting them")


def get_update_status(fetch: bool = True) -> dict[str, Any]:
    if not _repo_exists():
        return {"managed": False, "available": False, "reason": "source repo not installed"}

    branch = _current_branch()
    current = _current_commit()
    if fetch:
        _git(["fetch", "origin"], check=False)
    upstream = _tracked_upstream()
    remote = _git(["rev-parse", upstream], check=False)
    if remote.returncode != 0:
        return {
            "managed": True,
            "available": False,
            "branch": branch,
            "current": current,
            "reason": remote.stderr.strip() or f"Unable to resolve {upstream}",
        }

    latest = (remote.stdout or "").strip()
    counts = _git(["rev-list", "--left-right", "--count", f"{current}...{latest}"], check=False)
    ahead = behind = 0
    if counts.returncode == 0:
        parts = (counts.stdout or "0\t0").strip().split()
        if len(parts) >= 2:
            ahead = int(parts[0])
            behind = int(parts[1])

    return {
        "managed": True,
        "available": behind > 0,
        "branch": branch,
        "current": current,
        "latest": latest,
        "ahead": ahead,
        "behind": behind,
        "upstream": upstream,
    }


def _reinstall_package() -> None:
    pip_cmd = _pip_path()
    if not pip_cmd.exists():
        raise RuntimeError(f"pip not found at {pip_cmd}")
    subprocess.run([str(pip_cmd), "install", "-e", str(source_dir()), "-q"], check=True)


def perform_update() -> dict[str, Any]:
    status = get_update_status(fetch=True)
    if not status.get("managed"):
        raise RuntimeError(status.get("reason", "Managed source repo is unavailable"))
    if not status.get("available"):
        return {"updated": False, "reason": "Already up to date", **status}

    ensure_workspace()
    _ensure_clean_repo()
    previous_commit = status["current"]
    previous_branch = status["branch"]
    upstream = status["upstream"]

    _git(["checkout", "-B", "main", upstream])
    _git(["reset", "--hard", upstream])
    _reinstall_package()

    updated_status = get_update_status(fetch=False)
    payload = {
        "previous_commit": previous_commit,
        "previous_branch": previous_branch,
        "updated_at": _now(),
        "new_commit": updated_status.get("current", ""),
        "upstream": upstream,
    }
    _save_json(rollback_file(), payload)
    return {"updated": True, **updated_status, "rollback": payload}


def perform_rollback() -> dict[str, Any]:
    if not _repo_exists():
        raise RuntimeError("Managed source repo is unavailable")
    payload = _load_json(rollback_file(), {})
    previous_commit = str(payload.get("previous_commit", "")).strip()
    previous_branch = str(payload.get("previous_branch", "main")).strip() or "main"
    if not previous_commit:
        raise RuntimeError("No rollback information found")

    _ensure_clean_repo()
    _git(["checkout", "-B", previous_branch, previous_commit])
    _reinstall_package()

    status = get_update_status(fetch=False)
    payload["rolled_back_at"] = _now()
    _save_json(rollback_file(), payload)
    return {"rolled_back": True, **status, "rollback": payload}


@dataclass
class PromptResult:
    action: str = "none"
    message: str = ""
    details: dict[str, Any] | None = None


def maybe_prompt_for_update(*, input_fn=input, print_fn=print) -> PromptResult:
    if not sys.stdin or not sys.stdin.isatty():
        return PromptResult(action="noninteractive")

    try:
        status = get_update_status(fetch=True)
    except Exception as exc:  # pragma: no cover - defensive startup path
        return PromptResult(action="error", message=str(exc))

    if not status.get("managed") or not status.get("available"):
        return PromptResult(action="none", details=status)

    current = (status.get("current") or "")[:7]
    latest = (status.get("latest") or "")[:7]
    behind = status.get("behind", 0)
    print_fn(f"[graphclaw] Update available: {current or 'unknown'} -> {latest or 'unknown'} ({behind} commit(s)).")
    answer = input_fn("[graphclaw] Update now? [Y/n]: ").strip().lower()
    if answer not in {"", "y", "yes"}:
        return PromptResult(action="skipped", details=status)

    try:
        result = perform_update()
    except Exception as exc:
        return PromptResult(action="error", message=str(exc), details=status)

    message = (
        "Graphclaw updated successfully. Restart Graphclaw to use the new version. "
        "If you want to revert, run `graphclaw rollback`."
    )
    return PromptResult(action="updated", message=message, details=result)


def _print_status() -> None:
    status = get_update_status(fetch=True)
    if not status.get("managed"):
        print(status.get("reason", "Managed source repo is unavailable"))
        return
    if status.get("available"):
        print(
            f"Update available: {status['current'][:7]} -> {status['latest'][:7]} "
            f"({status['behind']} commit(s))"
        )
    else:
        print(f"Up to date at {status.get('current', '')[:7]}")


def main(argv: list[str] | None = None) -> int:
    args = list(argv or sys.argv[1:])
    command = args[0] if args else "status"
    try:
        if command == "status":
            _print_status()
            return 0
        if command == "update":
            result = perform_update()
            if result.get("updated"):
                print("Update complete. Restart Graphclaw to use the new version.")
                print("If needed, run `graphclaw rollback` to revert the last update.")
            else:
                print(result.get("reason", "Already up to date"))
            return 0
        if command == "rollback":
            perform_rollback()
            print("Rollback complete. Restart Graphclaw to use the reverted version.")
            return 0
        if command == "version":
            print(_current_commit()[:7] or "unknown")
            return 0
        print(f"Unknown command: {command}")
        return 1
    except Exception as exc:
        print(f"[graphclaw] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
