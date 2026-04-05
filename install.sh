#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Graphclaw Installer (Linux / macOS / WSL)
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.sh | bash
#  Or locally:
#    bash install.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
W='\033[1;37m'; D='\033[2m'; NC='\033[0m'; BOLD='\033[1m'

# ── Helpers ───────────────────────────────────────────────────────────────────
step_n=0; total_steps=6
step() { step_n=$((step_n + 1)); echo ""; echo -e "${BOLD}${W}  [$step_n/$total_steps] $1${NC}"; echo -e "  ${D}$(printf '%.0s─' $(seq 1 60))${NC}"; }
ok()   { echo -e "  ${G}✓${NC} $1"; }
warn() { echo -e "  ${Y}⚠${NC}  $1"; }
fail() { echo -e "  ${R}✗${NC} $1"; exit 1; }
info() { echo -e "  ${D}$1${NC}"; }
hint() { echo -e "  ${D}    ↳ $1${NC}"; }

ask_optional() {
    REPLY=""
    echo -ne "  ${C}?${NC} ${BOLD}$1${NC} ${D}(optional, Enter to skip)${NC}: "
    if ! read -r REPLY; then
        REPLY=""
    fi
}
ask_required() {
    REPLY=""
    while true; do
        echo -ne "  ${C}?${NC} ${BOLD}$1${NC}: "
        if ! read -r REPLY; then
            fail "Input aborted."
        fi
        [ -n "$REPLY" ] && return
        echo -e "  ${R}  Required — please enter a value.${NC}"
    done
}
ask_choice() {
    local prompt="$1" valid="$2" default="$3"
    local answer=""
    REPLY="$default"
    while true; do
        echo -ne "  ${C}?${NC} ${BOLD}$prompt${NC} ${D}[default: ${default}]${NC}: "
        if ! read -r answer; then
            fail "Input aborted."
        fi
        REPLY="${answer:-$default}"
        for v in $valid; do [ "$REPLY" = "$v" ] && return; done
        echo -e "  ${R}  Invalid — enter one of: ${valid}${NC}"
    done
}

# ── Banner ────────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${C}${BOLD}"
cat << 'BANNER'
  +===========================================================+
  |                                                           |
  |    GRAPHCLAW                              v0.1.0          |
  |    Graph-native multi-agent AI platform in Jac            |
  |                                                           |
  +===========================================================+
BANNER
echo -e "${NC}"

# ── Detect OS ────────────────────────────────────────────────────────────────
OS="$(uname -s 2>/dev/null || echo "unknown")"
case "$OS" in
    Linux*)  PLATFORM="linux" ;;
    Darwin*) PLATFORM="mac" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows-bash" ;;
    *)       PLATFORM="unknown" ;;
esac

if [ "$PLATFORM" = "windows-bash" ]; then
    warn "Detected Windows (Git Bash). For best experience use PowerShell:"
    echo -e "       ${W}.\\install.ps1${NC}"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Python
# ─────────────────────────────────────────────────────────────────────────────
step "Checking Python"

find_python() {
    for cmd in python3.13 python3.12 python3 python; do
        if command -v "$cmd" &>/dev/null; then
            _maj=$("$cmd" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo 0)
            _min=$("$cmd" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo 0)
            # Accept 3.12-3.13 only; 3.14+ has venv issues and jaclang doesn't support it yet
            if [ "$_maj" -eq 3 ] && [ "$_min" -ge 12 ] && [ "$_min" -le 13 ]; then
                echo "$cmd"; return 0
            elif [ "$_maj" -eq 3 ] && [ "$_min" -ge 14 ]; then
                warn "Python $_maj.$_min detected but 3.14+ is not yet supported. Will install 3.13."
            fi
        fi
    done
    return 1
}

PYTHON=$(find_python)

if [ -z "$PYTHON" ]; then
    info "Python 3.12-3.13 not found — installing Python 3.13..."
    if [ "$PLATFORM" = "mac" ]; then
        if command -v brew &>/dev/null; then
            brew install python@3.13 -q
            PYTHON=$(find_python)
        else
            warn "Homebrew not found. Install from https://brew.sh then re-run."
            fail "Python 3.13 required. Install from https://python.org/downloads/release/python-3130/"
        fi
    elif [ "$PLATFORM" = "linux" ]; then
        if command -v apt-get &>/dev/null; then
            info "Adding deadsnakes PPA and installing python3.13..."
            sudo apt-get update -qq
            sudo apt-get install -y software-properties-common -qq
            sudo add-apt-repository -y ppa:deadsnakes/ppa -q
            sudo apt-get update -qq
            sudo apt-get install -y python3.13 python3.13-venv python3.13-dev -qq
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y python3.13
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm python
        fi
        PYTHON=$(find_python)
    fi

    if [ -z "$PYTHON" ]; then
        fail "Could not install Python 3.13 automatically. Install from: https://python.org/downloads/release/python-3130/"
    fi
    ok "Python 3.13 installed"
fi

ok "Using ${W}$($PYTHON --version 2>&1)${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Clone / locate repo
# ─────────────────────────────────────────────────────────────────────────────
step "Locating source"

GRAPHCLAW_DIR="$HOME/.graphclaw"
WORKSPACE_DIR="$GRAPHCLAW_DIR/workspace"
CONFIG_FILE="$GRAPHCLAW_DIR/config.json"
VENV_DIR="$GRAPHCLAW_DIR/venv"
SOURCE_DIR="$GRAPHCLAW_DIR/source"
ENV_FILE="$GRAPHCLAW_DIR/.env"
UPDATE_STATE_DIR="$GRAPHCLAW_DIR/state"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

command -v git &>/dev/null || fail "git is required. Install git and retry."

if [ -d "$SOURCE_DIR/.git" ]; then
    ok "Using managed source at ${W}$SOURCE_DIR${NC}"
elif [ -n "$SCRIPT_DIR" ] && [ "$SCRIPT_DIR" != "/dev/fd" ] && [ -f "$SCRIPT_DIR/pyproject.toml" ] && [ -d "$SCRIPT_DIR/.git" ]; then
    info "Creating managed source copy..."
    rm -rf "$SOURCE_DIR"
    git clone --quiet --no-hardlinks "$SCRIPT_DIR" "$SOURCE_DIR"
    ok "Managed source created at ${W}$SOURCE_DIR${NC}"
else
    info "Running from pipe — cloning graphclaw..."
    rm -rf "$SOURCE_DIR"
    git clone --depth 1 https://github.com/zero-abd/graphclaw "$SOURCE_DIR" -q
    ok "Cloned managed source to ${W}$SOURCE_DIR${NC}"
fi

mkdir -p "$WORKSPACE_DIR/memory" \
         "$WORKSPACE_DIR/sessions" \
         "$WORKSPACE_DIR/skills/installed" \
         "$GRAPHCLAW_DIR/skills/installed" \
         "$UPDATE_STATE_DIR"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Create venv & install dependencies
# ─────────────────────────────────────────────────────────────────────────────
step "Installing dependencies"

info "Creating virtual environment at ${W}$VENV_DIR${NC}"
$PYTHON -m venv "$VENV_DIR"

# Activate venv — all pip/jac commands now go here
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
ok "Virtual environment created"

info "Upgrading pip..."
pip install --upgrade pip -q 2>/dev/null

info "Installing jaclang (Jac runtime)..."
pip install "jaclang>=0.13.5,<0.14" -q 2>/dev/null
ok "jaclang installed"

info "Installing graphclaw..."
pip install -e "${SOURCE_DIR}[channels]" -q 2>/dev/null
ok "graphclaw installed"

if command -v jac &>/dev/null; then
    ok "jac CLI ready — ${D}$(jac --version 2>&1 | head -1)${NC}"
else
    warn "jac not found — this shouldn't happen inside the venv"
fi

deactivate 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Deployment mode
# ─────────────────────────────────────────────────────────────────────────────
step "Deployment mode"

echo -e "  ${D}How will you run Graphclaw?${NC}"
echo ""
echo -e "    ${W}1)${NC} ${BOLD}Single-user${NC}   ${D}— personal agent, no auth  ${G}(best for most users)${NC}"
echo -e "    ${W}2)${NC} ${BOLD}Multi-user${NC}    ${D}— hosted server, JWT auth, per-user memory${NC}"
echo ""
ask_choice "Select mode [1/2]" "1 2" "1"
MODE_CHOICE="$REPLY"

if [ "$MODE_CHOICE" = "2" ]; then
    MULTI_USER=true
    ok "Multi-user mode selected"
    ask_optional "JWT secret key (blank = auto-generate)"
    JWT_SECRET="$REPLY"
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$("$PYTHON" -c "import secrets; print(secrets.token_hex(32))")
        warn "Generated JWT secret — save this: ${W}$JWT_SECRET${NC}"
    fi
else
    MULTI_USER=false
    JWT_SECRET=""
    ok "Single-user mode selected"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — LLM provider & channels
# ─────────────────────────────────────────────────────────────────────────────
step "LLM provider & channels"

echo -e "  ${D}Choose your default LLM provider:${NC}"
echo ""
echo -e "    ${W}1)${NC} ${BOLD}OpenRouter${NC}   ${D}— one key, route models like Claude through OpenRouter  ${G}(recommended)${NC}"
echo -e "    ${W}2)${NC} ${BOLD}Anthropic${NC}    ${D}— Claude direct${NC}"
echo -e "    ${W}3)${NC} ${BOLD}OpenAI${NC}       ${D}— GPT-4o / GPT-4.1${NC}"
echo -e "    ${W}4)${NC} ${BOLD}Ollama${NC}       ${D}— local models, no API key needed${NC}"
echo -e "    ${W}5)${NC} ${BOLD}Skip${NC}         ${D}— configure manually later${NC}"
echo ""
ask_choice "Select provider [1-5]" "1 2 3 4 5" "1"
PROVIDER_CHOICE="$REPLY"

OPENROUTER_KEY=""; ANTHROPIC_KEY=""; OPENAI_KEY=""
DEFAULT_MODEL="openrouter/anthropic/claude-sonnet-4-6"
PROVIDER_NAME="OpenRouter"

case "$PROVIDER_CHOICE" in
    1)
        hint "OpenRouter key only — you do NOT need an Anthropic key for the default Claude-via-OpenRouter model"
        hint "Get your key at: https://openrouter.ai/keys"
        ask_optional "Paste OpenRouter API key now"
        OPENROUTER_KEY="$REPLY"
        if [ -n "$OPENROUTER_KEY" ]; then
            ok "OpenRouter configured"
        else
            hint "Set it later with an environment variable instead:"
            hint "macOS / Linux: export OPENROUTER_API_KEY='your-key'"
            hint "Windows PowerShell: $env:OPENROUTER_API_KEY='your-key'"
            warn "No OpenRouter key saved yet — Graphclaw will prompt again in the CLI if it needs one"
        fi
        ;;
    2)
        hint "Get your key at: https://console.anthropic.com/settings/keys"
        ask_optional "Paste Anthropic API key now"
        ANTHROPIC_KEY="$REPLY"
        DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
        PROVIDER_NAME="Anthropic"
        if [ -n "$ANTHROPIC_KEY" ]; then
            ok "Anthropic configured"
        else
            hint "Set it later with an environment variable instead:"
            hint "macOS / Linux: export ANTHROPIC_API_KEY='your-key'"
            hint "Windows PowerShell: $env:ANTHROPIC_API_KEY='your-key'"
            warn "No Anthropic key saved yet — Graphclaw will prompt again in the CLI if it needs one"
        fi
        ;;
    3)
        hint "Get your key at: https://platform.openai.com/api-keys"
        ask_optional "Paste OpenAI API key now"
        OPENAI_KEY="$REPLY"
        DEFAULT_MODEL="openai/gpt-4o"
        PROVIDER_NAME="OpenAI"
        if [ -n "$OPENAI_KEY" ]; then
            ok "OpenAI configured"
        else
            hint "Set it later with an environment variable instead:"
            hint "macOS / Linux: export OPENAI_API_KEY='your-key'"
            hint "Windows PowerShell: $env:OPENAI_API_KEY='your-key'"
            warn "No OpenAI key saved yet — Graphclaw will prompt again in the CLI if it needs one"
        fi
        ;;
    4)
        DEFAULT_MODEL="ollama/llama3"
        PROVIDER_NAME="Ollama"
        ok "Ollama selected — make sure 'ollama serve' is running"
        ;;
    5)
        ok "Skipped — edit ${W}~/.graphclaw/config.json${NC} to add your key later"
        PROVIDER_NAME="(not set)"
        ;;
esac

echo ""
echo -e "  ${D}Pick the first chat interface you want to set up:${NC}"
echo -e "  ${D}You can add more later by re-running install.sh or editing ~/.graphclaw/config.json.${NC}"
echo ""
echo -e "    ${W}1)${NC} ${BOLD}Telegram${NC}   ${D}— easiest for personal use${NC}"
echo -e "    ${W}2)${NC} ${BOLD}Discord${NC}    ${D}— best for servers / communities${NC}"
echo -e "    ${W}3)${NC} ${BOLD}Slack${NC}      ${D}— best for internal teams${NC}"
echo -e "    ${W}4)${NC} ${BOLD}Skip for now${NC} ${D}— configure later${NC}"
echo ""
ask_choice "Select first chat interface [1-4]" "1 2 3 4" "1"
CHANNEL_CHOICE="$REPLY"

TG_TOKEN=""; TG_USERNAME=""; DC_TOKEN=""; SL_BOT_TOKEN=""; SL_APP_TOKEN=""

resolve_telegram_bot_username() {
    local token="$1"
    [ -z "$token" ] && return 0
    "$PYTHON" - "$token" <<'PY'
import json
import sys
import urllib.request

token = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if not token:
    raise SystemExit(0)
try:
    with urllib.request.urlopen(f"https://api.telegram.org/bot{token}/getMe", timeout=10) as resp:
        payload = json.load(resp)
except Exception:
    raise SystemExit(0)
result = payload.get("result") or {}
username = str(result.get("username") or "").strip().lstrip("@")
if username:
    print(username)
PY
}

configure_telegram() {
    echo ""
    echo -e "  ${W}Telegram setup walkthrough${NC}"
    hint "Open BotFather: https://t.me/BotFather"
    hint "1. Send /newbot"
    hint "2. Choose a display name for your bot"
    hint "3. Choose a unique username ending in 'bot'"
    hint "4. Copy the token BotFather gives you"
    hint "5. Start a chat with your bot so it can message you back"
    ask_optional "Paste Telegram bot token"
    TG_TOKEN="$REPLY"
    if [ -n "$TG_TOKEN" ]; then
        ok "Telegram configured"
        TG_USERNAME="$(resolve_telegram_bot_username "$TG_TOKEN")"
        if [ -n "$TG_USERNAME" ]; then
            hint "Client onboarding link: https://t.me/$TG_USERNAME"
            hint "Tell the client to open that link, press Start, then send any message."
        else
            hint "Next step: open your bot in Telegram, press Start, then send any message."
        fi
        hint "If Telegram replies with a pairing code, approve it locally with:"
        hint "  pairing list telegram"
        hint "  pairing approve telegram <code>"
    fi
}

configure_discord() {
    echo ""
    echo -e "  ${W}Discord setup walkthrough${NC}"
    hint "Open Discord Developer Portal: https://discord.com/developers/applications"
    hint "1. Click New Application"
    hint "2. Open the Bot tab and click Add Bot"
    hint "3. Reset / copy the bot token"
    hint "4. In Bot settings, enable Message Content Intent"
    hint "5. In OAuth2 → URL Generator, select 'bot' scope and invite the bot to your server"
    ask_optional "Paste Discord bot token"
    DC_TOKEN="$REPLY"
    if [ -n "$DC_TOKEN" ]; then ok "Discord configured"; fi
}

configure_slack() {
    echo ""
    echo -e "  ${W}Slack setup walkthrough${NC}"
    hint "Open Slack app builder: https://api.slack.com/apps"
    hint "1. Click Create New App"
    hint "2. Add a bot user under App Home"
    hint "3. In OAuth & Permissions, install the app and copy the Bot User OAuth Token (xoxb-...)"
    hint "4. Enable Socket Mode"
    hint "5. In Basic Information → App-Level Tokens, create a token with connections:write (xapp-...)"
    hint "6. Invite the bot to the channel you want to use"
    ask_optional "Paste Slack bot token (xoxb-...)"
    SL_BOT_TOKEN="$REPLY"
    if [ -n "$SL_BOT_TOKEN" ]; then
        ask_required "Paste Slack app token (xapp-...)"
        SL_APP_TOKEN="$REPLY"
        ok "Slack configured"
    fi
}

case "$CHANNEL_CHOICE" in
    1) configure_telegram ;;
    2) configure_discord ;;
    3) configure_slack ;;
    4) ok "Skipped messaging channels for now — add one later in ~/.graphclaw/config.json or by re-running install.sh" ;;
esac

echo ""
echo -e "  ${D}Dev tool integrations:${NC}"
echo ""
hint "Base44 uses the official Base44 CLI flow. On first use, Graphclaw can call `base44` (or `npx --yes base44@latest`) and you may be prompted to log in."
hint "Loveable uses official Build with URL links, so no API key is required for the fast website-generation flow."
hint "If you want screenshot progress updates, Graphclaw will install a Playwright Chromium browser runtime on first use."
BASE44_KEY=""
LOVEABLE_KEY=""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Write config & shell integration
# ─────────────────────────────────────────────────────────────────────────────
step "Writing config & shell integration"

DEFAULT_PROVIDER_KEY="openrouter"
case "$PROVIDER_CHOICE" in
    2) DEFAULT_PROVIDER_KEY="anthropic" ;;
    3) DEFAULT_PROVIDER_KEY="openai" ;;
    4) DEFAULT_PROVIDER_KEY="ollama" ;;
esac

CONFIG_FILE="$CONFIG_FILE" \
WORKSPACE_DIR="$WORKSPACE_DIR" \
DEFAULT_MODEL="$DEFAULT_MODEL" \
DEFAULT_PROVIDER_KEY="$DEFAULT_PROVIDER_KEY" \
MULTI_USER="$MULTI_USER" \
JWT_SECRET="$JWT_SECRET" \
OPENROUTER_KEY="$OPENROUTER_KEY" \
ANTHROPIC_KEY="$ANTHROPIC_KEY" \
OPENAI_KEY="$OPENAI_KEY" \
TG_TOKEN="$TG_TOKEN" \
DC_TOKEN="$DC_TOKEN" \
SL_BOT_TOKEN="$SL_BOT_TOKEN" \
SL_APP_TOKEN="$SL_APP_TOKEN" \
INSTALLED_SKILLS_PATH="$GRAPHCLAW_DIR/skills/installed" \
"$PYTHON" - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ["CONFIG_FILE"])
existing = {}
if config_path.exists():
    try:
        existing = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception:
        existing = {}
if not isinstance(existing, dict):
    existing = {}

cfg = existing
cfg["workspace"] = cfg.get("workspace") or os.environ["WORKSPACE_DIR"]
cfg["multi_user"] = os.environ["MULTI_USER"].lower() == "true"

agents = cfg.setdefault("agents", {})
agents["model"] = os.environ["DEFAULT_MODEL"]
agents.setdefault("max_tokens", 8192)
agents.setdefault("temperature", 0.7)
agents.setdefault("max_tool_iterations", 200)
dream = agents.setdefault("dream", {})
dream.setdefault("enabled", True)
dream.setdefault("interval_hours", 2)

providers = cfg.setdefault("providers", {})
providers["default_provider"] = os.environ["DEFAULT_PROVIDER_KEY"]
providers.setdefault("openrouter", {"base_url": "https://openrouter.ai/api/v1"})
providers.setdefault("anthropic", {})
providers.setdefault("openai", {})
providers.setdefault("ollama", {"base_url": "http://localhost:11434"})
if os.environ["OPENROUTER_KEY"]:
    providers["openrouter"]["api_key"] = os.environ["OPENROUTER_KEY"]
providers["openrouter"].setdefault("base_url", "https://openrouter.ai/api/v1")
if os.environ["ANTHROPIC_KEY"]:
    providers["anthropic"]["api_key"] = os.environ["ANTHROPIC_KEY"]
if os.environ["OPENAI_KEY"]:
    providers["openai"]["api_key"] = os.environ["OPENAI_KEY"]

channels = cfg.setdefault("channels", {})
channels.setdefault("telegram", {"enabled": False, "bot_token": "", "allowed_ids": []})
channels.setdefault("discord", {"enabled": False, "bot_token": "", "allowed_ids": []})
channels.setdefault("slack", {"enabled": False, "bot_token": "", "app_token": "", "allowed_ids": []})
channels.setdefault("email", {"enabled": False})
channels.setdefault("whatsapp", {"enabled": False})
if os.environ["TG_TOKEN"]:
    channels["telegram"]["enabled"] = True
    channels["telegram"]["bot_token"] = os.environ["TG_TOKEN"]
if os.environ["DC_TOKEN"]:
    channels["discord"]["enabled"] = True
    channels["discord"]["bot_token"] = os.environ["DC_TOKEN"]
if os.environ["SL_BOT_TOKEN"]:
    channels["slack"]["enabled"] = True
    channels["slack"]["bot_token"] = os.environ["SL_BOT_TOKEN"]
if os.environ["SL_APP_TOKEN"]:
    channels["slack"]["app_token"] = os.environ["SL_APP_TOKEN"]

auth = cfg.setdefault("auth", {})
auth["enabled"] = os.environ["MULTI_USER"].lower() == "true"
if os.environ["JWT_SECRET"]:
    auth["secret_key"] = os.environ["JWT_SECRET"]
else:
    auth.setdefault("secret_key", "")

skills = cfg.setdefault("skills", {})
skills.setdefault("registry_url", "https://clawhub.ai/api/v1")
skills["installed_path"] = os.environ["INSTALLED_SKILLS_PATH"]

config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
PY
ok "Config written to ${W}$CONFIG_FILE${NC}"

ENV_FILE="$ENV_FILE" \
CONFIG_FILE="$CONFIG_FILE" \
GRAPHCLAW_HOME="$GRAPHCLAW_DIR" \
OPENROUTER_KEY="$OPENROUTER_KEY" \
ANTHROPIC_KEY="$ANTHROPIC_KEY" \
OPENAI_KEY="$OPENAI_KEY" \
"$PYTHON" - <<'PY'
import os
from pathlib import Path

env_path = Path(os.environ["ENV_FILE"])
existing = {}
if env_path.exists():
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        if not raw or raw.lstrip().startswith("#") or "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        existing[key] = value

updates = {
    "GRAPHCLAW_CONFIG_PATH": os.environ["CONFIG_FILE"],
    "GRAPHCLAW_HOME": os.environ["GRAPHCLAW_HOME"],
    "OPENROUTER_API_KEY": os.environ["OPENROUTER_KEY"],
    "ANTHROPIC_API_KEY": os.environ["ANTHROPIC_KEY"],
    "OPENAI_API_KEY": os.environ["OPENAI_KEY"],
}
for key, value in updates.items():
    if value:
        existing[key] = value
    elif key not in existing and key in {"GRAPHCLAW_CONFIG_PATH", "GRAPHCLAW_HOME"}:
        existing[key] = value

lines = ["# Graphclaw environment"]
for key in [
    "GRAPHCLAW_CONFIG_PATH",
    "GRAPHCLAW_HOME",
    "OPENROUTER_API_KEY",
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
]:
    value = existing.get(key, "")
    if value:
        lines.append(f"{key}={value}")
env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
ok ".env written"

cat > "$GRAPHCLAW_DIR/run.sh" << RUNEOF
#!/usr/bin/env bash
set -e
source "$VENV_DIR/bin/activate"
export GRAPHCLAW_CONFIG_PATH="$CONFIG_FILE"
export GRAPHCLAW_HOME="$GRAPHCLAW_DIR"
case "\${1:-}" in
  update)
    shift
    exec "$VENV_DIR/bin/python" -m graphclaw.update_manager update "\$@"
    ;;
  rollback)
    shift
    exec "$VENV_DIR/bin/python" -m graphclaw.update_manager rollback "\$@"
    ;;
  status)
    shift
    exec "$VENV_DIR/bin/python" -m graphclaw.update_manager status "\$@"
    ;;
esac
exec jac run --no-autonative "$SOURCE_DIR/graphclaw/main.jac" "\$@"
RUNEOF
chmod +x "$GRAPHCLAW_DIR/run.sh"
ok "Startup script: ${W}~/.graphclaw/run.sh${NC}"

cat > "$GRAPHCLAW_DIR/update.sh" << UPDATEEOF
#!/usr/bin/env bash
set -e
source "$VENV_DIR/bin/activate"
export GRAPHCLAW_CONFIG_PATH="$CONFIG_FILE"
export GRAPHCLAW_HOME="$GRAPHCLAW_DIR"
exec "$VENV_DIR/bin/python" -m graphclaw.update_manager update "\$@"
UPDATEEOF
chmod +x "$GRAPHCLAW_DIR/update.sh"

cat > "$GRAPHCLAW_DIR/rollback.sh" << ROLLBACKEOF
#!/usr/bin/env bash
set -e
source "$VENV_DIR/bin/activate"
export GRAPHCLAW_CONFIG_PATH="$CONFIG_FILE"
export GRAPHCLAW_HOME="$GRAPHCLAW_DIR"
exec "$VENV_DIR/bin/python" -m graphclaw.update_manager rollback "\$@"
ROLLBACKEOF
chmod +x "$GRAPHCLAW_DIR/rollback.sh"

# Shell alias
SHELL_RC=""
if   [ -f "$HOME/.zshrc"  ]; then SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.bash_profile" ]; then SHELL_RC="$HOME/.bash_profile"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q "alias graphclaw=" "$SHELL_RC" 2>/dev/null; then
        { echo ""; echo "alias graphclaw='$GRAPHCLAW_DIR/run.sh'"; } >> "$SHELL_RC"
        ok "Added ${W}graphclaw${NC} alias to ${W}$SHELL_RC${NC}"
    else
        ok "Alias ${W}graphclaw${NC} already in $SHELL_RC"
    fi
fi

FISH_RC="$HOME/.config/fish/config.fish"
if [ -f "$FISH_RC" ]; then
    if ! grep -q "alias graphclaw" "$FISH_RC" 2>/dev/null; then
        echo "alias graphclaw '$GRAPHCLAW_DIR/run.sh'" >> "$FISH_RC"
        ok "Added alias to Fish config"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${G}${BOLD}"
cat << 'DONE'
  +===========================================================+
  |                                                           |
  |   [OK]  Graphclaw installed successfully!                 |
  |                                                           |
  +===========================================================+
DONE
echo -e "${NC}"

echo -e "  ${BOLD}${W}Configuration${NC}"
echo -e "  ${D}──────────────────────────────────────────${NC}"
printf   "  %-12s %s\n" "Mode:"      "$([ "$MULTI_USER" = "true" ] && echo 'Multi-user (JWT auth)' || echo 'Single-user')"
printf   "  %-12s %s\n" "Provider:"  "$PROVIDER_NAME"
printf   "  %-12s %s\n" "Model:"     "$DEFAULT_MODEL"
printf   "  %-12s %s\n" "Config:"    "$CONFIG_FILE"
printf   "  %-12s %s\n" "Venv:"      "$VENV_DIR"
echo ""

echo -e "  ${BOLD}${W}Next steps${NC}"
echo -e "  ${D}──────────────────────────────────────────${NC}"
if [ -n "$SHELL_RC" ]; then
    echo -e "  ${Y}1. Reload your shell (required once):${NC}"
    echo -e "       ${W}source $SHELL_RC${NC}"
    echo ""
fi
echo -e "  ${W}2. Start graphclaw:${NC}"
echo -e "       ${W}graphclaw${NC}"
echo ""
echo -e "  ${D}Later, manage updates safely with:${NC}"
echo -e "       ${W}graphclaw update${NC}"
echo -e "       ${W}graphclaw rollback${NC}"
echo ""
if [ -n "$TG_USERNAME" ]; then
    echo -e "  ${BOLD}${W}Send this to your client${NC}"
    echo -e "  ${D}──────────────────────────────────────────${NC}"
    echo -e "  ${W}Open https://t.me/$TG_USERNAME, press Start, then send me any message.${NC}"
    echo -e "  ${D}If Telegram replies with a pairing code, approve it in this terminal with:${NC}"
    echo -e "       ${W}pairing list telegram${NC}"
    echo -e "       ${W}pairing approve telegram <code>${NC}"
    echo ""
fi
