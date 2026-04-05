"""Official Base44 integration built around the Base44 CLI workflow."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path


def _base44_command() -> list[str]:
    if shutil.which("base44"):
        return ["base44"]
    if shutil.which("npx"):
        return ["npx", "--yes", "base44@latest"]
    raise RuntimeError(
        "Base44 CLI is not available. Install Node.js/npm first, then run `npm install -g base44` "
        "or let Graphclaw use `npx --yes base44@latest`."
    )


def _run_base44(args: list[str], *, cwd: str | None = None, timeout: float = 300.0) -> dict:
    command = _base44_command() + args
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    combined = "\n".join(part for part in [result.stdout.strip(), result.stderr.strip()] if part).strip()
    urls = re.findall(r"https?://[^\s)>\"]+", combined)
    return {
        "ok": result.returncode == 0,
        "command": command,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "output": combined,
        "urls": urls,
    }


def ensure_cli() -> dict:
    """Check whether the Base44 CLI is available or can be invoked with npx."""
    try:
        command = _base44_command()
        result = _run_base44(["--help"], timeout=30.0)
        return {
            "ok": result["ok"],
            "command": command,
            "message": "Base44 CLI is available." if result["ok"] else result["output"],
        }
    except Exception as exc:
        return {"ok": False, "message": str(exc)}


def login_guide() -> dict:
    """Return the official login/setup guidance for Base44 CLI."""
    return {
        "steps": [
            "Run `base44 login` (or let Graphclaw use `npx --yes base44@latest login`) and complete authentication.",
            "Use `base44 create` to scaffold a project; Base44 includes project skills automatically in CLI-created apps.",
            "Use `base44 deploy` to push the current project to production, including Base44-hosted site deployment.",
        ],
        "notes": [
            "The CLI skill is Base44's official first stop for project setup, deployment, auth, and project management.",
            "If the CLI is not installed globally, Graphclaw can use `npx --yes base44@latest` when Node/npm is available.",
        ],
    }


def create_project(
    name: str,
    path: str = "",
    template: str = "basic",
    deploy: bool = False,
) -> dict:
    """Create a new Base44 project through the official CLI."""
    target = Path(path).expanduser().resolve() if path else (Path.cwd() / name).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    args = ["create", "--name", name, "--path", str(target), "--template", template]
    if deploy:
        args.append("--deploy")
    result = _run_base44(args, cwd=str(target.parent), timeout=900.0)
    result["project_path"] = str(target)
    return result


def deploy_project(project_path: str) -> dict:
    """Deploy an existing Base44 project to production via the CLI."""
    target = Path(project_path).expanduser().resolve()
    return _run_base44(["deploy"], cwd=str(target), timeout=900.0)


def create_landing_page_project(name: str, path: str = "", deploy: bool = True) -> dict:
    """Convenience helper for a simple Base44 landing-page starter."""
    return create_project(name=name, path=path, template="basic", deploy=deploy)


def parse_project_metadata(project_path: str) -> dict:
    """Read Base44's local app metadata file when present."""
    target = Path(project_path).expanduser().resolve() / "base44" / ".app.jsonc"
    if not target.exists():
        return {"ok": False, "message": f"No Base44 metadata found at {target}"}
    text = target.read_text(encoding="utf-8")
    cleaned = re.sub(r"//.*", "", text)
    try:
        return {"ok": True, "metadata": json.loads(cleaned)}
    except Exception as exc:
        return {"ok": False, "message": f"Failed to parse {target}: {exc}"}
