"""Skill loader — discovers local skills and integrates with ClawHub API."""
from __future__ import annotations
import asyncio
import inspect
import json
import re
from pathlib import Path
from typing import Any, Dict, List
from graphclaw.config.loader import load_config


CLAWHUB_BASE = "https://clawhub.ai"


def _workspace_root() -> Path:
    cfg = load_config()
    return Path(cfg.workspace)


def _workspace_skills_dir() -> Path:
    return _workspace_root() / "skills"


def _shared_skills_dir() -> Path:
    return Path.home() / ".graphclaw" / "skills"


def _legacy_installed_dir() -> Path:
    cfg = load_config()
    p = cfg.skills.installed_path
    if p:
        return Path(p)
    return _workspace_root() / "skills" / "installed"


def _skills_dir() -> Path:
    return _workspace_skills_dir()


def _builtin_skills_dir() -> Path:
    return Path(__file__).parent / "registry"


def _clawhub_dir() -> Path:
    return _workspace_root() / ".clawhub"


def _lock_path() -> Path:
    return _clawhub_dir() / "lock.json"


def _skill_search_paths() -> list[Path]:
    return [_workspace_skills_dir(), _shared_skills_dir(), _legacy_installed_dir(), _builtin_skills_dir()]


def _skill_runtime_paths() -> list[Path]:
    return [_workspace_skills_dir(), _shared_skills_dir(), _legacy_installed_dir()]


def _read_lock() -> dict[str, Any]:
    path = _lock_path()
    if not path.exists():
        return {"skills": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {"skills": {}}
    if not isinstance(data, dict):
        return {"skills": {}}
    data.setdefault("skills", {})
    return data


def _write_lock(payload: dict[str, Any]) -> None:
    path = _lock_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _update_lock(slug: str, *, source: str, version: str = "latest", skill_type: str = "skill") -> None:
    payload = _read_lock()
    payload.setdefault("skills", {})[slug] = {
        "source": source,
        "version": version,
        "type": skill_type,
    }
    _write_lock(payload)


def list_skills() -> List[Dict[str, Any]]:
    """List all installed skills using OpenClaw-style search precedence."""
    skills = []
    seen = set()
    lock = _read_lock().get("skills", {})
    for base in _skill_runtime_paths() + [_builtin_skills_dir()]:
        if not base.is_dir():
            continue
        for entry in sorted(base.iterdir()):
            if not entry.is_dir() or entry.name.startswith('.'):
                continue
            if entry.name in seen:
                continue
            meta_file = entry / "skill.json"
            md_file = entry / "SKILL.md"
            if meta_file.exists():
                try:
                    meta = json.loads(meta_file.read_text(encoding="utf-8"))
                    seen.add(entry.name)
                    skills.append({
                        "name": meta.get("name", entry.name),
                        "slug": entry.name,
                        "type": "native",
                        "description": meta.get("description", ""),
                        "path": str(entry),
                        "source": lock.get(entry.name, {}).get("source", "bundled" if base == _builtin_skills_dir() else "local"),
                    })
                except Exception:
                    pass
            elif md_file.exists():
                front = _parse_frontmatter(md_file.read_text(encoding="utf-8"))
                seen.add(entry.name)
                skills.append({
                    "name": front.get("name", entry.name),
                    "slug": entry.name,
                    "type": "skill",
                    "description": front.get("description", ""),
                    "path": str(entry),
                    "source": lock.get(entry.name, {}).get("source", "local"),
                })
    return skills


def build_skills_summary(limit: int = 24) -> str:
    skills = list_skills()
    if not skills:
        return "No workspace/shared/bundled skills are currently installed."
    lines = []
    for skill in skills[:limit]:
        lines.append(
            f"- {skill.get('slug', 'skill')} [{skill.get('type', 'skill')}] from {skill.get('source', 'local')}: {skill.get('description', '')}"
        )
    if len(skills) > limit:
        lines.append(f"- ... and {len(skills) - limit} more")
    return "\n".join(lines)


def list_native_skill_functions(slug: str) -> List[str]:
    """Return callable public functions exposed by a native skill."""
    for base in _skill_runtime_paths() + [_builtin_skills_dir()]:
        skill_dir = base / slug
        meta_file = skill_dir / "skill.json"
        py_file = skill_dir / "skill.py"
        if not (meta_file.exists() and py_file.exists()):
            continue
        try:
            import importlib.util
            spec = importlib.util.spec_from_file_location(f"skill_{slug}", str(py_file))
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            return [f for f in dir(mod) if not f.startswith("_") and callable(getattr(mod, f))]
        except Exception:
            return []
    return []


def _parse_frontmatter(text: str) -> Dict[str, str]:
    """Parse YAML frontmatter from SKILL.md."""
    m = re.match(r'^---\s*\n(.*?)\n---', text, re.DOTALL)
    if not m:
        return {}
    result = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            result[k.strip()] = v.strip().strip('"').strip("'")
    return result


async def search_clawhub(query: str) -> List[Dict[str, Any]]:
    """Search ClawHub API for skills."""
    try:
        import aiohttp
        url = f"{CLAWHUB_BASE}/api/v1/search"
        async with aiohttp.ClientSession() as session:
            async with session.get(url, params={"q": query}, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status == 200:
                    return await resp.json()
                return [{"error": f"ClawHub returned {resp.status}"}]
    except ImportError:
        return [{"error": "aiohttp not installed"}]
    except Exception as e:
        return [{"error": str(e)}]


async def install_skill(source: str) -> str:
    """Install a skill from ClawHub slug or GitHub URL."""
    dest = _workspace_skills_dir()
    dest.mkdir(parents=True, exist_ok=True)

    if source.startswith("http"):
        # GitHub URL — git clone
        slug = source.rstrip("/").split("/")[-1]
        target = dest / slug
        if target.exists():
            return f"Skill '{slug}' already installed at {target}"
        import subprocess
        result = subprocess.run(
            ["git", "clone", "--depth", "1", source, str(target)],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            return f"Failed to clone: {result.stderr}"
        _update_lock(slug, source=source, version="git", skill_type="skill")
        return f"Installed '{slug}' from GitHub to {target}. Start a new session to load it."
    else:
        # ClawHub slug
        slug = source.strip("/")
        target = dest / slug
        if target.exists():
            return f"Skill '{slug}' already installed at {target}"
        try:
            import aiohttp
            url = f"{CLAWHUB_BASE}/api/v1/download"
            async with aiohttp.ClientSession() as session:
                async with session.get(url, params={"slug": slug}, timeout=aiohttp.ClientTimeout(total=30)) as resp:
                    if resp.status != 200:
                        return f"ClawHub download failed: HTTP {resp.status}"
                    data = await resp.json()

            target.mkdir(parents=True, exist_ok=True)
            # Write SKILL.md
            if "content" in data:
                (target / "SKILL.md").write_text(data["content"], encoding="utf-8")
            # Write metadata
            if "metadata" in data:
                (target / "skill.json").write_text(
                    json.dumps(data["metadata"], indent=2), encoding="utf-8"
                )
            _update_lock(slug, source="clawhub", version=str(data.get("version", "latest")), skill_type="skill")
            return f"Installed '{slug}' from ClawHub to {target}. Start a new session to load it."
        except ImportError:
            return "Error: aiohttp not installed"
        except Exception as e:
            return f"Error installing skill: {e}"


async def update_skill(slug: str) -> str:
    lock = _read_lock().get("skills", {})
    entry = lock.get(slug)
    if not entry:
        return f"Skill '{slug}' is not tracked in .clawhub/lock.json"

    source = str(entry.get("source", "")).strip()
    target = _workspace_skills_dir() / slug
    if not target.exists():
        return f"Skill '{slug}' is missing from the workspace skills directory"

    if source == "clawhub":
        if target.exists():
            import shutil
            shutil.rmtree(target)
        return await install_skill(slug)

    if source.startswith("http"):
        import subprocess
        result = subprocess.run(["git", "-C", str(target), "pull", "--ff-only"], capture_output=True, text=True)
        if result.returncode != 0:
            return f"Failed to update '{slug}': {result.stderr.strip()}"
        _update_lock(slug, source=source, version="git", skill_type="skill")
        return f"Updated '{slug}' from {source}. Start a new session to load it."

    return f"Skill '{slug}' has an unsupported source '{source}'"


async def update_all_skills() -> str:
    lock = _read_lock().get("skills", {})
    if not lock:
        return "No ClawHub-managed skills are tracked in .clawhub/lock.json"
    results = []
    for slug in sorted(lock):
        results.append(await update_skill(slug))
    return "\n".join(results)


def invoke_skill(slug: str, function_name: str = "", **kwargs: Any) -> str:
    """Invoke a native skill function or return ClawHub instructions."""
    for base in _skill_runtime_paths() + [_builtin_skills_dir()]:
        skill_dir = base / slug
        if not skill_dir.is_dir():
            continue

        # ClawHub skill — return instructions
        md = skill_dir / "SKILL.md"
        if md.exists():
            return md.read_text(encoding="utf-8")

        # Native skill — import and call
        meta_file = skill_dir / "skill.json"
        py_file = skill_dir / "skill.py"
        if meta_file.exists() and py_file.exists():
            try:
                import importlib.util
                spec = importlib.util.spec_from_file_location(f"skill_{slug}", str(py_file))
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                if function_name and hasattr(mod, function_name):
                    return str(getattr(mod, function_name)(**kwargs))
                # If no function name, list available functions
                fns = [f for f in dir(mod) if not f.startswith("_") and callable(getattr(mod, f))]
                return f"Available functions in '{slug}': {', '.join(fns)}"
            except Exception as e:
                return f"Error invoking skill: {e}"

    return f"Skill '{slug}' not found"


async def invoke_skill_async(slug: str, function_name: str = "", **kwargs: Any) -> str:
    """Invoke a native skill function asynchronously or return ClawHub instructions."""
    for base in _skill_runtime_paths() + [_builtin_skills_dir()]:
        skill_dir = base / slug
        if not skill_dir.is_dir():
            continue

        md = skill_dir / "SKILL.md"
        if md.exists():
            task = kwargs.get("task", "")
            instructions = md.read_text(encoding="utf-8")
            if task:
                return f"Follow this skill for task: {task}\n\n{instructions}"
            return instructions

        meta_file = skill_dir / "skill.json"
        py_file = skill_dir / "skill.py"
        if meta_file.exists() and py_file.exists():
            try:
                import importlib.util

                spec = importlib.util.spec_from_file_location(f"skill_{slug}", str(py_file))
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)

                if function_name:
                    if not hasattr(mod, function_name):
                        available = list_native_skill_functions(slug)
                        return (
                            f"Function '{function_name}' not found in skill '{slug}'. "
                            f"Available functions: {', '.join(available) or '(none)'}"
                        )
                    result = getattr(mod, function_name)(**kwargs)
                    if inspect.isawaitable(result):
                        result = await result
                    return str(result)

                available = list_native_skill_functions(slug)
                return f"Available functions in '{slug}': {', '.join(available) or '(none)'}"
            except Exception as e:
                return f"Error invoking skill: {e}"

    return f"Skill '{slug}' not found"
