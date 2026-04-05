"""Jac byLLM skill matcher for semantic task-to-skill selection."""

::py::
import json
import os

from byllm.lib import MockLLM, Model

from graphclaw.config.loader import load_config


def _normalize_model_name(provider: str, model_name: str) -> str:
    if not model_name:
        return "gpt-4o-mini"
    if provider in {"openai", "anthropic"} and "/" in model_name:
        prefix = f"{provider}/"
        if model_name.startswith(prefix):
            return model_name[len(prefix):]
    return model_name


def build_skill_selector_model():
    mock_outputs = os.environ.get("GRAPHCLAW_SKILL_SELECTOR_MOCK_OUTPUTS", "").strip()
    if mock_outputs:
        try:
            outputs = json.loads(mock_outputs)
        except Exception:
            outputs = [mock_outputs]
        if not isinstance(outputs, list):
            outputs = [str(outputs)]
        return MockLLM(model_name="mockllm", config={"outputs": outputs})

    cfg = load_config()
    provider = str(cfg.providers.get("default_provider", "openrouter") or "openrouter")
    provider_cfg = cfg.providers.get(provider, {}) or {}
    model_name = os.environ.get("GRAPHCLAW_SKILL_SELECTOR_MODEL", "").strip() or cfg.agents.model
    model_name = _normalize_model_name(provider, model_name)

    model_kwargs = {"model_name": model_name}
    api_key = str(provider_cfg.get("api_key", "") or "").strip()
    if api_key:
        model_kwargs["api_key"] = api_key

    config = {}
    base_url = str(provider_cfg.get("base_url", "") or "").strip()
    if base_url:
        config["base_url"] = base_url
    if config:
        model_kwargs["config"] = config

    return Model(**model_kwargs)
::py::

glob llm = build_skill_selector_model();

obj SkillCandidate {
    has slug: str;
    has name: str = "";
    has description: str = "";
    has source: str = "";
    has tags: list[str] = [];
    has preview: str = "";
}

sem SkillCandidate = "Compact summary of one installed skill candidate.";
sem SkillCandidate.slug = "Unique installed skill slug. Use this exact slug if you recommend the skill.";
sem SkillCandidate.name = "Human-friendly skill name.";
sem SkillCandidate.description = "Short capability summary for the skill.";
sem SkillCandidate.source = "Where the skill came from, like local, clawhub, or bundled.";
sem SkillCandidate.tags = "Short topical tags or keywords associated with the skill.";
sem SkillCandidate.preview = "Compact excerpt from the skill body or metadata. Keep selection grounded in this summary.";

obj SkillMatch {
    has slug: str;
    has confidence: float = 0.0;
    has reason: str = "";
}

sem SkillMatch = "A semantic recommendation for an installed skill that matches the user's task.";
sem SkillMatch.slug = "Exact slug from the provided candidate list.";
sem SkillMatch.confidence = "Confidence from 0.0 to 1.0. Use higher scores only for strong, direct matches.";
sem SkillMatch.reason = "One short practical reason this skill helps with the task.";

def recommend_skill_matches(task: str, candidates: list[SkillCandidate], limit: int) -> list[SkillMatch] by llm(temperature=0.0, max_tokens=500);

sem recommend_skill_matches = """
Select the best installed skills for a user task.

Rules:
- Only return slugs that exist in the provided candidates list.
- Return at most `limit` matches.
- Prefer precise capability matches over broad or weak matches.
- Return an empty list if none of the candidates truly fit.
- Keep reasons short and actionable.
- Never invent skills or capabilities beyond the provided metadata.
""";
sem recommend_skill_matches.task = "The user task or request to match against installed skills.";
sem recommend_skill_matches.candidates = "Installed skill candidates with compact summaries. Use these as the only source of truth.";
sem recommend_skill_matches.limit = "Maximum number of skills to recommend.";
sem recommend_skill_matches.return = "Ordered best-match list from strongest match to weakest acceptable match.";
