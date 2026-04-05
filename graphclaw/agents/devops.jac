# graphclaw/agents/devops.jac
# DevOps agent -- taps into a skill directory dynamically
# Supports two skill types:
#   "native"  -- skill.json + skill.py (base44, loveable) -- tools are Python functions
#   "clawhub" -- SKILL.md from clawhub.ai -- tools return instructions the agent follows

import from graphclaw.agents.base { BaseAgent, AgentTool, AgentResult }
import from graphclaw.skills.loader {
    LoadSkills, ListSkills, GetSkill, InvokeSkillTool,
    InstallSkill, SearchClawHub
};
import from graphclaw.tools.shell { ShellTool }
import from graphclaw.tools.filesystem { ReadFileTool, WriteFileTool, ListDirTool }
import from graphclaw.tools.web { WebSearchTool, WebFetchTool }

# -- DevOps agent ---------------------------------------------------------------

walker DevOpsAgent(BaseAgent) {
    has agent_name: str = "devops";
    has agent_description: str = "DevOps engineer agent -- CI/CD, infrastructure, deployments, app platforms";
    has system_prompt_extra: str = """
You are an expert DevOps engineer. You can:
- Deploy and manage apps on Base44 and Loveable (built-in skills)
- Run shell commands for infrastructure tasks
- Search the web for documentation and solutions
- Read and write files in the workspace
- Search ClawHub for new skills and install them on demand

**Available skill types:**
- Native skills (base44, loveable): call `<skillname>__<toolname>` with specific parameters
- ClawHub skills: call `clawhub__<skillname>` with `{"task": "what to accomplish"}` -- you get
  back the skill's instructions, then use your shell/web tools to follow them

When given a task:
1. Check if you have the right skill already (use list_available_skills)
2. If not, search ClawHub (use search_clawhub) and install what you need (use install_skill)
3. Execute step by step, using shell/web/file tools to complete the work
4. Report progress and store important findings in memory
""";

    can run with `root() entry {
        LoadSkills() spawn here;
        self._tools = self._build_tools(here);
        ::jac::
        visit here;
        ::jac::
    }

    def _build_tools(graph_root) -> list[AgentTool] {
        tools = [];

        # -- Built-in tools --------------------------------------------------
        tools.append(ShellTool());
        tools.append(ReadFileTool());
        tools.append(WriteFileTool());
        tools.append(ListDirTool());
        tools.append(WebSearchTool());
        tools.append(WebFetchTool());

        # -- Registry tools -------------------------------------------------
        tools.append(self._make_search_clawhub_tool(graph_root));
        tools.append(self._make_install_skill_tool(graph_root));
        tools.append(self._make_list_skills_tool(graph_root));

        # -- Skill-backed tools (from all enabled skills) --------------------
        skill_list = ListSkills(enabled_only=True) spawn graph_root;
        for sk in (skill_list or []) {
            if sk.get("skill_type", "native") == "clawhub" {
                # ClawHub skill → single tool that returns SKILL.md instructions
                ::py::
                _sk = sk
                _graph_root = graph_root
                class _ClawHubTool:
                    def __init__(self, skill_meta, root):
                        self.name = f"clawhub__{skill_meta['name']}"
                        self.description = (
                            f"[ClawHub] {skill_meta.get('description', '')} "
                            f"-- pass task='what you want to do'"
                        )
                        self.parameters_schema = {
                            "type": "object",
                            "properties": {
                                "task": {
                                    "type": "string",
                                    "description": "Describe what you want to accomplish with this skill"
                                }
                            },
                            "required": ["task"]
                        }
                        self._skill_name = skill_meta["name"]
                        self._root = root
                    def execute(self, params):
                        from graphclaw.skills.loader import InvokeSkillTool
                        result = InvokeSkillTool(
                            skill_name=self._skill_name,
                            tool_name="",
                            params=params
                        ).spawn(self._root)
                        return str(result) if result is not None else "[no instructions returned]"
                _clawhub_tool = _ClawHubTool(_sk, _graph_root)
                ::py::
                tools.append(_clawhub_tool);
            } else {
                # Native skill → one tool per Python function
                for tool_name in sk.get("tools", []) {
                    ::py::
                    _sk = sk
                    _tn = tool_name
                    _graph_root = graph_root
                    class _NativeTool:
                        def __init__(self, skill_meta, tname, root):
                            self.name = f"{skill_meta['name']}__{tname}"
                            self.description = (
                                f"[{skill_meta['name']}] "
                                f"{tname.replace('_', ' ').title()}"
                            )
                            self.parameters_schema = {
                                "type": "object",
                                "properties": {},
                                "additionalProperties": True
                            }
                            self._skill_name = skill_meta["name"]
                            self._tool_name = tname
                            self._root = root
                        def execute(self, params):
                            from graphclaw.skills.loader import InvokeSkillTool
                            result = InvokeSkillTool(
                                skill_name=self._skill_name,
                                tool_name=self._tool_name,
                                params=params
                            ).spawn(self._root)
                            if isinstance(result, dict):
                                import json
                                return json.dumps(result, indent=2, default=str)
                            return str(result) if result is not None else "Done"
                    _native_tool = _NativeTool(_sk, _tn, _graph_root)
                    ::py::
                    tools.append(_native_tool);
                }
            }
        }

        return tools;
    }

    def _make_search_clawhub_tool(graph_root) -> AgentTool {
        ::py::
        _root = graph_root
        class _SearchClawHubTool:
            name = "search_clawhub"
            description = "Search the ClawHub skills registry for skills matching your query."
            parameters_schema = {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "What kind of skill to search for (e.g. 'kubernetes', 'docker', 'github actions')"
                    }
                },
                "required": ["query"]
            }
            def __init__(self, root):
                self._root = root
            def execute(self, params):
                from graphclaw.skills.loader import SearchClawHub
                import json
                query = params.get("query", "")
                results = SearchClawHub(query=query).spawn(self._root)
                if isinstance(results, dict) and "error" in results:
                    return f"ClawHub search failed: {results['error']}"
                if not results:
                    return f"No skills found on ClawHub for '{query}'. Try a broader query."
                items = results if isinstance(results, list) else []
                lines = [f"**ClawHub skills matching '{query}':**\n"]
                for skill in items[:10]:
                    slug = skill.get("slug", skill.get("name", "?"))
                    desc = skill.get("description", "")[:120]
                    lines.append(f"- `{slug}` -- {desc}")
                lines.append(f"\nTo install: call install_skill with source='<slug>'")
                return "\n".join(lines)
        _tool = _SearchClawHubTool(_root)
        ::py::
        return _tool;
    }

    def _make_install_skill_tool(graph_root) -> AgentTool {
        ::py::
        _root = graph_root
        class _InstallSkillTool:
            name = "install_skill"
            description = (
                "Install a skill from ClawHub by slug (e.g. 'kubernetes') or from a direct GitHub ZIP URL. "
                "After installing, the skill tool becomes available immediately."
            )
            parameters_schema = {
                "type": "object",
                "properties": {
                    "source": {
                        "type": "string",
                        "description": "ClawHub skill slug (e.g. 'kubernetes') or a direct URL to a skill ZIP"
                    },
                    "force": {
                        "type": "boolean",
                        "description": "Re-install even if already installed (default: false)"
                    }
                },
                "required": ["source"]
            }
            def __init__(self, root):
                self._root = root
            def execute(self, params):
                from graphclaw.skills.loader import InstallSkill, LoadSkills
                source = params.get("source", "")
                force = params.get("force", False)
                result = InstallSkill(source=source, force=force).spawn(self._root)
                if not result:
                    return f"Install failed: no response"
                if result.get("success"):
                    skill = result.get("skill", {})
                    stype = "ClawHub" if skill.get("instructions") else "native"
                    return (
                        f"✓ Installed {stype} skill '{skill.get('name', source)}' "
                        f"v{skill.get('version', '?')}.\n"
                        f"{skill.get('description', '')}\n"
                        f"You can now use it via clawhub__{skill.get('name', source)}."
                    )
                return f"Failed to install '{source}': {result.get('error', 'unknown error')}"
        _tool = _InstallSkillTool(_root)
        ::py::
        return _tool;
    }

    def _make_list_skills_tool(graph_root) -> AgentTool {
        ::py::
        _root = graph_root
        class _ListSkillsTool:
            name = "list_available_skills"
            description = "List all currently installed skills and their tools."
            parameters_schema = {"type": "object", "properties": {}}
            def __init__(self, root):
                self._root = root
            def execute(self, params):
                from graphclaw.skills.loader import ListSkills
                skills = ListSkills(enabled_only=True).spawn(self._root) or []
                if not skills:
                    return "No skills installed. Use search_clawhub to find skills and install_skill to add them."
                lines = ["**Installed skills:**\n"]
                for sk in skills:
                    stype = sk.get("skill_type", "native")
                    if stype == "clawhub":
                        lines.append(
                            f"- **clawhub__{sk['name']}** v{sk.get('version','?')} "
                            f"[ClawHub] -- {sk.get('description','')}"
                        )
                    else:
                        tlist = ", ".join(sk.get("tools", []))
                        lines.append(
                            f"- **{sk['name']}** v{sk.get('version','?')} "
                            f"[native] -- {sk.get('description','')} | tools: {tlist}"
                        )
                return "\n".join(lines)
        _tool = _ListSkillsTool(_root)
        ::py::
        return _tool;
    }
}
