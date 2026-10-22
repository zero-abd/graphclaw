import asyncio
import importlib
import os
import sys
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from graphclaw.tools import shell as _shell_mod

shell_mod = importlib.reload(_shell_mod)


def test_shell_tool_returns_output_and_exit_code(tmp_path):
    tool = shell_mod.ShellTool(workspace=str(tmp_path))

    result = asyncio.run(tool.execute(command="echo hello; exit 3"))

    assert "hello" in result
    assert "[exit code: 3]" in result


@pytest.mark.skipif(os.name == "nt", reason="uses POSIX shell syntax")
def test_shell_tool_kills_command_and_children_on_timeout(tmp_path):
    tool = shell_mod.ShellTool(workspace=str(tmp_path))
    # Both the shell itself and a backgrounded child would write a marker
    # once the timeout has passed, unless the timeout actually kills them.
    command = "(sleep 2; touch child_marker) & sleep 2; touch shell_marker"

    start = time.monotonic()
    result = asyncio.run(tool.execute(command=command, timeout=1))
    elapsed = time.monotonic() - start

    assert result == "Error: command timed out after 1s"
    assert elapsed < 2
    time.sleep(2.5)
    assert not (tmp_path / "shell_marker").exists()
    assert not (tmp_path / "child_marker").exists()
