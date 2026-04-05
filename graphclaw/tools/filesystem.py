"""Filesystem tools for agents."""
from __future__ import annotations
import os
from pathlib import Path
from typing import Any, Dict, Optional


class ReadFileTool:
    name = "read_file"
    description = "Read the contents of a file. Supports offset/limit for large files."
    parameters = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Absolute or workspace-relative file path"},
            "offset": {"type": "integer", "description": "Line number to start from (0-based)", "default": 0},
            "limit": {"type": "integer", "description": "Max lines to read", "default": 2000},
        },
        "required": ["path"],
    }

    def __init__(self, workspace: str = ""):
        self.workspace = workspace

    async def execute(self, **kwargs: Any) -> str:
        path = kwargs["path"]
        offset = kwargs.get("offset", 0)
        limit = kwargs.get("limit", 2000)

        p = Path(path) if os.path.isabs(path) else Path(self.workspace) / path
        if not p.exists():
            return f"Error: file not found: {p}"
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
            chunk = lines[offset:offset + limit]
            numbered = [f"{i + offset + 1}\t{line}" for i, line in enumerate(chunk)]
            result = "\n".join(numbered)
            if len(lines) > offset + limit:
                result += f"\n... ({len(lines) - offset - limit} more lines)"
            return result
        except Exception as e:
            return f"Error reading file: {e}"


class WriteFileTool:
    name = "write_file"
    description = "Write content to a file, creating parent directories if needed."
    parameters = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "File path to write"},
            "content": {"type": "string", "description": "Content to write"},
        },
        "required": ["path", "content"],
    }

    def __init__(self, workspace: str = ""):
        self.workspace = workspace

    async def execute(self, **kwargs: Any) -> str:
        path = kwargs["path"]
        content = kwargs["content"]
        p = Path(path) if os.path.isabs(path) else Path(self.workspace) / path
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")
            return f"Wrote {len(content)} bytes to {p}"
        except Exception as e:
            return f"Error writing file: {e}"


class EditFileTool:
    name = "edit_file"
    description = "Replace a string in a file. old_string must match exactly."
    parameters = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "File path"},
            "old_string": {"type": "string", "description": "Exact string to find"},
            "new_string": {"type": "string", "description": "Replacement string"},
        },
        "required": ["path", "old_string", "new_string"],
    }

    def __init__(self, workspace: str = ""):
        self.workspace = workspace

    async def execute(self, **kwargs: Any) -> str:
        path = kwargs["path"]
        old = kwargs["old_string"]
        new = kwargs["new_string"]
        p = Path(path) if os.path.isabs(path) else Path(self.workspace) / path
        if not p.exists():
            return f"Error: file not found: {p}"
        try:
            text = p.read_text(encoding="utf-8")
            if old not in text:
                return f"Error: old_string not found in {p}"
            count = text.count(old)
            text = text.replace(old, new, 1)
            p.write_text(text, encoding="utf-8")
            return f"Replaced 1 of {count} occurrences in {p}"
        except Exception as e:
            return f"Error editing file: {e}"


class ListDirTool:
    name = "list_dir"
    description = "List files and directories at a given path."
    parameters = {
        "type": "object",
        "properties": {
            "path": {"type": "string", "description": "Directory path", "default": "."},
        },
    }

    def __init__(self, workspace: str = ""):
        self.workspace = workspace

    async def execute(self, **kwargs: Any) -> str:
        path = kwargs.get("path", ".")
        p = Path(path) if os.path.isabs(path) else Path(self.workspace) / path
        if not p.is_dir():
            return f"Error: not a directory: {p}"
        try:
            entries = sorted(p.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))
            lines = []
            for e in entries:
                if e.name.startswith("."):
                    continue
                suffix = "/" if e.is_dir() else ""
                lines.append(f"  {e.name}{suffix}")
            return "\n".join(lines) if lines else "(empty directory)"
        except Exception as e:
            return f"Error listing dir: {e}"
