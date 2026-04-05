# graphclaw/agents/planner.jac

import from graphclaw.agents.base { BaseAgent, AgentTool };
import from graphclaw.tools.filesystem { ReadFileTool, WriteFileTool };
import from graphclaw.memory.nodes { Memory, MemoryType };

walker PlannerAgent(BaseAgent) {
    has agent_name: str = "planner";
    has agent_description: str = "Planner — breaks goals into tasks, tracks progress, manages priorities";
    has system_prompt_extra: str = """
You are a planning specialist. You:
- Decompose complex goals into actionable tasks
- Track task dependencies and blockers
- Prioritize work based on impact and urgency
- Create and maintain project plans
- Store plans and progress in the memory graph for continuity

When creating a plan, be specific about deliverables, dependencies, and success criteria.
""";

    can run with `root entry {
        self._tools = [ReadFileTool(), WriteFileTool()];
        visit here;
    }
}
