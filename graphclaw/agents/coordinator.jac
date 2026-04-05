# graphclaw/agents/coordinator.jac
# Coordinator — routes incoming messages to the right agent

import from graphclaw.agents.base { BaseAgent, AgentTool, AgentResult };
import from graphclaw.config.loader { load_config };

sem classify_intent = "Given a user message, determine which agent should handle it. Return the agent name: devops, planner, builder, researcher, or coordinator (if it's a general question or none of the others fit).";

obj IntentClassification {
    has agent: str;         # devops | planner | builder | researcher | coordinator
    has confidence: float;
    has reason: str;
}

def classify_intent(message: str, available_agents: list[str]) -> IntentClassification by llm();

walker CoordinatorAgent(BaseAgent) {
    has agent_name: str = "coordinator";
    has agent_description: str = "Coordinator — routes tasks to the right specialist agent";
    has system_prompt_extra: str = """
You are the central coordinator for Graphclaw. You:
- Answer general questions directly
- Route specialized tasks to the right agent (devops, planner, builder, researcher)
- Synthesize results from multiple agents
- Maintain context across the conversation
""";

    has available_agents: list[str] = ["devops", "planner", "builder", "researcher"];

    can route with `root entry {
        # Classify intent
        intent = classify_intent(self.query, self.available_agents);

        if intent.agent == "coordinator" or intent.confidence < 0.6 {
            # Handle directly
            visit here;   # triggers base agent run
        } else {
            # Spawn the appropriate specialist
            result = self._spawn_agent(intent.agent, here);
            report result;
        }
    }

    def _spawn_agent(agent_name: str, graph_root) -> AgentResult {
        from graphclaw.agents.devops import DevOpsAgent;
        from graphclaw.agents.planner import PlannerAgent;
        from graphclaw.agents.builder import BuilderAgent;
        from graphclaw.agents.researcher import ResearcherAgent;

        agent_map = {
            "devops":     DevOpsAgent,
            "planner":    PlannerAgent,
            "builder":    BuilderAgent,
            "researcher": ResearcherAgent,
        };

        AgentClass = agent_map.get(agent_name);
        if not AgentClass {
            return AgentResult(content=f"[Unknown agent: {agent_name}]");
        }

        agent = AgentClass(
            query=self.query,
            channel=self.channel,
            chat_id=self.chat_id,
            user_id=self.user_id,
            session_id=self.session_id,
            model=self.model,
            stream=self.stream,
            on_token=self.on_token
        );
        return agent spawn graph_root;
    }
}
