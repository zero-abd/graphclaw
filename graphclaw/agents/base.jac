# graphclaw/agents/base.jac
# Base agent walker -- all agents inherit from this

import from graphclaw.providers.registry { get_provider }
import from graphclaw.providers.base { GenerationSettings, LLMResponse, ToolCallRequest }
import from graphclaw.memory.recall { Recall, GetMemoryContext }
import from graphclaw.memory.store { AppendTurn, StartSession }
import from graphclaw.config.loader { load_config }
import from datetime { datetime, timezone }
import from typing { Any }

# -- Agent result ---------------------------------------------------------------

obj AgentResult {
    has content: str;
    has tools_used: list[str] = [];
    has session_id: str = "";
    has input_tokens: int = 0;
    has output_tokens: int = 0;
    has iterations: int = 0;
}

# -- Tool definition for agent tool-use ----------------------------------------

obj AgentTool {
    has name: str;
    has description: str;
    has parameters_schema: dict;

    def execute(params: dict) -> str abs;
}

# -- Base agent walker ---------------------------------------------------------

walker BaseAgent {
    has query: str;
    has channel: str = "cli";
    has chat_id: str = "";
    has user_id: str = "";
    has session_id: str = "";
    has model: str = "";
    has stream: bool = False;
    has on_token: Any = None;   # callback for streaming tokens

    # Set by subclasses
    has agent_name: str = "base";
    has agent_description: str = "Base agent";
    has system_prompt_extra: str = "";

    # Internal
    has _tools: list[AgentTool] = [];
    has _messages: list[dict] = [];
    has _input_tokens: int = 0;
    has _output_tokens: int = 0;
    has _tools_used: list[str] = [];
    has _iterations: int = 0;

    can run with `root() entry {
        cfg = load_config();
        model = self.model or cfg.agents.model;
        provider = get_provider(model);

        # Start or reuse session
        if not self.session_id {
            sid = StartSession(
                channel=self.channel,
                chat_id=self.chat_id,
                user_id=self.user_id,
                agent=self.agent_name,
                model=model
            ) spawn here;
            self.session_id = sid;
        }

        # Build system prompt
        mem_context = GetMemoryContext(max_chars=3000) spawn here;
        system_prompt = self._build_system_prompt(mem_context);

        # Build messages
        self._messages = [{"role": "system", "content": system_prompt}];
        self._messages.append({"role": "user", "content": self.query});

        # Register user turn
        AppendTurn(
            session_id=self.session_id,
            role="user",
            content=self.query
        ) spawn here;

        # Agent loop
        settings = GenerationSettings(
            model=model,
            temperature=cfg.agents.temperature,
            max_tokens=cfg.agents.max_tokens,
            tools=provider.build_tool_definitions(self._tools),
            stream=self.stream,
            reasoning_effort=cfg.agents.reasoning_effort
        );

        result = self._run_loop(provider, settings, cfg);

        # Record assistant turn
        AppendTurn(
            session_id=self.session_id,
            role="assistant",
            content=result.content
        ) spawn here;

        report result;
    }

    def _build_system_prompt(mem_context: str) -> str {
        from datetime import datetime, timezone;
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC");
        lines = [
            f"You are {self.agent_name}, a {self.agent_description}.",
            f"Current time: {now}",
            "",
        ];
        if self.system_prompt_extra { lines.append(self.system_prompt_extra); lines.append(""); }
        if mem_context {
            lines.append("## Memory");
            lines.append(mem_context);
            lines.append("");
        }
        return "\n".join(lines);
    }

    def _run_loop(provider, settings, cfg) -> AgentResult {
        max_iter = cfg.agents.max_tool_iterations;
        while self._iterations < max_iter {
            self._iterations += 1;
            resp = provider.chat_completion(self._messages, settings);
            self._input_tokens += resp.input_tokens;
            self._output_tokens += resp.output_tokens;

            if resp.finish_reason == "tool_calls" or resp.tool_calls {
                self._messages.append({
                    "role": "assistant",
                    "content": resp.content,
                    "tool_calls": [
                        {"id": tc.id, "type": "function",
                         "function": {"name": tc.name, "arguments": str(tc.arguments)}}
                        for tc in resp.tool_calls
                    ]
                });

                for tc in resp.tool_calls {
                    tool_result = self._execute_tool(tc, cfg);
                    self._tools_used.append(tc.name);
                    self._messages.append({
                        "role": "tool",
                        "tool_call_id": tc.id,
                        "name": tc.name,
                        "content": str(tool_result)[:cfg.agents.max_tool_result_chars]
                    });
                }
            } else {
                return AgentResult(
                    content=resp.content,
                    tools_used=self._tools_used,
                    session_id=self.session_id,
                    input_tokens=self._input_tokens,
                    output_tokens=self._output_tokens,
                    iterations=self._iterations
                );
            }
        }
        return AgentResult(
            content="[Max iterations reached]",
            tools_used=self._tools_used,
            session_id=self.session_id,
            iterations=self._iterations
        );
    }

    def _execute_tool(tc: ToolCallRequest, cfg) -> str {
        for tool in self._tools {
            if tool.name == tc.name {
                ::py::
                import traceback
                try:
                    _tool_result = tool.execute(tc.arguments)
                except Exception as e:
                    _tool_result = f"[Tool error: {traceback.format_exc(limit=3)}]"
                ::py::
                return _tool_result;
            }
        }
        return f"[Unknown tool: {tc.name}]";
    }
}
