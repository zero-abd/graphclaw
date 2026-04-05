"""Configuration loader with env-var overrides and caching."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Optional

from graphclaw.config.schema import Config

_config: Optional[Config] = None


def _default_config_path() -> Path:
    env = os.environ.get("GRAPHCLAW_CONFIG_PATH")
    if env:
        return Path(env)
    return Path.home() / ".graphclaw" / "config.json"


def load_config(path: Optional[str] = None, *, force_reload: bool = False) -> Config:
    global _config
    if _config is not None and not force_reload:
        return _config

    p = Path(path) if path else _default_config_path()
    if p.exists():
        data = json.loads(p.read_text(encoding="utf-8"))
    else:
        data = {}

    cfg = Config(**data)

    # env overrides
    if v := os.environ.get("OPENROUTER_API_KEY"):
        cfg.providers.setdefault("openrouter", {})["api_key"] = v
    if v := os.environ.get("ANTHROPIC_API_KEY"):
        cfg.providers.setdefault("anthropic", {})["api_key"] = v
    if v := os.environ.get("OPENAI_API_KEY"):
        cfg.providers.setdefault("openai", {})["api_key"] = v
    if v := os.environ.get("GRAPHCLAW_WORKSPACE"):
        cfg.workspace = v

    if not cfg.workspace:
        cfg.workspace = str(Path.home() / ".graphclaw" / "workspace")

    _config = cfg
    return cfg


def save_config(cfg: Config, path: Optional[str] = None) -> None:
    p = Path(path) if path else _default_config_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(cfg.model_dump(), indent=2, default=str), encoding="utf-8")


def ensure_workspace() -> None:
    cfg = load_config()
    ws = Path(cfg.workspace)
    for sub in ["memory", "sessions", "skills/installed"]:
        (ws / sub).mkdir(parents=True, exist_ok=True)
    (Path.home() / ".graphclaw" / "credentials").mkdir(parents=True, exist_ok=True)
