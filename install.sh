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
    echo -ne "  ${C}?${NC} ${BOLD}$1${NC} ${D}(optional, Enter to skip)${NC}: "
    read -r REPLY
}
ask_required() {
    while true; do
        echo -ne "  ${C}?${NC} ${BOLD}$1${NC}: "
        read -r REPLY
        [ -n "$REPLY" ] && return
        echo -e "  ${R}  Required — please enter a value.${NC}"
    done
}
ask_choice() {
    local prompt="$1" valid="$2" default="$3"
    while true; do
        echo -ne "  ${C}?${NC} ${BOLD}$prompt${NC} ${D}[default: ${default}]${NC}: "
        read -r REPLY
        REPLY="${REPLY:-$default}"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "/dev/fd" ] || [ ! -f "$SCRIPT_DIR/pyproject.toml" ]; then
    CLONE_DIR="$(mktemp -d)/graphclaw"
    info "Running from pipe — cloning graphclaw..."
    command -v git &>/dev/null || fail "git is required. Install git and retry."
    git clone --depth 1 https://github.com/zero-abd/graphclaw "$CLONE_DIR" -q
    ok "Cloned to ${W}$CLONE_DIR${NC}"
    SCRIPT_DIR="$CLONE_DIR"
else
    ok "Using source at ${W}$SCRIPT_DIR${NC}"
fi

GRAPHCLAW_DIR="$HOME/.graphclaw"
WORKSPACE_DIR="$GRAPHCLAW_DIR/workspace"
CONFIG_FILE="$GRAPHCLAW_DIR/config.json"
VENV_DIR="$GRAPHCLAW_DIR/venv"

mkdir -p "$WORKSPACE_DIR/memory" \
         "$WORKSPACE_DIR/sessions" \
         "$WORKSPACE_DIR/skills/installed" \
         "$GRAPHCLAW_DIR/skills/installed"

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
pip install -e "$SCRIPT_DIR" -q 2>/dev/null
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
echo -e "    ${W}1)${NC} ${BOLD}OpenRouter${NC}   ${D}— one key, access to all major models  ${G}(recommended)${NC}"
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
        hint "Get your key at: openrouter.ai/keys"
        ask_required "OpenRouter API key"
        OPENROUTER_KEY="$REPLY"
        ok "OpenRouter configured"
        ;;
    2)
        hint "Get your key at: console.anthropic.com/settings/keys"
        ask_required "Anthropic API key"
        ANTHROPIC_KEY="$REPLY"
        DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
        PROVIDER_NAME="Anthropic"
        ok "Anthropic configured"
        ;;
    3)
        hint "Get your key at: platform.openai.com/api-keys"
        ask_required "OpenAI API key"
        OPENAI_KEY="$REPLY"
        DEFAULT_MODEL="openai/gpt-4o"
        PROVIDER_NAME="OpenAI"
        ok "OpenAI configured"
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
echo -e "  ${D}Messaging channels — all optional, press Enter to skip:${NC}"
echo ""
hint "Telegram: open Telegram, message @BotFather, send /newbot"
ask_optional "Telegram bot token"
TG_TOKEN="$REPLY"
hint "Discord: discord.com/developers/applications → New App → Bot → Reset Token"
ask_optional "Discord bot token"
DC_TOKEN="$REPLY"
hint "Slack: api.slack.com/apps → Create App → OAuth & Permissions → Bot Token"
ask_optional "Slack bot token (xoxb-...)"
SL_BOT_TOKEN="$REPLY"
SL_APP_TOKEN=""
if [ -n "$SL_BOT_TOKEN" ]; then
    hint "Slack app token: api.slack.com/apps → Basic Information → App-Level Tokens"
    ask_required "Slack app token (xapp-...)"
    SL_APP_TOKEN="$REPLY"
fi

echo ""
echo -e "  ${D}DevOps skill API keys — all optional, press Enter to skip:${NC}"
echo ""
hint "Base44: app.base44.com/settings → API Keys"
ask_optional "Base44 API key"
BASE44_KEY="$REPLY"
hint "Loveable: lovable.dev/settings → API"
ask_optional "Loveable API key"
LOVEABLE_KEY="$REPLY"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Write config & shell integration
# ─────────────────────────────────────────────────────────────────────────────
step "Writing config & shell integration"

cat > "$CONFIG_FILE" << EOF
{
  "workspace": "$WORKSPACE_DIR",
  "multi_user": $MULTI_USER,
  "agents": {
    "model": "$DEFAULT_MODEL",
    "max_tokens": 8192,
    "temperature": 0.7,
    "max_tool_iterations": 200,
    "dream": { "enabled": true, "interval_hours": 2 }
  },
  "providers": {
    "default_provider": "openrouter",
    "openrouter": { "api_key": "$OPENROUTER_KEY", "base_url": "https://openrouter.ai/api/v1" },
    "anthropic":  { "api_key": "$ANTHROPIC_KEY" },
    "openai":     { "api_key": "$OPENAI_KEY" }
  },
  "channels": {
    "telegram": { "enabled": $([ -n "$TG_TOKEN" ] && echo "true" || echo "false"), "bot_token": "$TG_TOKEN" },
    "discord":  { "enabled": $([ -n "$DC_TOKEN" ] && echo "true" || echo "false"), "bot_token": "$DC_TOKEN" },
    "slack":    { "enabled": $([ -n "$SL_BOT_TOKEN" ] && echo "true" || echo "false"), "bot_token": "$SL_BOT_TOKEN", "app_token": "$SL_APP_TOKEN" },
    "email":    { "enabled": false },
    "whatsapp": { "enabled": false }
  },
  "auth": { "enabled": $MULTI_USER, "secret_key": "$JWT_SECRET" },
  "skills": {
    "registry_url": "https://clawhub.ai/api/v1",
    "installed_path": "$GRAPHCLAW_DIR/skills/installed"
  }
}
EOF
ok "Config written to ${W}$CONFIG_FILE${NC}"

# .env
ENV_FILE="$GRAPHCLAW_DIR/.env"
{
    echo "# Graphclaw environment"
    echo "GRAPHCLAW_CONFIG_PATH=$CONFIG_FILE"
    [ -n "$OPENROUTER_KEY" ] && echo "OPENROUTER_API_KEY=$OPENROUTER_KEY"
    [ -n "$ANTHROPIC_KEY"  ] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_KEY"
    [ -n "$OPENAI_KEY"     ] && echo "OPENAI_API_KEY=$OPENAI_KEY"
    [ -n "$BASE44_KEY"     ] && echo "BASE44_API_KEY=$BASE44_KEY"
    [ -n "$LOVEABLE_KEY"   ] && echo "LOVEABLE_API_KEY=$LOVEABLE_KEY"
} > "$ENV_FILE"
ok ".env written"

# run.sh — activates venv, sets config, runs jac
cat > "$GRAPHCLAW_DIR/run.sh" << RUNEOF
#!/usr/bin/env bash
source "$VENV_DIR/bin/activate"
export GRAPHCLAW_CONFIG_PATH="$CONFIG_FILE"
exec jac run --no-autonative "$SCRIPT_DIR/graphclaw/main.jac" "\$@"
RUNEOF
chmod +x "$GRAPHCLAW_DIR/run.sh"
ok "Startup script: ${W}~/.graphclaw/run.sh${NC}"

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
echo -e "  ${D}Or run directly without reloading:${NC}"
echo -e "       ${W}~/.graphclaw/run.sh${NC}"
echo ""
