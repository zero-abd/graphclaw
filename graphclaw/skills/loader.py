"""Skill loader — discovers local skills and integrates with ClawHub API."""
from __future__ import annotations
import json
import os
import re
import shutil
from pathlib import Path
from typing import Any, Dict, List, Optional
from graphclaw.config.loader import load_config


CLAWHUB_BASE = "https://clawhub.ai"


def _skills_dir() -> Path:
    cfg = load_config()
    p = cfg.skills.installed_path
    if p:
        return Path(p)
    return Path(cfg.workspace) / "skills" / "installed"


def _builtin_skills_dir() -> Path:
    return Path(__file__).parent / "registry"


def list_skills() -> List[Dict[str, Any]]:
    """List all installed skills (builtin + user-installed)."""
    skills = []
    for base in [_builtin_skills_dir(), _skills_dir()]:
        if not base.is_dir():
            continue
        for entry in sorted(base.iterdir()):
            if not entry.is_dir():
                continue
            meta_file = entry / "skill.json"
            md_file = entry / "SKILL.md"
            if meta_file.exists():
                try:
                    meta = json.loads(meta_file.read_text(encoding="utf-8"))
                    skills.append({
                        "name": meta.get("name", entry.name),
                        "slug": entry.name,
                        "type": "native",
                        "description": meta.get("description", ""),
                        "path": str(entry),
                    })
                except Exception:
                    pass
            elif md_file.exists():
                front = _parse_frontmatter(md_file.read_text(encoding="utf-8"))
                skills.append({
                    "name": front.get("name", entry.name),
                    "slug": entry.name,
                    "type": "clawhub",
                    "description": front.get("description", ""),
                    "path": str(entry),
                })
    return skills


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
    dest = _skills_dir()
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
        return f"Installed '{slug}' from GitHub to {target}"
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
            return f"Installed '{slug}' from ClawHub to {target}"
        except ImportError:
            return "Error: aiohttp not installed"
        except Exception as e:
            return f"Error installing skill: {e}"


def invoke_skill(slug: str, function_name: str = "", **kwargs: Any) -> str:
    """Invoke a native skill function or return ClawHub instructions."""
    for base in [_builtin_skills_dir(), _skills_dir()]:
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
