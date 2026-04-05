# graphclaw/config/loader.jac
# Loads config from ~/.graphclaw/config.json or GRAPHCLAW_CONFIG env var

import from graphclaw.config.schema { Config };
import from pathlib { Path };
import from os { environ, path };
import from json { loads, dumps };

glob _config: Config | None = None;

def get_workspace_dir() -> str {
    env_path = environ.get("GRAPHCLAW_WORKSPACE_DIR", "");
    if env_path { return env_path; }
    return str(Path.home() / ".graphclaw" / "workspace");
}

def get_config_path() -> str {
    env_path = environ.get("GRAPHCLAW_CONFIG_PATH", "");
    if env_path { return env_path; }
    return str(Path.home() / ".graphclaw" / "config.json");
}

def load_config() -> Config {
    global _config;
    if _config { return _config; }

    config_path = Path(get_config_path());
    if config_path.exists() {
        raw = loads(config_path.read_text(encoding="utf-8"));
        _config = Config(**raw);
    } else {
        _config = Config();
    }

    # Override workspace from env
    ws = environ.get("GRAPHCLAW_WORKSPACE_DIR", "");
    if ws { _config.workspace = ws; }

    # Override provider keys from env
    ak = environ.get("OPENROUTER_API_KEY", "");
    if ak { _config.providers.openrouter.api_key = ak; }
    ak = environ.get("ANTHROPIC_API_KEY", "");
    if ak { _config.providers.anthropic.api_key = ak; }
    ak = environ.get("OPENAI_API_KEY", "");
    if ak { _config.providers.openai.api_key = ak; }

    return _config;
}

def save_config(cfg: Config) -> None {
    config_path = Path(get_config_path());
    config_path.parent.mkdir(parents=True, exist_ok=True);
    config_path.write_text(
        dumps(cfg.__dict__, indent=2, default=str),
        encoding="utf-8"
    );
}

def ensure_workspace() -> str {
    ws = Path(load_config().workspace).expanduser();
    (ws / "memory").mkdir(parents=True, exist_ok=True);
    (ws / "sessions").mkdir(parents=True, exist_ok=True);
    (ws / "skills" / "installed").mkdir(parents=True, exist_ok=True);
    return str(ws);
}
