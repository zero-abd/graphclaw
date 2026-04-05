"""Skill loader — discovers local skills, recommends them, and integrates with ClawHub."""
from __future__ import annotations
import asyncio
import io
import inspect
import json
import re
import shutil
import zipfile
from pathlib import Path
from typing import Any, Dict, List
from graphclaw.config.loader import load_config


CLAWHUB_BASE = "https://clawhub.ai"
_SKILL_RECOMMENDATION_CACHE: dict[tuple[str, int, str], list[dict[str, Any]]] = {}


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
    for candidate in _skill_candidate_catalog():
        skills.append({
            "name": candidate.get("name", candidate.get("slug", "")),
            "slug": candidate.get("slug", ""),
            "type": candidate.get("type", "skill"),
            "description": candidate.get("description", ""),
            "path": candidate.get("path", ""),
            "source": candidate.get("source", "local"),
            "tags": candidate.get("tags", []),
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


def _frontmatter_list(frontmatter: Dict[str, str], key: str) -> list[str]:
    value = str(frontmatter.get(key, "") or "").strip()
    if not value:
        return []
    normalized = value.strip().strip("[]")
    parts = [part.strip().strip('"').strip("'") for part in normalized.split(",")]
    return [part for part in parts if part]


def _strip_frontmatter(text: str) -> str:
    return re.sub(r'^---\s*\n.*?\n---\s*\n?', '', text, flags=re.DOTALL)


def _skill_preview_from_markdown(text: str, limit: int = 280) -> str:
    stripped = _strip_frontmatter(text)
    lines = []
    for raw in stripped.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        lines.append(line)
        if len(" ".join(lines)) >= limit:
            break
    preview = " ".join(lines)
    return preview[:limit].strip()


def _task_terms(text: str) -> set[str]:
    return {
        token
        for token in re.findall(r"[a-z0-9][a-z0-9_-]{2,}", text.lower())
        if token not in {"the", "and", "for", "with", "from", "that", "this", "into", "your", "have"}
    }


def _candidate_keyword_overlap(task: str, candidate: dict[str, Any]) -> int:
    terms = _task_terms(task)
    haystack = " ".join([
        str(candidate.get("slug", "")),
        str(candidate.get("name", "")),
        str(candidate.get("description", "")),
        " ".join(candidate.get("tags", []) or []),
        str(candidate.get("preview", "")),
    ]).lower()
    return sum(1 for term in terms if term in haystack)


def _skill_candidate_catalog() -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    lock = _read_lock().get("skills", {})
    seen: set[str] = set()
    for base in _skill_runtime_paths() + [_builtin_skills_dir()]:
        if not base.is_dir():
            continue
        for entry in sorted(base.iterdir()):
            if not entry.is_dir() or entry.name.startswith('.') or entry.name in seen:
                continue
            meta_file = entry / "skill.json"
            md_file = entry / "SKILL.md"
            if not (meta_file.exists() or md_file.exists()):
                continue

            description = ""
            name = entry.name
            tags: list[str] = []
            preview = ""
            skill_type = "skill"

            if meta_file.exists():
                try:
                    meta = json.loads(meta_file.read_text(encoding="utf-8"))
                    name = str(meta.get("name", name))
                    description = str(meta.get("description", "") or "")
                    raw_tags = meta.get("tags", []) or []
                    if isinstance(raw_tags, list):
                        tags = [str(tag).strip() for tag in raw_tags if str(tag).strip()]
                    skill_type = str(meta.get("type", "native") or "native")
                    preview = str(meta.get("summary", "") or "")
                except Exception:
                    pass

            if md_file.exists():
                text = md_file.read_text(encoding="utf-8")
                front = _parse_frontmatter(text)
                name = front.get("name", name)
                description = front.get("description", description)
                tags = tags or _frontmatter_list(front, "tags") or _frontmatter_list(front, "keywords")
                preview = preview or _skill_preview_from_markdown(text)
                skill_type = "skill"

            source = lock.get(entry.name, {}).get("source", "bundled" if base == _builtin_skills_dir() else "local")
            candidates.append({
                "slug": entry.name,
                "name": name,
                "description": description,
                "path": str(entry),
                "type": skill_type,
                "source": source,
                "tags": tags,
                "preview": preview,
            })
            seen.add(entry.name)
    return candidates


def _candidate_signature(candidates: list[dict[str, Any]]) -> str:
    compact = [
        {
            "slug": item.get("slug", ""),
            "description": item.get("description", ""),
            "source": item.get("source", ""),
            "tags": item.get("tags", []),
            "preview": item.get("preview", ""),
        }
        for item in candidates
    ]
    return json.dumps(compact, sort_keys=True)


def _prefilter_candidates(task: str, candidates: list[dict[str, Any]], *, max_candidates: int = 8) -> list[dict[str, Any]]:
    if len(candidates) <= max_candidates:
        return candidates
    terms = _task_terms(task)
    scored: list[tuple[int, dict[str, Any]]] = []
    for candidate in candidates:
        haystack = " ".join([
            str(candidate.get("slug", "")),
            str(candidate.get("name", "")),
            str(candidate.get("description", "")),
            " ".join(candidate.get("tags", []) or []),
            str(candidate.get("preview", "")),
        ]).lower()
        score = _candidate_keyword_overlap(task, candidate)
        if task and task.lower() in haystack:
            score += 2
        scored.append((score, candidate))
    scored.sort(key=lambda item: (item[0], len(str(item[1].get("description", "")))), reverse=True)
    head = [candidate for _, candidate in scored[:max_candidates]]
    return head or candidates[:max_candidates]


def _fallback_recommendations(task: str, candidates: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    picks = _prefilter_candidates(task, candidates, max_candidates=max(limit, 3))
    results = []
    for idx, candidate in enumerate(picks[:limit], start=1):
        results.append({
            "slug": candidate.get("slug", ""),
            "name": candidate.get("name", candidate.get("slug", "")),
            "description": candidate.get("description", ""),
            "source": candidate.get("source", "local"),
            "keyword_overlap": _candidate_keyword_overlap(task, candidate),
            "confidence": max(0.2, 0.6 - ((idx - 1) * 0.1)),
            "reason": "Closest installed skill match from local metadata.",
        })
    return results


def _recommend_from_candidates(task: str, candidates: list[dict[str, Any]], limit: int = 3) -> list[dict[str, Any]]:
    task = str(task or "").strip()
    if not task or not candidates:
        return []

    shortlisted = _prefilter_candidates(task, candidates)
    signature = _candidate_signature(shortlisted)
    cache_key = (task, limit, signature)
    if cache_key in _SKILL_RECOMMENDATION_CACHE:
        return _SKILL_RECOMMENDATION_CACHE[cache_key]

    by_slug = {candidate["slug"]: candidate for candidate in shortlisted}
    try:
        import jaclang  # noqa: F401
        from graphclaw.skills.selector import SkillCandidate, recommend_skill_matches

        matches = recommend_skill_matches(
            task,
            [
                SkillCandidate(
                    slug=candidate["slug"],
                    name=candidate.get("name", ""),
                    description=candidate.get("description", ""),
                    source=candidate.get("source", ""),
                    tags=candidate.get("tags", []) or [],
                    preview=candidate.get("preview", ""),
                )
                for candidate in shortlisted
            ],
            limit,
        )
        if isinstance(matches, str):
            matches = json.loads(matches)

        recommendations: list[dict[str, Any]] = []
        seen: set[str] = set()
        for match in matches:
            if isinstance(match, dict):
                slug = str(match.get("slug", "") or "").strip()
                raw_confidence = match.get("confidence", 0.0)
                raw_reason = match.get("reason", "")
            else:
                slug = str(getattr(match, "slug", "") or "").strip()
                raw_confidence = getattr(match, "confidence", 0.0)
                raw_reason = getattr(match, "reason", "")
            if not slug or slug not in by_slug or slug in seen:
                continue
            candidate = by_slug[slug]
            confidence = raw_confidence
            try:
                confidence = max(0.0, min(1.0, float(confidence)))
            except Exception:
                confidence = 0.0
            recommendations.append({
                "slug": slug,
                "name": candidate.get("name", slug),
                "description": candidate.get("description", ""),
                "source": candidate.get("source", "local"),
                "keyword_overlap": _candidate_keyword_overlap(task, candidate),
                "confidence": confidence,
                "reason": str(raw_reason or "").strip(),
            })
            seen.add(slug)

        if not recommendations:
            recommendations = _fallback_recommendations(task, shortlisted, limit)
    except Exception:
        recommendations = _fallback_recommendations(task, shortlisted, limit)

    _SKILL_RECOMMENDATION_CACHE[cache_key] = recommendations[:limit]
    return recommendations[:limit]


def recommend_skills(task: str, limit: int = 3) -> list[dict[str, Any]]:
    return _recommend_from_candidates(task, _skill_candidate_catalog(), limit=limit)


def build_recommended_skills_summary(task: str, limit: int = 3) -> str:
    recommendations = recommend_skills(task, limit=limit)
    if not recommendations:
        return "No strong installed skill match was found for this task."
    lines = []
    for skill in recommendations:
        lines.append(
            f"- {skill['slug']} ({skill['confidence']:.2f}) from {skill['source']}: {skill['reason'] or skill['description']}"
        )
    return "\n".join(lines)


async def search_clawhub(query: str) -> List[Dict[str, Any]]:
    """Search ClawHub API for skills."""
    try:
        import httpx
        url = f"{CLAWHUB_BASE}/api/v1/search"
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, params={"q": query})
            if resp.status_code != 200:
                return [{"error": f"ClawHub returned {resp.status_code}"}]
            payload = resp.json()
            if isinstance(payload, dict) and isinstance(payload.get("results"), list):
                return payload["results"]
            if isinstance(payload, list):
                return payload
            return [{"error": "Unexpected ClawHub response format"}]
    except Exception as e:
        return [{"error": str(e)}]


def search_installable_skills_from_results(task: str, results: list[dict[str, Any]], limit: int = 3) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    for item in results:
        slug = str(item.get("slug", "") or "").strip()
        if not slug:
            continue
        candidates.append({
            "slug": slug,
            "name": str(item.get("displayName", slug) or slug),
            "description": str(item.get("summary", "") or ""),
            "path": "",
            "type": "skill",
            "source": "clawhub",
            "tags": [slug.replace("-", " ")],
            "preview": str(item.get("summary", "") or ""),
            "search_score": item.get("score", 0.0),
        })
    return _recommend_from_candidates(task, candidates, limit=limit)


async def search_installable_skills(task: str, limit: int = 3) -> list[dict[str, Any]]:
    results = await search_clawhub(task)
    if results and isinstance(results[0], dict) and results[0].get("error"):
        return results
    return search_installable_skills_from_results(task, results, limit=limit)


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
            import httpx
            url = f"{CLAWHUB_BASE}/api/v1/download"
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.get(url, params={"slug": slug})
            if resp.status_code != 200:
                return f"ClawHub download failed: HTTP {resp.status_code}"

            target.mkdir(parents=True, exist_ok=True)
            version = "latest"
            content_type = resp.headers.get("content-type", "")
            if "application/json" in content_type:
                data = resp.json()
                if "content" in data:
                    (target / "SKILL.md").write_text(data["content"], encoding="utf-8")
                if "metadata" in data:
                    (target / "skill.json").write_text(
                        json.dumps(data["metadata"], indent=2), encoding="utf-8"
                    )
                version = str(data.get("version", "latest"))
            else:
                with zipfile.ZipFile(io.BytesIO(resp.content)) as archive:
                    archive.extractall(target)
                skill_md = target / "SKILL.md"
                if not skill_md.exists():
                    nested = [path.parent for path in target.rglob("SKILL.md")]
                    if len(nested) == 1:
                        nested_dir = nested[0]
                        for item in nested_dir.iterdir():
                            shutil.move(str(item), target / item.name)
                        shutil.rmtree(nested_dir, ignore_errors=True)

            _update_lock(slug, source="clawhub", version=version, skill_type="skill")
            return f"Installed '{slug}' from ClawHub to {target}. Start a new session to load it."
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
