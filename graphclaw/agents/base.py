"""Base agent with tool-calling loop, modeled after nanobot's AgentRunner."""
from __future__ import annotations
import json
import traceback
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional
from graphclaw.providers.registry import get_provider
from graphclaw.providers.base import GenerationSettings, LLMResponse, ToolCallRequest
from graphclaw.config.loader import load_config


@dataclass
class AgentResult:
    content: str = ""
    tools_used: List[str] = field(default_factory=list)
    prompt_tokens: int = 0
    completion_tokens: int = 0
    error: Optional[str] = None


class BaseAgent:
    """Base agent with iterative tool-calling loop."""

    name: str = "base"
    system_prompt: str = "You are a helpful assistant."
    tools: List[Any] = []

    def __init__(
        self,
        query: str = "",
        channel: str = "cli",
        chat_id: str = "local",
        user_id: str = "user",
        model: Optional[str] = None,
    ):
        self.query = query
        self.channel = channel
        self.chat_id = chat_id
        self.user_id = user_id
        self._model = model

    def _get_tool_schemas(self) -> List[Dict]:
        schemas = []
        for tool in self.tools:
            schemas.append({
                "type": "function",
                "function": {
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters,
                },
            })
        return schemas

    def _find_tool(self, name: str) -> Optional[Any]:
        for tool in self.tools:
            if tool.name == name:
                return tool
        return None

    async def run(self) -> AgentResult:
        cfg = load_config()
        model = self._model or cfg.agents.model
        provider = get_provider(model)

        messages: List[Dict[str, Any]] = [
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": self.query},
        ]

        tool_schemas = self._get_tool_schemas()
        settings = GenerationSettings(
            model=model,
            max_tokens=cfg.agents.max_tokens,
            temperature=cfg.agents.temperature,
            tools=tool_schemas or None,
        )

        result = AgentResult()
        max_iters = cfg.agents.max_tool_iterations

        for _ in range(max_iters):
            try:
                resp = await provider.generate(messages, settings)
            except Exception as e:
                result.error = str(e)
                result.content = f"[LLM error] {e}"
                break

            result.prompt_tokens += resp.prompt_tokens
            result.completion_tokens += resp.completion_tokens

            # No tool calls — we're done
            if not resp.tool_calls:
                result.content = resp.content or ""
                break

            # Append assistant message with tool calls
            assistant_msg: Dict[str, Any] = {"role": "assistant", "content": resp.content or ""}
            assistant_msg["tool_calls"] = [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {"name": tc.name, "arguments": json.dumps(tc.arguments)},
                }
                for tc in resp.tool_calls
            ]
            messages.append(assistant_msg)

            # Execute each tool call
            for tc in resp.tool_calls:
                tool = self._find_tool(tc.name)
                if tool:
                    try:
                        tool_result = await tool.execute(**tc.arguments)
                        result.tools_used.append(tc.name)
                        if (
                            tc.name == "request_skill_install"
                            and isinstance(tool_result, str)
                            and "install" in tool_result.lower()
                            and "continue without" in tool_result.lower()
                        ):
                            result.content = tool_result
                            return result
                    except Exception as e:
                        tool_result = f"Tool error: {e}\n{traceback.format_exc()}"
                else:
                    tool_result = f"Unknown tool: {tc.name}"

                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": str(tool_result)[:50_000],
                })

        return result
