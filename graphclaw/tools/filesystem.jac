# graphclaw/tools/filesystem.jac

import from graphclaw.agents.base { AgentTool };

obj ReadFileTool(AgentTool) {
    has name: str = "read_file";
    has description: str = "Read the contents of a file.";
    has parameters_schema: dict = {
        "type": "object",
        "properties": {
            "path": {"type": "string"},
            "start_line": {"type": "integer", "default": 1},
            "end_line": {"type": "integer", "default": 0}
        },
        "required": ["path"]
    };
    def execute(params: dict) -> str {
        ::py::
        from pathlib import Path
        try:
            p = Path(params["path"]).expanduser()
            lines = p.read_text(encoding="utf-8").splitlines()
            start = max(0, params.get("start_line", 1) - 1)
            end = params.get("end_line", 0)
            if end: lines = lines[start:end]
            else: lines = lines[start:]
            _result = "\n".join(f"{start+i+1}\t{l}" for i, l in enumerate(lines))
        except Exception as e:
            _result = f"[Error: {e}]"
        ::py::
        return _result;
    }
}

obj WriteFileTool(AgentTool) {
    has name: str = "write_file";
    has description: str = "Write content to a file (overwrites).";
    has parameters_schema: dict = {
        "type": "object",
        "properties": {
            "path": {"type": "string"},
            "content": {"type": "string"}
        },
        "required": ["path", "content"]
    };
    def execute(params: dict) -> str {
        ::py::
        from pathlib import Path
        try:
            p = Path(params["path"]).expanduser()
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(params["content"], encoding="utf-8")
            _result = f"Written {len(params['content'])} chars to {p}"
        except Exception as e:
            _result = f"[Error: {e}]"
        ::py::
        return _result;
    }
}

obj EditFileTool(AgentTool) {
    has name: str = "edit_file";
    has description: str = "Replace a specific string in a file with a new string.";
    has parameters_schema: dict = {
        "type": "object",
        "properties": {
            "path": {"type": "string"},
            "old_string": {"type": "string"},
            "new_string": {"type": "string"}
        },
        "required": ["path", "old_string", "new_string"]
    };
    def execute(params: dict) -> str {
        ::py::
        from pathlib import Path
        try:
            p = Path(params["path"]).expanduser()
            content = p.read_text(encoding="utf-8")
            if params["old_string"] not in content:
                _result = "[old_string not found in file]"
            else:
                new_content = content.replace(params["old_string"], params["new_string"], 1)
                p.write_text(new_content, encoding="utf-8")
                _result = f"Edit applied to {p}"
        except Exception as e:
            _result = f"[Error: {e}]"
        ::py::
        return _result;
    }
}

obj ListDirTool(AgentTool) {
    has name: str = "list_dir";
    has description: str = "List files and directories at a path.";
    has parameters_schema: dict = {
        "type": "object",
        "properties": {"path": {"type": "string", "default": "."}},
        "required": []
    };
    def execute(params: dict) -> str {
        ::py::
        from pathlib import Path
        try:
            p = Path(params.get("path", ".")).expanduser()
            entries = sorted(p.iterdir(), key=lambda x: (x.is_file(), x.name))
            _result = "\n".join(
                f"{'d' if e.is_dir() else 'f'} {e.name}" for e in entries
            )
        except Exception as e:
            _result = f"[Error: {e}]"
        ::py::
        return _result;
    }
}
