# graphclaw/agents/coordinator.jac
# Coordinator -- routes incoming messages to the right specialist agent
# Uses Jac's `by llm()` for intent classification, calls Python agents

import from graphclaw.config.loader { load_config }

# -- Intent classification via LLM ------------------------------------------------

obj IntentClassification {
    has agent: str;         # devops | planner | builder | researcher | coordinator
    has confidence: float;
    has reason: str;
}

def classify_intent(
    message: str,
    available_agents: list[str]
) -> IntentClassification by llm();

# -- Coordinator walker ------------------------------------------------------------

walker CoordinatorAgent {
    has query: str = "";
    has channel: str = "cli";
    has chat_id: str = "local";
    has user_id: str = "user";
    has model: str = "";

    can route with `root() entry {
        cfg = load_config();
        agents = ["devops", "planner", "builder", "researcher"];
        intent = classify_intent(self.query, agents);

        ::py::
        import asyncio

        agent_name = intent.agent
        confidence = intent.confidence

        # Import Python agent classes
        from graphclaw.agents.base import BaseAgent, AgentResult
        from graphclaw.agents.devops import DevOpsAgent
        from graphclaw.agents.planner import PlannerAgent
        from graphclaw.agents.builder import BuilderAgent
        from graphclaw.agents.researcher import ResearcherAgent

        agent_map = {
            "devops": DevOpsAgent,
            "planner": PlannerAgent,
            "builder": BuilderAgent,
            "researcher": ResearcherAgent,
        }

        kwargs = {
            "query": self.query,
            "channel": self.channel,
            "chat_id": self.chat_id,
            "user_id": self.user_id,
        }
        if self.model:
            kwargs["model"] = self.model

        if agent_name == "coordinator" or confidence < 0.6:
            # Handle directly as a general assistant
            agent = BaseAgent(**kwargs)
            agent.system_prompt = (
                "You are Graphclaw, a helpful multi-agent AI assistant. "
                "Answer the user's question directly and clearly. "
                "You have access to web search and file tools if needed."
            )
            from graphclaw.tools.web import WebSearchTool, WebFetchTool
            agent.tools = [WebSearchTool(), WebFetchTool()]
        else:
            AgentClass = agent_map.get(agent_name, BaseAgent)
            agent = AgentClass(**kwargs)

        # Run the Python agent
        loop = asyncio.get_event_loop()
        if loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as pool:
                _result = loop.run_in_executor(pool, lambda: asyncio.run(agent.run()))
                _result = asyncio.ensure_future(_result)
                # For sync context, we need a different approach
                _result = None
                try:
                    _result = asyncio.get_event_loop().run_until_complete(agent.run())
                except RuntimeError:
                    # Already running -- use create_task
                    import threading
                    result_holder = [None]
                    def _run():
                        result_holder[0] = asyncio.run(agent.run())
                    t = threading.Thread(target=_run)
                    t.start()
                    t.join(timeout=300)
                    _result = result_holder[0]
        else:
            _result = loop.run_until_complete(agent.run())
        ::py::

        if _result {
            report _result;
        } else {
            report {"content": "[No response from agent]", "error": "agent returned None"};
        }
    }
}
