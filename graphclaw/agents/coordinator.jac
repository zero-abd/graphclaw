# graphclaw/agents/coordinator.jac
# Coordinator -- routes incoming messages to the right specialist agent.

obj IntentClassification {
    has agent: str = "coordinator";
    has confidence: float = 0.0;
    has reason: str = "";
}

def classify_intent(message: str, available_agents: list[str]) -> IntentClassification by llm();

walker CoordinatorAgent {
    has query: str = "";
    has channel: str = "cli";
    has chat_id: str = "local";
    has user_id: str = "user";
    has model: str = "";

    can route with Root entry {
        result_payload = None;
        agents = ["devops", "planner", "builder", "researcher"];
        intent = classify_intent(self.query, agents);

        ::py::
        import asyncio
        import threading

        from graphclaw.agents.base import BaseAgent
        from graphclaw.agents.builder import BuilderAgent
        from graphclaw.agents.devops import DevOpsAgent
        from graphclaw.agents.planner import PlannerAgent
        from graphclaw.agents.researcher import ResearcherAgent
        from graphclaw.tools.web import WebFetchTool, WebSearchTool

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

        if intent.agent == "coordinator" or intent.confidence < 0.6:
            agent = BaseAgent(**kwargs)
            agent.system_prompt = (
                "You are Graphclaw, a helpful multi-agent AI assistant. "
                "Answer directly and clearly. Use tools when helpful, and be honest about uncertainty."
            )
            agent.tools = [WebSearchTool(), WebFetchTool()]
        else:
            agent_cls = agent_map.get(intent.agent, BaseAgent)
            agent = agent_cls(**kwargs)

        result_holder = {"value": None, "error": None}

        def _run_agent() -> None:
            try:
                result_holder["value"] = asyncio.run(agent.run())
            except Exception as exc:
                result_holder["error"] = exc

        worker = threading.Thread(target=_run_agent, daemon=True)
        worker.start()
        worker.join(timeout=300)

        if worker.is_alive():
            result_payload = {"content": "[Agent error] agent timed out", "error": "agent timed out"}
        elif result_holder["error"] is not None:
            result_payload = {
                "content": f"[Agent error] {result_holder['error']}",
                "error": str(result_holder["error"]),
            }
        elif result_holder["value"] is None:
            result_payload = {"content": "[No response from agent]", "error": "agent returned None"}
        else:
            result_payload = result_holder["value"]
        ::py::

        report result_payload;
    }
}
