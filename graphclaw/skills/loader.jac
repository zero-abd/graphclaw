# graphclaw/skills/loader.jac
# Skill discovery, loading, and online installation
# Skills can be loaded from:
#   1. Built-in registry (graphclaw/skills/registry/)
#   2. User-installed skills (~/.graphclaw/skills/installed/)
#   3. Online — GitHub URL or central registry index

import from pathlib { Path };
import from importlib { import_module };
import from json { loads, dumps };
import from os { environ };
import from graphclaw.config.loader { load_config };
import from datetime { datetime, timezone };
import httpx;

# ── Skill node in the graph ────────────────────────────────────────────────────

node SkillNode {
    has name: str = "";
    has description: str = "";
    has version: str = "0.1.0";
    has author: str = "";
    has tools: list[str] = [];          # tool function names this skill exposes
    has requirements: list[str] = [];   # pip packages needed
    has source_url: str = "";
    has skill_path: str = "";           # filesystem path to skill directory
    has enabled: bool = True;
    has installed_at: str = "";

    def postinit {
        if not self.installed_at {
            self.installed_at = datetime.now(timezone.utc).isoformat();
        }
    }
}

edge HasSkill {}

# ── Skill manifest format (skill.json in each skill directory) ─────────────────
#
# {
#   "name": "base44",
#   "description": "Deploy and manage apps on Base44",
#   "version": "0.1.0",
#   "author": "graphclaw",
#   "tools": ["deploy_app", "get_app_status", "get_build_logs", "update_env_vars"],
#   "requirements": [],
#   "source_url": "https://github.com/graphclaw/skills-registry/tree/main/base44"
# }

glob BUILTIN_SKILLS_DIR: str = str(Path(__file__).parent / "registry");
glob REGISTRY_INDEX_URL: str = "https://raw.githubusercontent.com/graphclaw/skills-registry/main/index.json";

# ── Scan and register built-in + installed skills ─────────────────────────────

walker LoadSkills {
    can load with `root entry {
        cfg = load_config();
        installed_dir = Path(cfg.skills.installed_path).expanduser();

        dirs_to_scan = [
            Path(BUILTIN_SKILLS_DIR),
            installed_dir
        ];

        loaded = [];
        for skills_dir in dirs_to_scan {
            if not skills_dir.exists() { continue; }
            for skill_dir in skills_dir.iterdir() {
                if not skill_dir.is_dir() { continue; }
                manifest_path = skill_dir / "skill.json";
                if not manifest_path.exists() { continue; }

                manifest = loads(manifest_path.read_text());
                name = manifest.get("name", skill_dir.name);

                # Skip if already loaded
                existing = [here -->(:HasSkill:)--> (:SkillNode)][? name == name];
                if existing { continue; }

                sn = SkillNode(
                    name=name,
                    description=manifest.get("description", ""),
                    version=manifest.get("version", "0.1.0"),
                    author=manifest.get("author", ""),
                    tools=manifest.get("tools", []),
                    requirements=manifest.get("requirements", []),
                    source_url=manifest.get("source_url", ""),
                    skill_path=str(skill_dir)
                );
                here +:HasSkill:+> sn;
                loaded.append(name);
            }
        }
        report loaded;
    }
}

# ── List available skills ──────────────────────────────────────────────────────

walker ListSkills {
    has enabled_only: bool = True;

    can list with `root entry {
        skills = [here -->(:HasSkill:)--> (:SkillNode)];
        if self.enabled_only {
            skills = [s for s in skills if s.enabled];
        }
        report [{"name": s.name, "description": s.description,
                 "version": s.version, "tools": s.tools} for s in skills];
    }
}

# ── Get a skill by name ────────────────────────────────────────────────────────

walker GetSkill {
    has name: str;

    can get with `root entry {
        skills = [here -->(:HasSkill:)--> (:SkillNode)][
            ? name == self.name and enabled == True
        ];
        if skills { report skills[0]; }
        else { report None; }
    }
}

# ── Invoke a tool from a skill ─────────────────────────────────────────────────

walker InvokeSkillTool {
    has skill_name: str;
    has tool_name: str;
    has params: dict = {};

    can invoke with `root entry {
        skills = [here -->(:HasSkill:)--> (:SkillNode)][
            ? name == self.skill_name and enabled == True
        ];
        if not skills {
            report {"error": f"Skill '{self.skill_name}' not found or disabled"};
            disengage;
        }
        sk = skills[0];

        if self.tool_name not in sk.tools {
            report {"error": f"Tool '{self.tool_name}' not found in skill '{self.skill_name}'"};
            disengage;
        }

        # Dynamically import the skill module and call the tool function
        ::py::
        import importlib.util, sys, os, pathlib
        skill_path = pathlib.Path(sk.skill_path)
        mod_file = skill_path / "skill.py"
        if not mod_file.exists():
            mod_file = skill_path / "tools.py"
        if mod_file.exists():
            spec = importlib.util.spec_from_file_location(
                f"graphclaw_skill_{sk.name}", mod_file
            )
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            tool_fn = getattr(mod, self.tool_name, None)
            if tool_fn:
                import asyncio, inspect
                if inspect.iscoroutinefunction(tool_fn):
                    result = asyncio.get_event_loop().run_until_complete(
                        tool_fn(**self.params)
                    )
                else:
                    result = tool_fn(**self.params)
                _invoke_result = result
            else:
                _invoke_result = {"error": f"Function '{self.tool_name}' not found in skill module"}
        else:
            _invoke_result = {"error": f"No skill.py or tools.py found in {skill_path}"}
        ::py::

        report _invoke_result;
    }
}

# ── Fetch skill index from online registry ─────────────────────────────────────

walker FetchRegistryIndex {
    can fetch with `root entry {
        ::py::
        import httpx
        try:
            resp = httpx.get(REGISTRY_INDEX_URL, timeout=10.0)
            resp.raise_for_status()
            _index = resp.json()
        except Exception as e:
            _index = {"error": str(e), "skills": []}
        ::py::
        report _index;
    }
}

# ── Install a skill from online registry or GitHub URL ────────────────────────

walker InstallSkill {
    has source: str;   # "base44" | "graphclaw/base44" | "https://github.com/..."
    has force: bool = False;

    can install with `root entry {
        cfg = load_config();
        installed_dir = Path(cfg.skills.installed_path).expanduser();
        installed_dir.mkdir(parents=True, exist_ok=True);

        # Resolve source → download URL
        download_url = self._resolve_url(self.source);
        if not download_url {
            report {"error": f"Cannot resolve skill source: {self.source}"};
            disengage;
        }

        ::py::
        import httpx, zipfile, io, json, pathlib, shutil

        # Download zip/tarball from GitHub
        try:
            resp = httpx.get(download_url, timeout=30.0, follow_redirects=True)
            resp.raise_for_status()
        except Exception as e:
            _install_result = {"error": f"Download failed: {e}"}
            _installed = False
        else:
            # Extract
            try:
                z = zipfile.ZipFile(io.BytesIO(resp.content))
                # Find skill.json inside zip to get the skill name
                manifest_entry = next(
                    (n for n in z.namelist() if n.endswith("skill.json")), None
                )
                if not manifest_entry:
                    _install_result = {"error": "No skill.json found in archive"}
                    _installed = False
                else:
                    manifest = json.loads(z.read(manifest_entry))
                    skill_name = manifest.get("name", self.source.split("/")[-1])
                    target_dir = pathlib.Path(str(installed_dir)) / skill_name

                    if target_dir.exists() and not self.force:
                        _install_result = {"error": f"Skill '{skill_name}' already installed. Use force=True to reinstall."}
                        _installed = False
                    else:
                        if target_dir.exists():
                            shutil.rmtree(target_dir)
                        target_dir.mkdir(parents=True)

                        # Extract relevant files
                        prefix = "/".join(manifest_entry.split("/")[:-1]) + "/"
                        for entry in z.namelist():
                            if entry.startswith(prefix) and not entry.endswith("/"):
                                rel = entry[len(prefix):]
                                dest = target_dir / rel
                                dest.parent.mkdir(parents=True, exist_ok=True)
                                dest.write_bytes(z.read(entry))

                        _install_result = manifest
                        _installed = True
            except Exception as e:
                _install_result = {"error": f"Extraction failed: {e}"}
                _installed = False
        ::py::

        if _installed {
            # Register the newly installed skill in the graph
            sn = SkillNode(
                name=_install_result.get("name", self.source),
                description=_install_result.get("description", ""),
                version=_install_result.get("version", "0.1.0"),
                author=_install_result.get("author", ""),
                tools=_install_result.get("tools", []),
                requirements=_install_result.get("requirements", []),
                source_url=download_url,
                skill_path=str(installed_dir / _install_result.get("name", self.source))
            );
            here +:HasSkill:+> sn;
            report {"success": True, "skill": _install_result};
        } else {
            report _install_result;
        }
    }

    def _resolve_url(source: str) -> str {
        if source.startswith("https://") or source.startswith("http://") {
            return source;
        }
        # Short name — look up in registry index
        # Format: "org/name" or just "name" (assumes graphclaw org)
        if "/" not in source {
            source = f"graphclaw/{source}";
        }
        parts = source.split("/");
        org = parts[0];
        name = parts[1];
        return f"https://github.com/{org}/skills-registry/archive/refs/heads/main/{name}.zip";
    }
}

# ── Remove an installed skill ──────────────────────────────────────────────────

walker UninstallSkill {
    has name: str;

    can uninstall with `root entry {
        skills = [here -->(:HasSkill:)--> (:SkillNode)][? name == self.name];
        if not skills {
            report {"error": f"Skill '{self.name}' not found"};
            disengage;
        }
        sk = skills[0];

        ::py::
        import shutil, pathlib
        p = pathlib.Path(sk.skill_path)
        if p.exists() and "installed" in str(p):  # safety: only remove user-installed
            shutil.rmtree(p)
            _removed = True
        else:
            _removed = False
        ::py::

        if _removed {
            del sk;
            report {"success": True};
        } else {
            report {"error": "Cannot remove built-in skills"};
        }
    }
}
