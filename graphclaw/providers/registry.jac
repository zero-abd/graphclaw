# graphclaw/providers/registry.jac
# Maps model strings to providers — same multi-provider approach as nanobot

import from graphclaw.providers.base {
    LLMProvider, OpenAICompatProvider, AnthropicProvider, GenerationSettings
};
import from graphclaw.config.loader { load_config };

glob _provider_cache: dict = {};

def get_provider(model: str = "") -> LLMProvider {
    global _provider_cache;
    cfg = load_config();

    if not model { model = cfg.agents.model; }

    # Check cache
    if model in _provider_cache { return _provider_cache[model]; }

    provider = _resolve_provider(model, cfg);
    _provider_cache[model] = provider;
    return provider;
}

def _resolve_provider(model: str, cfg) -> LLMProvider {
    m = model.lower();

    # OpenRouter (default) — handles almost everything
    if m.startswith("openrouter/") or "/" not in m {
        or_model = model if "/" in model else f"openrouter/{model}";
        return OpenAICompatProvider(
            name="openrouter",
            api_key=cfg.providers.openrouter.api_key,
            base_url="https://openrouter.ai/api/v1",
            default_model=or_model
        );
    }

    if m.startswith("anthropic/") or m.startswith("claude") {
        return AnthropicProvider(
            api_key=cfg.providers.anthropic.api_key or cfg.providers.openrouter.api_key
        );
    }

    if m.startswith("openai/") or m.startswith("gpt") {
        return OpenAICompatProvider(
            name="openai",
            api_key=cfg.providers.openai.api_key,
            base_url="https://api.openai.com/v1",
            default_model=model
        );
    }

    if m.startswith("deepseek") {
        return OpenAICompatProvider(
            name="deepseek",
            api_key=cfg.providers.custom.api_key,
            base_url="https://api.deepseek.com/v1",
            default_model=model
        );
    }

    if m.startswith("groq/") or m.startswith("groq-") {
        return OpenAICompatProvider(
            name="groq",
            api_key=cfg.providers.custom.api_key,
            base_url="https://api.groq.com/openai/v1",
            default_model=model
        );
    }

    if m.startswith("ollama/") {
        return OpenAICompatProvider(
            name="ollama",
            api_key="ollama",
            base_url=cfg.providers.ollama.base_url or "http://localhost:11434",
            default_model=model
        );
    }

    # Fallback: treat as OpenRouter model
    return OpenAICompatProvider(
        name="openrouter",
        api_key=cfg.providers.openrouter.api_key,
        base_url="https://openrouter.ai/api/v1",
        default_model=f"openrouter/{model}"
    );
}

def list_providers() -> list[str] {
    return ["openrouter", "anthropic", "openai", "deepseek", "groq", "ollama", "custom"];
}
