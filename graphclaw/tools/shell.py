"""Shell command execution tool."""
from __future__ import annotations
import asyncio
import os
import signal
import subprocess
from typing import Any


class ShellTool:
    name = "shell"
    description = "Execute a shell command and return its output. Use for git, npm, pip, tests, etc."
    parameters = {
        "type": "object",
        "properties": {
            "command": {"type": "string", "description": "Shell command to execute"},
            "timeout": {"type": "integer", "description": "Timeout in seconds", "default": 120},
        },
        "required": ["command"],
    }

    def __init__(self, workspace: str = ""):
        self.workspace = workspace

    async def execute(self, **kwargs: Any) -> str:
        command = kwargs["command"]
        timeout = kwargs.get("timeout", 120)

        proc = None
        try:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=self.workspace or None,
                # Own process group, so a timeout can kill the command's children too
                start_new_session=os.name != "nt",
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
            out = stdout.decode("utf-8", errors="replace") if stdout else ""
            err = stderr.decode("utf-8", errors="replace") if stderr else ""

            result = ""
            if out:
                result += out
            if err:
                result += f"\n[stderr]\n{err}" if result else err

            # Truncate very long output
            max_chars = 50_000
            if len(result) > max_chars:
                half = max_chars // 2
                result = result[:half] + f"\n\n... ({len(result) - max_chars} chars truncated) ...\n\n" + result[-half:]

            if proc.returncode != 0:
                result += f"\n[exit code: {proc.returncode}]"

            return result or "(no output)"
        except asyncio.TimeoutError:
            # Kill the timed-out process so it doesn't keep running orphaned
            if proc is not None and proc.returncode is None:
                try:
                    if os.name != "nt":
                        os.killpg(proc.pid, signal.SIGKILL)
                    else:
                        proc.kill()
                except ProcessLookupError:
                    pass
                await proc.wait()
            return f"Error: command timed out after {timeout}s"
        except Exception as e:
            return f"Error executing command: {e}"
