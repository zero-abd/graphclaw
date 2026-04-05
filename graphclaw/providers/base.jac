# graphclaw/providers/base.jac
# LLM provider abstraction -- mirrors nanobot's provider layer, ported to Jac
# All providers speak the same interface; byllm/litellm handles the heavy lifting

import from dataclasses { dataclass, field }
import from typing { AsyncGenerator }
import from abc { ABC, abstractmethod }

obj ToolCallRequest {
    has id: str;
    has name: str;
    has arguments: dict;
}

obj LLMResponse {
    has content: str = "";
    has tool_calls: list[ToolCallRequest] = [];
    has finish_reason: str = "stop";   # stop | tool_calls | length
    has input_tokens: int = 0;
    has output_tokens: int = 0;
    has model: str = "";
    has cached: bool = False;
}

obj GenerationSettings {
    has model: str;
    has temperature: float = 0.7;
    has max_tokens: int = 8192;
    has system_prompt: str = "";
    has tools: list[dict] = [];        # OpenAI-format tool definitions
    has stream: bool = False;
    has reasoning_effort: str = "";    # "" | "low" | "medium" | "high"
    has extra: dict = {};
}

# -- Base provider ABC ---------------------------------------------------------

obj LLMProvider {
    has name: str;
    has api_key: str = "";
    has base_url: str = "";
    has default_model: str = "";

    def chat_completion(
        messages: list[dict],
        settings: GenerationSettings
    ) -> LLMResponse abs;

    def stream_completion(
        messages: list[dict],
        settings: GenerationSettings
    ) -> AsyncGenerator abs;

    def build_tool_definitions(tools: list) -> list[dict] {
        # Convert graphclaw tool objects → OpenAI function-call format
        defs = [];
        for t in tools {
            defs.append({
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.parameters_schema
                }
            });
        }
        return defs;
    }

    def is_available() -> bool {
        return bool(self.api_key) or bool(self.base_url);
    }
}

# -- OpenAI-compatible provider (used by OpenRouter, DeepSeek, Groq, etc.) ----

obj OpenAICompatProvider(LLMProvider) {
    def chat_completion(
        messages: list[dict],
        settings: GenerationSettings
    ) -> LLMResponse {
        ::py::
        import litellm, os

        kwargs = {
            "model": settings.model,
            "messages": messages,
            "temperature": settings.temperature,
            "max_tokens": settings.max_tokens,
            "api_key": self.api_key or None,
        }
        if self.base_url:
            kwargs["api_base"] = self.base_url
        if settings.tools:
            kwargs["tools"] = settings.tools
            kwargs["tool_choice"] = "auto"
        if settings.reasoning_effort:
            kwargs["thinking"] = {"type": "enabled", "budget_tokens": {
                "low": 1024, "medium": 4096, "high": 10000
            }.get(settings.reasoning_effort, 4096)}

        resp = litellm.completion(**kwargs)
        msg = resp.choices[0].message
        tool_calls = []
        if msg.tool_calls:
            import json
            for tc in msg.tool_calls:
                tool_calls.append(ToolCallRequest(
                    id=tc.id,
                    name=tc.function.name,
                    arguments=json.loads(tc.function.arguments or "{}")
                ))
        _result = LLMResponse(
            content=msg.content or "",
            tool_calls=tool_calls,
            finish_reason=resp.choices[0].finish_reason or "stop",
            input_tokens=getattr(resp.usage, "prompt_tokens", 0),
            output_tokens=getattr(resp.usage, "completion_tokens", 0),
            model=resp.model or settings.model,
        )
        ::py::
        return _result;
    }

    def stream_completion(
        messages: list[dict],
        settings: GenerationSettings
    ) -> AsyncGenerator {
        ::py::
        import litellm

        kwargs = {
            "model": settings.model,
            "messages": messages,
            "temperature": settings.temperature,
            "max_tokens": settings.max_tokens,
            "api_key": self.api_key or None,
            "stream": True,
        }
        if self.base_url:
            kwargs["api_base"] = self.base_url
        if settings.tools:
            kwargs["tools"] = settings.tools
            kwargs["tool_choice"] = "auto"

        async def _gen():
            async for chunk in await litellm.acompletion(**kwargs):
                delta = chunk.choices[0].delta
                if delta.content:
                    yield delta.content

        _stream_gen = _gen()
        ::py::
        return _stream_gen;
    }
}

# -- Anthropic provider (direct, for prompt caching support) ------------------

obj AnthropicProvider(LLMProvider) {
    has name: str = "anthropic";
    has default_model: str = "claude-sonnet-4-6";

    def chat_completion(
        messages: list[dict],
        settings: GenerationSettings
    ) -> LLMResponse {
        ::py::
        import litellm

        model = settings.model
        if not model.startswith("claude"):
            model = self.default_model

        kwargs = {
            "model": f"anthropic/{model}",
            "messages": messages,
            "temperature": settings.temperature,
            "max_tokens": settings.max_tokens,
            "api_key": self.api_key or None,
        }
        if settings.tools:
            kwargs["tools"] = settings.tools
            kwargs["tool_choice"] = "auto"

        resp = litellm.completion(**kwargs)
        msg = resp.choices[0].message
        tool_calls = []
        if msg.tool_calls:
            import json
            for tc in msg.tool_calls:
                tool_calls.append(ToolCallRequest(
                    id=tc.id,
                    name=tc.function.name,
                    arguments=json.loads(tc.function.arguments or "{}")
                ))
        _result = LLMResponse(
            content=msg.content or "",
            tool_calls=tool_calls,
            finish_reason=resp.choices[0].finish_reason or "stop",
            input_tokens=getattr(resp.usage, "prompt_tokens", 0),
            output_tokens=getattr(resp.usage, "completion_tokens", 0),
            model=resp.model or model,
        )
        ::py::
        return _result;
    }

    def stream_completion(messages: list[dict], settings: GenerationSettings) -> AsyncGenerator {
        # Delegate to OpenAI-compat path via litellm
        compat = OpenAICompatProvider(
            name="anthropic_compat",
            api_key=self.api_key,
            base_url=""
        );
        return compat.stream_completion(messages, settings);
    }
}
