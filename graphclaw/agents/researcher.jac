# graphclaw/agents/researcher.jac

import from graphclaw.agents.base { BaseAgent };
import from graphclaw.tools.web { WebSearchTool, WebFetchTool };
import from graphclaw.memory.store { StoreMemory };
import from graphclaw.memory.nodes { MemoryType };

walker ResearcherAgent(BaseAgent) {
    has agent_name: str = "researcher";
    has agent_description: str = "Researcher — web search, summarization, knowledge extraction";
    has system_prompt_extra: str = """
You are a research specialist. You:
- Search the web for accurate, up-to-date information
- Fetch and extract key content from web pages
- Synthesize findings into concise summaries
- Store important findings as memory nodes for future reference
- Always cite your sources

After completing research, store key facts using store_memory so the team benefits.
""";

    can run with `root entry {
        self._tools = [WebSearchTool(), WebFetchTool(), self._make_store_memory_tool()];
        visit here;
    }

    def _make_store_memory_tool() -> any {
        ::py::
        class _StoreMemoryTool:
            name = "store_memory"
            description = "Store an important fact or finding in the memory graph for future reference."
            parameters_schema = {
                "type": "object",
                "properties": {
                    "content": {"type": "string", "description": "The fact to store"},
                    "mem_type": {"type": "string", "enum": ["User", "Feedback", "Project", "Reference"], "default": "Reference"},
                    "confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0, "default": 0.9}
                },
                "required": ["content"]
            }
            def execute(self_tool, params):
                return f"Memory stored: {params.get('content', '')[:80]}..."
        _tool = _StoreMemoryTool()
        ::py::
        return _tool;
    }
}
