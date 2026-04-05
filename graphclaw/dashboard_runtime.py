"""Runtime helpers for launching and managing the local dashboard server."""
from __future__ import annotations

import atexit
import json
import os
import shutil
import subprocess
import sys
import time
import tomllib
import urllib.request
import webbrowser
from pathlib import Path
from typing import Any

from graphclaw.config.loader import load_config

_DASHBOARD_PROC: subprocess.Popen | None = None


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _dashboard_project_root() -> Path:
    return Path(__file__).resolve().parent / "dashboard_app"


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


def _dashboard_client_dir() -> Path:
    return _dashboard_project_root() / ".jac" / "client"


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


def dashboard_api_url() -> str:
    cfg = _dashboard_config()
    return f"http://{cfg['host']}:{cfg['port'] + 1}/"


def _jac_executable() -> str:
    jac = shutil.which("jac")
    return jac or "jac"


def _with_repo_on_pythonpath(env: dict[str, str]) -> dict[str, str]:
    updated = dict(env)
    repo_root = str(_repo_root())
    current = updated.get("PYTHONPATH", "")
    if current:
        entries = current.split(os.pathsep)
        if repo_root not in entries:
            updated["PYTHONPATH"] = os.pathsep.join([repo_root, *entries])
    else:
        updated["PYTHONPATH"] = repo_root
    return updated


def _is_dashboard_reachable(url: str, timeout: float = 0.4) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            return 200 <= int(response.status) < 500
    except Exception:
        return False


def _recent_log_excerpt() -> str:
    path = _log_path()
    if not path.exists():
        return ""
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        return ""
    excerpt = text[-1200:].strip()
    return excerpt


def _ensure_dashboard_client_sync() -> None:
    jac_toml = _dashboard_project_root() / "jac.toml"
    package_json = _dashboard_client_dir() / "configs" / "package.json"
    helper_src = _dashboard_project_root() / "graph_helpers.js"
    helper_dest = _dashboard_client_dir() / "compiled" / "graph_helpers.js"
    if not jac_toml.exists() or not package_json.exists():
        if helper_src.exists():
            helper_dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(helper_src, helper_dest)
        return
    try:
        jac_data = tomllib.loads(jac_toml.read_text(encoding="utf-8"))
        package_data = json.loads(package_json.read_text(encoding="utf-8"))
    except Exception:
        return

    expected = set((jac_data.get("dependencies", {}) or {}).get("npm", {}).keys())
    actual = set((package_data.get("dependencies") or {}).keys())
    if expected - actual:
        shutil.rmtree(_dashboard_client_dir(), ignore_errors=True)
    if helper_src.exists():
        helper_dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(helper_src, helper_dest)


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
    api_url = dashboard_api_url()
    _cleanup_stale_state(url)
    state = _read_state()
    pid = int(state.get("pid", 0) or 0)
    if pid and _pid_alive(pid) and _is_dashboard_reachable(url):
        if open_browser and cfg["auto_open"]:
            webbrowser.open(url)
        return url

    _ensure_dashboard_client_sync()
    log_handle = _log_path().open("a", encoding="utf-8")
    env = _with_repo_on_pythonpath(dict(os.environ))
    env.setdefault("GRAPHCLAW_CONFIG_PATH", os.environ.get("GRAPHCLAW_CONFIG_PATH", ""))
    env.setdefault("GRAPHCLAW_HOME", str(_graphclaw_home()))
    cmd = [_jac_executable(), "start", "--dev", "--port", str(cfg["port"])]
    proc = subprocess.Popen(
        cmd,
        cwd=str(_dashboard_project_root()),
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

    for _ in range(60):
        if _is_dashboard_reachable(url):
            if open_browser and cfg["auto_open"]:
                webbrowser.open(url)
            return url
        if proc.poll() is not None:
            break
        time.sleep(0.5)

    if proc.poll() is None and _is_dashboard_reachable(api_url):
        raise RuntimeError(
            "Dashboard API started, but the web UI did not become reachable. "
            "Make sure jac-client and bun are installed, then try again.\n"
            + _recent_log_excerpt()
        )

    raise RuntimeError(
        "Dashboard web UI failed to start.\n"
        + (_recent_log_excerpt() or "No dashboard logs were captured.")
    )
