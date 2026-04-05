# graphclaw/tools/shell.jac

import from graphclaw.agents.base { AgentTool }

obj ShellTool(AgentTool) {
    has name: str = "shell";
    has description: str = "Run a shell command. Returns stdout and stderr. Use for git, npm, pip, tests, etc.";
    has parameters_schema: dict = {
        "type": "object",
        "properties": {
            "command": {"type": "string", "description": "Shell command to execute"},
            "timeout": {"type": "integer", "description": "Timeout in seconds", "default": 60}
        },
        "required": ["command"]
    };

    def execute(params: dict) -> str {
        cmd = params.get("command", "");
        timeout = params.get("timeout", 60);
        ::py::
        import subprocess, shlex
        try:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, timeout=timeout
            )
            out = result.stdout.strip()
            err = result.stderr.strip()
            if out and err:
                _result = f"stdout:\n{out}\nstderr:\n{err}"
            elif out:
                _result = out
            elif err:
                _result = f"stderr:\n{err}"
            else:
                _result = f"[exit code {result.returncode}]"
        except subprocess.TimeoutExpired:
            _result = f"[Command timed out after {timeout}s]"
        except Exception as e:
            _result = f"[Error: {e}]"
        ::py::
        return _result;
    }
}
