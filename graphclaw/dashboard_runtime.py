"""Runtime helpers for launching and managing the local dashboard server."""
from __future__ import annotations

import atexit
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import webbrowser
from pathlib import Path
from typing import Any

from graphclaw.config.loader import load_config

_DASHBOARD_PROC: subprocess.Popen | None = None


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _graphclaw_home() -> Path:
    env = os.environ.get("GRAPHCLAW_HOME")
    if env:
        return Path(env)
    return Path.home() / ".graphclaw"


def _state_path() -> Path:
    path = _graphclaw_home() / "state" / "dashboard-server.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _log_path() -> Path:
    path = _graphclaw_home() / "logs" / "dashboard-server.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def _dashboard_config() -> dict[str, Any]:
    cfg = load_config(force_reload=True)
    dashboard = getattr(cfg, "dashboard", {}) or {}
    if not isinstance(dashboard, dict):
        dashboard = {}
    return {
        "enabled": bool(dashboard.get("enabled", True)),
        "auto_open": bool(dashboard.get("auto_open", True)),
        "host": str(dashboard.get("host", "127.0.0.1")),
        "port": int(dashboard.get("port", 18789)),
    }


def dashboard_url() -> str:
    cfg = _dashboard_config()
    return f"http://{cfg['host']}:{cfg['port']}/"


def _jac_executable() -> str:
    jac = shutil.which("jac")
    return jac or "jac"


def _is_dashboard_reachable(url: str, timeout: float = 0.4) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return 200 <= int(response.status) < 500
    except Exception:
        return False


def _read_state() -> dict[str, Any]:
    path = _state_path()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _write_state(payload: dict[str, Any]) -> None:
    _state_path().write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def _cleanup_stale_state(url: str) -> None:
    state = _read_state()
    pid = int(state.get("pid", 0) or 0)
    if pid and _pid_alive(pid) and _is_dashboard_reachable(url):
        return
    if _state_path().exists():
        _state_path().unlink(missing_ok=True)


def ensure_local_dashboard(open_browser: bool = True) -> str | None:
    global _DASHBOARD_PROC
    cfg = _dashboard_config()
    if not cfg["enabled"] or os.environ.get("GRAPHCLAW_DASHBOARD_DISABLE") in {"1", "true", "yes"}:
        return None

    url = dashboard_url()
    _cleanup_stale_state(url)
    state = _read_state()
    pid = int(state.get("pid", 0) or 0)
    if pid and _pid_alive(pid) and _is_dashboard_reachable(url):
        if open_browser and cfg["auto_open"]:
            webbrowser.open(url)
        return url

    log_handle = _log_path().open("a", encoding="utf-8")
    env = dict(os.environ)
    env.setdefault("GRAPHCLAW_CONFIG_PATH", os.environ.get("GRAPHCLAW_CONFIG_PATH", ""))
    env.setdefault("GRAPHCLAW_HOME", str(_graphclaw_home()))
    cmd = [_jac_executable(), "start", "graphclaw/dashboard.jac", "--dev", "--port", str(cfg["port"])]
    proc = subprocess.Popen(
        cmd,
        cwd=str(_repo_root()),
        env=env,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )
    _DASHBOARD_PROC = proc
    _write_state({"pid": proc.pid, "url": url, "started_at": time.time()})

    def _shutdown_dashboard() -> None:
        global _DASHBOARD_PROC
        if _DASHBOARD_PROC and _DASHBOARD_PROC.poll() is None:
            _DASHBOARD_PROC.terminate()
            try:
                _DASHBOARD_PROC.wait(timeout=3)
            except Exception:
                _DASHBOARD_PROC.kill()
        _DASHBOARD_PROC = None
        _state_path().unlink(missing_ok=True)

    atexit.register(_shutdown_dashboard)

    for _ in range(30):
        if _is_dashboard_reachable(url):
            if open_browser and cfg["auto_open"]:
                webbrowser.open(url)
            return url
        if proc.poll() is not None:
            break
        time.sleep(0.2)

    return url
