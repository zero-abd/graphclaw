"""Provider resolution — maps model strings to LLMProvider instances."""
from __future__ import annotations

from typing import Dict, Optional

from graphclaw.config.loader import load_config
from graphclaw.providers.base import LLMProvider, LiteLLMProvider

_cache: Dict[str, LLMProvider] = {}


def get_provider(model: Optional[str] = None) -> LLMProvider:
    cfg = load_config()
    model = model or cfg.agents.model

    if model in _cache:
        return _cache[model]

    providers = cfg.providers
    prefix = model.split("/")[0] if "/" in model else ""

    api_key = ""
    base_url = ""

    if prefix == "openrouter" or providers.get("default_provider") == "openrouter":
        p = providers.get("openrouter", {})
        api_key = p.get("api_key", "")
        base_url = p.get("base_url", "https://openrouter.ai/api/v1")
    elif prefix == "anthropic":
        api_key = providers.get("anthropic", {}).get("api_key", "")
    elif prefix == "openai":
        api_key = providers.get("openai", {}).get("api_key", "")
    elif prefix == "ollama":
        base_url = "http://localhost:11434"
    elif prefix in ("deepseek", "groq"):
        p = providers.get(prefix, {})
        api_key = p.get("api_key", "")
        base_url = p.get("base_url", "")

    provider = LiteLLMProvider(model=model, api_key=api_key, base_url=base_url)
    _cache[model] = provider
    return provider
