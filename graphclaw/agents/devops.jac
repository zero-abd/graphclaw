# graphclaw/agents/devops.jac
# DevOps agent — taps into a skill directory dynamically
# Has built-in tools + loads skills from the registry on demand

import from graphclaw.agents.base { BaseAgent, AgentTool, AgentResult };
import from graphclaw.skills.loader { LoadSkills, ListSkills, GetSkill, InvokeSkillTool, InstallSkill };
import from graphclaw.tools.shell { ShellTool };
import from graphclaw.tools.filesystem { ReadFileTool, WriteFileTool, ListDirTool };
import from graphclaw.tools.web { WebSearchTool, WebFetchTool };

# ── Skill-backed tool (wraps any installed skill tool as an AgentTool) ─────────

obj SkillBackedTool(AgentTool) {
    has skill_name: str;
    has tool_description: str;

    def execute(params: dict) -> str {
        ::py::
        import asyncio
        # We need access to root for the InvokeSkillTool walker
        # This is handled via the devops agent's _invoke_skill helper
        _skill_result = f"[SkillBackedTool: call _invoke_skill({self.skill_name}, {self.name}, params)]"
        ::py::
        return _skill_result;
    }
}

# ── DevOps agent ───────────────────────────────────────────────────────────────

walker DevOpsAgent(BaseAgent) {
    has agent_name: str = "devops";
    has agent_description: str = "DevOps engineer agent — CI/CD, infrastructure, deployments, app platforms";
    has system_prompt_extra: str = """
You are an expert DevOps engineer. You can:
- Deploy and manage apps on Base44 and Loveable
- Run shell commands for infrastructure tasks
- Search the web for documentation and solutions
- Read and write files in the workspace
- Install new skills from the online registry when you need capabilities you don't have yet

When given a task:
1. Identify what skills/tools you need
2. If a needed skill isn't loaded, install it with install_skill
3. Execute the task step by step, reporting progress
4. Store important findings in memory for future reference
""";

    has _skill_names: list[str] = [];

    can run with `root entry {
        # Load all skills first
        LoadSkills() spawn here;

        # Build tool list: built-ins + all enabled skill tools
        self._tools = self._build_tools(here);

        # Hand off to base agent loop
        ::jac::
        visit here;
        ::jac::
    }

    def _build_tools(graph_root) -> list[AgentTool] {
        tools = [];

        # ── Built-in tools ──────────────────────────────────────────────────
        tools.append(ShellTool());
        tools.append(ReadFileTool());
        tools.append(WriteFileTool());
        tools.append(ListDirTool());
        tools.append(WebSearchTool());
        tools.append(WebFetchTool());
        tools.append(self._make_install_skill_tool());
        tools.append(self._make_list_skills_tool());

        # ── Skill-backed tools (from all enabled skills) ────────────────────
        ::py::
        import asyncio
        # Run ListSkills walker to get available skills
        # In real usage this is called via spawn, here we do it inline
        skills_result = []
        _skill_tools_added = []
        ::py::

        skill_list = ListSkills(enabled_only=True) spawn graph_root;
        for sk in (skill_list or []) {
            for tool_name in sk.get("tools", []) {
                desc = f"[{sk['name']} skill] {tool_name.replace('_', ' ').title()}";
                tools.append(AgentTool(
                    name=f"{sk['name']}__{tool_name}",
                    description=desc,
                    parameters_schema={"type": "object", "properties": {}, "additionalProperties": True}
                ));
                self._skill_names.append(sk['name']);
            }
        }

        return tools;
    }

    def _make_install_skill_tool() -> AgentTool {
        ::py::
        class _InstallSkillTool:
            name = "install_skill"
            description = "Install a new skill from the online registry by name or GitHub URL. Use this when you need a capability that isn't available yet."
            parameters_schema = {
                "type": "object",
                "properties": {
                    "source": {"type": "string", "description": "Skill name (e.g. 'kubernetes') or GitHub URL"}
                },
                "required": ["source"]
            }
            def execute(self, params):
                source = params.get("source", "")
                # This calls back into the graph — handled via the walker infrastructure
                return f"Installing skill: {source}. Run: InstallSkill(source='{source}') spawn root"
        _install_tool = _InstallSkillTool()
        ::py::
        return _install_tool;
    }

    def _make_list_skills_tool() -> AgentTool {
        ::py::
        class _ListSkillsTool:
            name = "list_available_skills"
            description = "List all currently loaded skills and their tools."
            parameters_schema = {"type": "object", "properties": {}}
            def execute(self, params):
                return "Use ListSkills walker to get current skills"
        _list_tool = _ListSkillsTool()
        ::py::
        return _list_tool;
    }

    def _execute_tool(tc, cfg) -> str {
        # Intercept skill-backed tool calls (name format: "skillname__toolname")
        if "__" in tc.name {
            parts = tc.name.split("__", 1);
            skill_name = parts[0];
            tool_name = parts[1];
            ::py::
            import json
            _tc_result = f"Invoking {skill_name}.{tool_name} with {tc.arguments}"
            # Real invocation happens via InvokeSkillTool walker
            ::py::
            return _tc_result;
        }

        # Otherwise delegate to base class
        return super._execute_tool(tc, cfg);
    }
}
