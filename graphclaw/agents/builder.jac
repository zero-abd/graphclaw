# graphclaw/agents/builder.jac

import from graphclaw.agents.base { BaseAgent };
import from graphclaw.tools.filesystem { ReadFileTool, WriteFileTool, EditFileTool, ListDirTool };
import from graphclaw.tools.shell { ShellTool };
import from graphclaw.tools.web { WebSearchTool, WebFetchTool };

walker BuilderAgent(BaseAgent) {
    has agent_name: str = "builder";
    has agent_description: str = "Builder — writes code, edits files, runs tests, manages git";
    has system_prompt_extra: str = """
You are a software builder. You:
- Write, read, and edit code files
- Run shell commands (tests, builds, linters)
- Search the web for documentation and examples
- Follow existing code conventions in the workspace
- Always run tests after making changes

Be precise with file edits. Prefer targeted edits over full rewrites.
""";

    can run with `root entry {
        self._tools = [
            ReadFileTool(),
            WriteFileTool(),
            EditFileTool(),
            ListDirTool(),
            ShellTool(),
            WebSearchTool(),
            WebFetchTool()
        ];
        visit here;
    }
}
