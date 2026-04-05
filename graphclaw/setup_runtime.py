"""Interactive runtime setup helpers for first-run and missing-key recovery."""
from __future__ import annotations

import os
from dataclasses import dataclass
import sys
from pathlib import Path
from typing import Callable

from graphclaw.config.loader import load_config, save_config


@dataclass
class SetupPromptResult:
    action: str = "none"
    message: str = ""
    provider: str = ""


def _config_path() -> Path:
    env = os.environ.get("GRAPHCLAW_CONFIG_PATH")
    if env:
        return Path(env)
    return Path.home() / ".graphclaw" / "config.json"


def _env_path() -> Path:
    return _config_path().parent / ".env"


def _provider_needing_key() -> str:
    cfg = load_config(force_reload=True)
    provider = str(cfg.providers.get("default_provider", "openrouter")).strip().lower() or "openrouter"
    if provider in {"openrouter", "anthropic", "openai"}:
        entry = cfg.providers.get(provider, {})
        if not entry.get("api_key"):
            return provider
    return ""


def _write_env_key(provider: str, value: str) -> None:
    env_map: dict[str, str] = {}
    env_path = _env_path()
    if env_path.exists():
        for raw in env_path.read_text(encoding="utf-8").splitlines():
            if not raw or raw.lstrip().startswith("#") or "=" not in raw:
                continue
            key, item = raw.split("=", 1)
            env_map[key] = item
    key_name = {
        "openrouter": "OPENROUTER_API_KEY",
        "anthropic": "ANTHROPIC_API_KEY",
        "openai": "OPENAI_API_KEY",
    }[provider]
    env_map["GRAPHCLAW_CONFIG_PATH"] = str(_config_path())
    env_map[key_name] = value
    lines = ["# Graphclaw environment"]
    for key, item in env_map.items():
        if item:
            lines.append(f"{key}={item}")
    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def maybe_prompt_for_provider_key(
    *,
    input_fn: Callable[[str], str] = input,
    print_fn: Callable[[str], None] = print,
) -> SetupPromptResult:
    if not sys.stdin or not sys.stdin.isatty():
        return SetupPromptResult(action="noninteractive")

    provider = _provider_needing_key()
    if not provider:
        return SetupPromptResult(action="none")

    prompts = {
        "openrouter": (
            "OpenRouter",
            "https://openrouter.ai/keys",
            "OPENROUTER_API_KEY",
        ),
        "anthropic": (
            "Anthropic",
            "https://console.anthropic.com/settings/keys",
            "ANTHROPIC_API_KEY",
        ),
        "openai": (
            "OpenAI",
            "https://platform.openai.com/api-keys",
            "OPENAI_API_KEY",
        ),
    }
    label, url, _ = prompts[provider]
    print_fn(f"[graphclaw] {label} API key is missing.")
    print_fn(f"[graphclaw] Get one here: {url}")
    answer = input_fn(f"[graphclaw] Paste {label} API key now (or press Enter to skip): ").strip()
    if not answer:
        return SetupPromptResult(action="skipped", provider=provider)

    cfg = load_config(force_reload=True)
    cfg.providers.setdefault(provider, {})["api_key"] = answer
    save_config(cfg)
    _write_env_key(provider, answer)
    os.environ[{"openrouter": "OPENROUTER_API_KEY", "anthropic": "ANTHROPIC_API_KEY", "openai": "OPENAI_API_KEY"}[provider]] = answer
    load_config(force_reload=True)
    return SetupPromptResult(action="saved", provider=provider, message=f"Saved {label} API key.")
