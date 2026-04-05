# graphclaw/skills/loader.jac
# Skill discovery, loading, and online installation
# Skills can be loaded from:
#   1. Built-in registry (graphclaw/skills/registry/)
#   2. User-installed skills (~/.graphclaw/skills/installed/)
#   3. Online -- GitHub URL or central registry index

import from pathlib { Path }
import from importlib { import_module }
import from json { loads, dumps }
import from os { environ }
import from graphclaw.config.loader { load_config }
import from datetime { datetime, timezone }
import httpx;

# -- Skill node in the graph ----------------------------------------------------

node SkillNode {
    has name: str = "";
    has description: str = "";
    has version: str = "0.1.0";
    has author: str = "";
    has tools: list[str] = [];          # tool function names this skill exposes (native skills only)
    has requirements: list[str] = [];   # pip packages needed
    has source_url: str = "";
    has skill_path: str = "";           # filesystem path to skill directory
    has enabled: bool = True;
    has installed_at: str = "";
    # ClawHub skill fields
    has skill_type: str = "native";     # "native" | "clawhub"
    has instructions: str = "";         # SKILL.md body (clawhub skills)
    has env_vars: list[str] = [];       # required env vars from SKILL.md frontmatter
    has required_bins: list[str] = [];  # required binaries from SKILL.md frontmatter

    def postinit {
        if not self.installed_at {
            self.installed_at = datetime.now(timezone.utc).isoformat();
        }
    }
}

edge HasSkill {}

# -- Skill manifest format (skill.json in each skill directory) -----------------
#
# {
#   "name": "base44",
#   "description": "Deploy and manage apps on Base44",
#   "version": "0.1.0",
#   "author": "graphclaw",
#   "tools": ["deploy_app", "get_app_status", "get_build_logs", "update_env_vars"],
#   "requirements": [],
#   "source_url": "https://clawhub.ai/skills/base44"
# }

glob BUILTIN_SKILLS_DIR: str = str(Path(__file__).parent / "registry");
glob CLAWHUB_BASE_URL: str = "https://clawhub.ai";

# -- Scan and register built-in + installed skills -----------------------------

walker LoadSkills {
    can load with `root() entry {
        cfg = load_config();
        installed_dir = Path(cfg.skills.installed_path).expanduser();

        loaded = [];

        # -- Built-in native skills (skill.json + skill.py) -----------------
        builtin_dir = Path(BUILTIN_SKILLS_DIR);
        if builtin_dir.exists() {
            for skill_dir in builtin_dir.iterdir() {
                if not skill_dir.is_dir() { continue; }
                manifest_path = skill_dir / "skill.json";
                if not manifest_path.exists() { continue; }

                manifest = loads(manifest_path.read_text());
                name = manifest.get("name", skill_dir.name);
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
                    skill_path=str(skill_dir),
                    skill_type="native"
                );
                here +:HasSkill:+> sn;
                loaded.append(name);
            }
        }

        # -- User-installed skills: native (skill.json) or ClawHub (SKILL.md) -
        if installed_dir.exists() {
            for skill_dir in installed_dir.iterdir() {
                if not skill_dir.is_dir() { continue; }
                name = skill_dir.name;
                existing = [here -->(:HasSkill:)--> (:SkillNode)][? name == name];
                if existing { continue; }

                native_manifest = skill_dir / "skill.json";
                clawhub_manifest = skill_dir / "SKILL.md";

                if native_manifest.exists() {
                    manifest = loads(native_manifest.read_text());
                    sn = SkillNode(
                        name=manifest.get("name", name),
                        description=manifest.get("description", ""),
                        version=manifest.get("version", "0.1.0"),
                        author=manifest.get("author", ""),
                        tools=manifest.get("tools", []),
                        requirements=manifest.get("requirements", []),
                        source_url=manifest.get("source_url", ""),
                        skill_path=str(skill_dir),
                        skill_type="native"
                    );
                    here +:HasSkill:+> sn;
                    loaded.append(manifest.get("name", name));
                } elif clawhub_manifest.exists() {
                    ::py::
                    import yaml, re
                    raw = clawhub_manifest.read_text(encoding="utf-8", errors="replace")
                    match = re.match(r'^---\n(.*?)\n---\n?(.*)', raw, re.DOTALL)
                    if match:
                        try:
                            _fm = yaml.safe_load(match.group(1)) or {}
                        except Exception:
                            _fm = {}
                        _body = match.group(2).strip()
                    else:
                        _fm = {}
                        _body = raw.strip()
                    _openclaw = (_fm.get("metadata") or {}).get("openclaw", {})
                    _req = _openclaw.get("requires") or {}
                    _env_vars = _req.get("env", [])
                    _bins = _req.get("bins", [])
                    _ch_name = _fm.get("name", name)
                    _ch_desc = _fm.get("description", "")
                    _ch_version = str(_fm.get("version", "0.1.0"))
                    _ch_author = str(_fm.get("author", ""))
                    ::py::
                    sn = SkillNode(
                        name=_ch_name,
                        description=_ch_desc,
                        version=_ch_version,
                        author=_ch_author,
                        tools=[],
                        requirements=[],
                        source_url=f"{CLAWHUB_BASE_URL}/skills/{name}",
                        skill_path=str(skill_dir),
                        skill_type="clawhub",
                        instructions=_body,
                        env_vars=_env_vars,
                        required_bins=_bins
                    );
                    here +:HasSkill:+> sn;
                    loaded.append(_ch_name);
                }
            }
        }

        report loaded;
    }
}

# -- List available skills ------------------------------------------------------

walker ListSkills {
    has enabled_only: bool = True;

    can list with `root() entry {
        skills = [here -->(:HasSkill:)--> (:SkillNode)];
        if self.enabled_only {
            skills = [s for s in skills if s.enabled];
        }
        report [{
            "name": s.name,
            "description": s.description,
            "version": s.version,
            "tools": s.tools,
            "skill_type": s.skill_type,
            "instructions": s.instructions,
            "env_vars": s.env_vars,
            "required_bins": s.required_bins,
            "source_url": s.source_url
        } for s in skills];
    }
}

# -- Get a skill by name --------------------------------------------------------

walker GetSkill {
    has name: str;

    can get with `root() entry {
        skills = [here -->(:HasSkill:)--> (:SkillNode)][
            ? name == self.name and enabled == True
        ];
        if skills { report skills[0]; }
        else { report None; }
    }
}

# -- Invoke a tool from a skill -------------------------------------------------

walker InvokeSkillTool {
    has skill_name: str;
    has tool_name: str;    # ignored for clawhub skills
    has params: dict = {};

    can invoke with `root() entry {
        skills = [here -->(:HasSkill:)--> (:SkillNode)][
            ? name == self.skill_name and enabled == True
        ];
        if not skills {
            report {"error": f"Skill '{self.skill_name}' not found or disabled"};
            disengage;
        }
        sk = skills[0];

        # -- ClawHub skill: return instructions for the agent to follow ------
        if sk.skill_type == "clawhub" {
            task = self.params.get("task", "(no task specified)");
            env_note = "";
            if sk.env_vars {
                env_note = f"\n\n**Required environment variables:** {', '.join(sk.env_vars)}";
            }
            bins_note = "";
            if sk.required_bins {
                bins_note = f"\n**Required binaries:** {', '.join(sk.required_bins)}";
            }
            report f"# Skill: {sk.name}\n\n{sk.instructions}{env_note}{bins_note}\n\n## Your Task\n{task}\n\nUse your shell, web_fetch, web_search, read_file, and write_file tools to complete this task by following the instructions above.";
            disengage;
        }

        # -- Native skill: dynamically import and call Python function --------
        if self.tool_name not in sk.tools {
            report {"error": f"Tool '{self.tool_name}' not found in skill '{self.skill_name}'"};
            disengage;
        }

        ::py::
        import importlib.util, pathlib
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
                    try:
                        loop = asyncio.get_running_loop()
                        import concurrent.futures
                        with concurrent.futures.ThreadPoolExecutor() as pool:
                            _invoke_result = pool.submit(
                                asyncio.run, tool_fn(**self.params)
                            ).result()
                    except RuntimeError:
                        _invoke_result = asyncio.run(tool_fn(**self.params))
                else:
                    _invoke_result = tool_fn(**self.params)
            else:
                _invoke_result = {"error": f"Function '{self.tool_name}' not found in skill module"}
        else:
            _invoke_result = {"error": f"No skill.py or tools.py found in {skill_path}"}
        ::py::

        report _invoke_result;
    }
}

# -- Search ClawHub registry ----------------------------------------------------

walker SearchClawHub {
    has query: str;
    has limit: int = 10;

    can search with `root() entry {
        ::py::
        import httpx
        try:
            resp = httpx.get(
                f"{CLAWHUB_BASE_URL}/api/v1/search",
                params={"q": self.query},
                timeout=10.0
            )
            resp.raise_for_status()
            data = resp.json()
            _results = data.get("items", data) if isinstance(data, dict) else data
        except Exception as e:
            _results = {"error": str(e)}
        ::py::
        report _results;
    }
}

# -- List skills on ClawHub -----------------------------------------------------

walker ListClawHubSkills {
    has limit: int = 20;
    has offset: int = 0;

    can list with `root() entry {
        ::py::
        import httpx
        try:
            resp = httpx.get(
                f"{CLAWHUB_BASE_URL}/api/v1/skills",
                params={"limit": self.limit, "offset": self.offset},
                timeout=10.0
            )
            resp.raise_for_status()
            data = resp.json()
            _results = data.get("items", data) if isinstance(data, dict) else data
        except Exception as e:
            _results = {"error": str(e)}
        ::py::
        report _results;
    }
}

# -- Install a skill -- ClawHub slug or direct GitHub URL -----------------------

walker InstallSkill {
    has source: str;   # "kubernetes" | "https://github.com/org/repo/..."
    has force: bool = False;

    can install with `root() entry {
        # If it's a URL, treat as a GitHub release ZIP (native skill.json format)
        if self.source.startswith("http") {
            report self._install_from_url(here);
            disengage;
        }
        # Otherwise, treat as a ClawHub slug
        report self._install_from_clawhub(here);
    }

    def _install_from_clawhub(graph_root) -> dict {
        cfg = load_config();
        installed_dir = Path(cfg.skills.installed_path).expanduser();
        installed_dir.mkdir(parents=True, exist_ok=True);

        ::py::
        import httpx, zipfile, io, pathlib, shutil, yaml, re

        slug = self.source
        installed_dir_py = pathlib.Path(str(installed_dir))
        target_dir = installed_dir_py / slug

        if target_dir.exists() and not self.force:
            _ch_result = {"error": f"Skill '{slug}' already installed. Use force=True to reinstall."}
            _ch_ok = False
        else:
            try:
                resp = httpx.get(
                    f"{CLAWHUB_BASE_URL}/api/v1/download",
                    params={"slug": slug},
                    timeout=30.0,
                    follow_redirects=True
                )
                resp.raise_for_status()
            except Exception as e:
                _ch_result = {"error": f"Download from ClawHub failed: {e}"}
                _ch_ok = False
            else:
                try:
                    z = zipfile.ZipFile(io.BytesIO(resp.content))
                    skill_md_entry = next(
                        (n for n in z.namelist() if n.endswith("SKILL.md")), None
                    )
                    if not skill_md_entry:
                        _ch_result = {"error": "No SKILL.md found in ClawHub archive"}
                        _ch_ok = False
                    else:
                        raw = z.read(skill_md_entry).decode("utf-8", errors="replace")
                        match = re.match(r'^---\n(.*?)\n---\n?(.*)', raw, re.DOTALL)
                        if match:
                            try:
                                _fm = yaml.safe_load(match.group(1)) or {}
                            except Exception:
                                _fm = {}
                            _body = match.group(2).strip()
                        else:
                            _fm = {}
                            _body = raw.strip()

                        _openclaw_meta = (_fm.get("metadata") or {}).get("openclaw", {})
                        _req = _openclaw_meta.get("requires") or {}

                        if target_dir.exists():
                            shutil.rmtree(target_dir)
                        target_dir.mkdir(parents=True)

                        prefix = "/".join(skill_md_entry.split("/")[:-1])
                        prefix = prefix + "/" if prefix else ""
                        for entry in z.namelist():
                            if entry.startswith(prefix) and not entry.endswith("/"):
                                rel = entry[len(prefix):]
                                if rel:
                                    dest = target_dir / rel
                                    dest.parent.mkdir(parents=True, exist_ok=True)
                                    dest.write_bytes(z.read(entry))

                        _ch_result = {
                            "name": _fm.get("name", slug),
                            "description": _fm.get("description", ""),
                            "version": str(_fm.get("version", "0.1.0")),
                            "author": str(_fm.get("author", "")),
                            "instructions": _body,
                            "env_vars": _req.get("env", []),
                            "required_bins": _req.get("bins", []),
                            "skill_path": str(target_dir)
                        }
                        _ch_ok = True
                except Exception as e:
                    _ch_result = {"error": f"Extraction failed: {e}"}
                    _ch_ok = False
        ::py::

        if _ch_ok {
            existing = [graph_root -->(:HasSkill:)--> (:SkillNode)][? name == _ch_result["name"]];
            if existing { del existing[0]; }
            sn = SkillNode(
                name=_ch_result["name"],
                description=_ch_result["description"],
                version=_ch_result["version"],
                author=_ch_result.get("author", ""),
                tools=[],
                requirements=[],
                source_url=f"{CLAWHUB_BASE_URL}/skills/{self.source}",
                skill_path=_ch_result["skill_path"],
                skill_type="clawhub",
                instructions=_ch_result["instructions"],
                env_vars=_ch_result.get("env_vars", []),
                required_bins=_ch_result.get("required_bins", [])
            );
            graph_root +:HasSkill:+> sn;
            return {"success": True, "skill": _ch_result};
        }
        return _ch_result;
    }

    def _install_from_url(graph_root) -> dict {
        cfg = load_config();
        installed_dir = Path(cfg.skills.installed_path).expanduser();
        installed_dir.mkdir(parents=True, exist_ok=True);

        ::py::
        import httpx, zipfile, io, json, pathlib, shutil
        try:
            resp = httpx.get(self.source, timeout=30.0, follow_redirects=True)
            resp.raise_for_status()
            z = zipfile.ZipFile(io.BytesIO(resp.content))
            manifest_entry = next(
                (n for n in z.namelist() if n.endswith("skill.json")), None
            )
            if not manifest_entry:
                _url_result = {"error": "No skill.json found in archive"}
                _url_ok = False
            else:
                manifest = json.loads(z.read(manifest_entry))
                skill_name = manifest.get("name", self.source.split("/")[-1].replace(".zip",""))
                target_dir = pathlib.Path(str(installed_dir)) / skill_name
                if target_dir.exists() and not self.force:
                    _url_result = {"error": f"Skill '{skill_name}' already installed"}
                    _url_ok = False
                else:
                    if target_dir.exists():
                        shutil.rmtree(target_dir)
                    target_dir.mkdir(parents=True)
                    prefix = "/".join(manifest_entry.split("/")[:-1]) + "/"
                    for entry in z.namelist():
                        if entry.startswith(prefix) and not entry.endswith("/"):
                            rel = entry[len(prefix):]
                            if rel:
                                dest = target_dir / rel
                                dest.parent.mkdir(parents=True, exist_ok=True)
                                dest.write_bytes(z.read(entry))
                    manifest["skill_path"] = str(target_dir)
                    _url_result = manifest
                    _url_ok = True
        except Exception as e:
            _url_result = {"error": str(e)}
            _url_ok = False
        ::py::

        if _url_ok {
            existing = [graph_root -->(:HasSkill:)--> (:SkillNode)][? name == _url_result["name"]];
            if existing { del existing[0]; }
            sn = SkillNode(
                name=_url_result["name"],
                description=_url_result.get("description", ""),
                version=_url_result.get("version", "0.1.0"),
                author=_url_result.get("author", ""),
                tools=_url_result.get("tools", []),
                requirements=_url_result.get("requirements", []),
                source_url=self.source,
                skill_path=_url_result["skill_path"],
                skill_type="native"
            );
            graph_root +:HasSkill:+> sn;
            return {"success": True, "skill": _url_result};
        }
        return _url_result;
    }
}

# -- Remove an installed skill --------------------------------------------------

walker UninstallSkill {
    has name: str;

    can uninstall with `root() entry {
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
