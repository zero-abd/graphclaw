"""LLM provider abstraction layer using litellm."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any


@dataclass
class ToolCallRequest:
    id: str
    name: str
    arguments: Dict[str, Any]


@dataclass
class LLMResponse:
    content: Optional[str] = None
    tool_calls: List[ToolCallRequest] = field(default_factory=list)
    finish_reason: str = "stop"
    prompt_tokens: int = 0
    completion_tokens: int = 0


@dataclass
class GenerationSettings:
    model: str = "openrouter/anthropic/claude-sonnet-4-6"
    max_tokens: int = 8192
    temperature: float = 0.7
    tools: Optional[List[Dict]] = None


class LLMProvider(ABC):
    @abstractmethod
    async def generate(
        self,
        messages: List[Dict[str, Any]],
        settings: GenerationSettings,
    ) -> LLMResponse:
        ...


class LiteLLMProvider(LLMProvider):
    """Universal provider using litellm — supports OpenRouter, Anthropic, OpenAI, Ollama, etc."""

    def __init__(self, model: str, api_key: str = "", base_url: str = ""):
        self.model = model
        self.api_key = api_key
        self.base_url = base_url

    async def generate(
        self,
        messages: List[Dict[str, Any]],
        settings: GenerationSettings,
    ) -> LLMResponse:
        import litellm

        kwargs: Dict[str, Any] = {
            "model": settings.model or self.model,
            "messages": messages,
            "max_tokens": settings.max_tokens,
            "temperature": settings.temperature,
        }
        if self.api_key:
            kwargs["api_key"] = self.api_key
        if self.base_url:
            kwargs["api_base"] = self.base_url
        if settings.tools:
            kwargs["tools"] = settings.tools

        try:
            resp = await litellm.acompletion(**kwargs)
        except Exception as e:
            return LLMResponse(content=f"[LLM error] {e}", finish_reason="error")

        msg = resp.choices[0].message
        tool_calls = []
        if msg.tool_calls:
            import json as _json
            for tc in msg.tool_calls:
                args = tc.function.arguments
                if isinstance(args, str):
                    try:
                        args = _json.loads(args)
                    except _json.JSONDecodeError:
                        args = {"raw": args}
                tool_calls.append(ToolCallRequest(
                    id=tc.id,
                    name=tc.function.name,
                    arguments=args,
                ))

        usage = resp.usage or {}
        return LLMResponse(
            content=msg.content,
            tool_calls=tool_calls,
            finish_reason=resp.choices[0].finish_reason or "stop",
            prompt_tokens=getattr(usage, "prompt_tokens", 0),
            completion_tokens=getattr(usage, "completion_tokens", 0),
        )
