#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Graphclaw Installer
#  Usage (one-liner):
#    curl -fsSL https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.sh | bash
#  Or locally:
#    bash install.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m'   # red
G='\033[0;32m'   # green
Y='\033[1;33m'   # yellow
C='\033[0;36m'   # cyan
B='\033[0;34m'   # blue
M='\033[0;35m'   # magenta
W='\033[1;37m'   # white bold
D='\033[2m'      # dim
NC='\033[0m'     # reset
BOLD='\033[1m'
CHECK="${G}✓${NC}"
CROSS="${R}✗${NC}"
ARROW="${C}→${NC}"

# ── Helpers ───────────────────────────────────────────────────────────────────

step_n=0
total_steps=6

step() {
    step_n=$((step_n + 1))
    echo ""
    echo -e "${BOLD}${W}  [$step_n/$total_steps] $1${NC}"
    echo -e "  ${D}$(printf '%.0s─' {1..60})${NC}"
}

ok()   { echo -e "  ${CHECK} $1"; }
warn() { echo -e "  ${Y}⚠${NC}  $1"; }
fail() { echo -e "  ${CROSS} $1"; exit 1; }
info() { echo -e "  ${D}$1${NC}"; }

ask() {
    # ask <prompt> <default>
    local prompt="$1" default="${2:-}"
    if [ -n "$default" ]; then
        echo -ne "  ${C}?${NC} ${BOLD}$prompt${NC} ${D}[${default}]${NC}: "
    else
        echo -ne "  ${C}?${NC} ${BOLD}$prompt${NC}: "
    fi
    read -r REPLY
    REPLY="${REPLY:-$default}"
}

spinner() {
    local pid=$1 msg="${2:-Working...}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${C}${frames[$((i % ${#frames[@]}))]}${NC}  %s " "$msg"
        i=$((i + 1))
        sleep 0.08
    done
    printf "\r  %*s\r" $((${#msg} + 8)) ""
}

# ── Banner ────────────────────────────────────────────────────────────────────

clear 2>/dev/null || true
echo ""
echo -e "${C}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║                                                           ║"
echo "  ║    ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗              ║"
echo "  ║   ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║              ║"
echo "  ║   ██║  ███╗██████╔╝███████║██████╔╝███████║              ║"
echo "  ║   ██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║              ║"
echo "  ║   ╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║              ║"
echo "  ║    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝  ${D}v0.1.0${C}${BOLD}     ║"
echo "  ║                                                           ║"
echo "  ║   ${D}Graph-native multi-agent AI platform in Jac${C}${BOLD}            ║"
echo "  ║                                                           ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ── Detect OS ────────────────────────────────────────────────────────────────

OS="$(uname -s 2>/dev/null || echo "unknown")"
case "$OS" in
    Linux*)   PLATFORM="linux" ;;
    Darwin*)  PLATFORM="mac" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows-bash" ;;
    *)        PLATFORM="unknown" ;;
esac

if [ "$PLATFORM" = "windows-bash" ]; then
    echo -e "  ${Y}⚠  Detected Windows (Git Bash / MSYS2)${NC}"
    echo -e "  ${D}For a native Windows experience, use PowerShell instead:${NC}"
    echo ""
    echo -e "  ${W}  irm https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.ps1 | iex${NC}"
    echo ""
    echo -e "  Continuing with bash installer...\n"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Python
# ─────────────────────────────────────────────────────────────────────────────

step "Checking Python"

PYTHON=""
for cmd in python3.13 python3.12 python3 python; do
    if command -v "$cmd" &>/dev/null; then
        _maj=$("$cmd" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo 0)
        _min=$("$cmd" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo 0)
        if [ "$_maj" -ge 3 ] && [ "$_min" -ge 12 ]; then
            PYTHON="$cmd"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo ""
    echo -e "  ${CROSS} ${BOLD}Python 3.12+ not found${NC}"
    echo ""
    echo -e "  Install it from one of:"
    echo -e "  ${ARROW} ${W}https://python.org/downloads${NC}"
    if [ "$PLATFORM" = "mac" ]; then
        echo -e "  ${ARROW} ${W}brew install python@3.13${NC}"
    elif [ "$PLATFORM" = "linux" ]; then
        echo -e "  ${ARROW} ${W}sudo apt install python3.12${NC}  (Debian/Ubuntu)"
        echo -e "  ${ARROW} ${W}sudo dnf install python3.12${NC}  (Fedora/RHEL)"
    fi
    echo ""
    exit 1
fi

PY_VER=$("$PYTHON" --version 2>&1)
ok "Using ${W}$PY_VER${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Clone / locate repo
# ─────────────────────────────────────────────────────────────────────────────

step "Locating source"

# If piped via curl, BASH_SOURCE[0] will be /dev/stdin — need to clone
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
INSTALL_FROM_PIPE=false

if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "/dev/fd" ] || [ ! -f "$SCRIPT_DIR/pyproject.toml" ]; then
    INSTALL_FROM_PIPE=true
    CLONE_DIR="$(mktemp -d)/graphclaw"
    info "Running from pipe — cloning graphclaw..."

    if command -v git &>/dev/null; then
        (git clone --depth 1 https://github.com/zero-abd/graphclaw "$CLONE_DIR" -q) &
        spinner $! "Cloning repository"
        wait $!
        ok "Cloned to ${W}$CLONE_DIR${NC}"
        SCRIPT_DIR="$CLONE_DIR"
    else
        fail "git is required. Install git and retry."
    fi
else
    ok "Using source at ${W}$SCRIPT_DIR${NC}"
fi

GRAPHCLAW_DIR="$HOME/.graphclaw"
WORKSPACE_DIR="$GRAPHCLAW_DIR/workspace"
CONFIG_FILE="$GRAPHCLAW_DIR/config.json"

mkdir -p "$WORKSPACE_DIR/memory" \
         "$WORKSPACE_DIR/sessions" \
         "$WORKSPACE_DIR/skills/installed" \
         "$GRAPHCLAW_DIR/skills/installed"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Install dependencies
# ─────────────────────────────────────────────────────────────────────────────

step "Installing dependencies"

# Prefer uv if available (much faster)
if command -v uv &>/dev/null; then
    info "Using uv for fast installation..."
    (uv pip install jaclang -q 2>/dev/null || true) &
    spinner $! "Installing jaclang"
    wait $! || true
    (uv pip install -e "$SCRIPT_DIR" -q 2>/dev/null || "$PYTHON" -m pip install -e "$SCRIPT_DIR" -q) &
    spinner $! "Installing graphclaw"
    wait $!
else
    ($PYTHON -m pip install --upgrade pip -q) &
    spinner $! "Upgrading pip"
    wait $!

    ($PYTHON -m pip install "jaclang>=0.7.0" -q) &
    spinner $! "Installing jaclang (the Jac runtime)"
    wait $!

    ($PYTHON -m pip install -e "$SCRIPT_DIR" -q) &
    spinner $! "Installing graphclaw"
    wait $!
fi

# Verify jac CLI
if command -v jac &>/dev/null; then
    JAC_VER=$(jac --version 2>&1 | head -1 || echo "unknown")
    ok "jac CLI ready  ${D}($JAC_VER)${NC}"
else
    warn "jac command not found in PATH — you may need to reload your shell"
fi
ok "graphclaw package installed"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Deployment mode
# ─────────────────────────────────────────────────────────────────────────────

step "Deployment mode"

echo -e "  ${D}How will you run Graphclaw?${NC}"
echo ""
echo -e "    ${W}1)${NC} ${BOLD}Single-user${NC}   ${D}— personal agent, no auth required${NC}"
echo -e "    ${W}2)${NC} ${BOLD}Multi-user${NC}    ${D}— hosted platform, JWT auth, per-user memory graphs${NC}"
echo ""
ask "Select mode [1/2]" "1"
MODE_CHOICE="$REPLY"

if [ "$MODE_CHOICE" = "2" ]; then
    MULTI_USER=true
    ok "Multi-user mode selected"
    ask "Secret key for JWT (leave blank to auto-generate)" ""
    JWT_SECRET="$REPLY"
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$("$PYTHON" -c "import secrets; print(secrets.token_hex(32))")
        warn "Generated JWT secret (save this!):  ${W}$JWT_SECRET${NC}"
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
echo -e "    ${W}1)${NC} ${BOLD}OpenRouter${NC}   ${D}— one key, access to every major model  ${G}(recommended)${NC}"
echo -e "    ${W}2)${NC} ${BOLD}Anthropic${NC}    ${D}— Claude direct${NC}"
echo -e "    ${W}3)${NC} ${BOLD}OpenAI${NC}       ${D}— GPT-4o / GPT-4.1${NC}"
echo -e "    ${W}4)${NC} ${BOLD}Ollama${NC}       ${D}— local models, no API key needed${NC}"
echo -e "    ${W}5)${NC} ${BOLD}Skip${NC}         ${D}— configure manually later${NC}"
echo ""
ask "Select provider [1-5]" "1"
PROVIDER_CHOICE="$REPLY"

OPENROUTER_KEY=""; ANTHROPIC_KEY=""; OPENAI_KEY=""
DEFAULT_MODEL="openrouter/anthropic/claude-sonnet-4-6"
PROVIDER_NAME="OpenRouter"

case "$PROVIDER_CHOICE" in
    1)
        ask "OpenRouter API key" ""
        OPENROUTER_KEY="$REPLY"
        ok "OpenRouter configured"
        ;;
    2)
        ask "Anthropic API key" ""
        ANTHROPIC_KEY="$REPLY"
        DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
        PROVIDER_NAME="Anthropic"
        ok "Anthropic configured"
        ;;
    3)
        ask "OpenAI API key" ""
        OPENAI_KEY="$REPLY"
        DEFAULT_MODEL="openai/gpt-4o"
        PROVIDER_NAME="OpenAI"
        ok "OpenAI configured"
        ;;
    4)
        DEFAULT_MODEL="ollama/llama3"
        PROVIDER_NAME="Ollama"
        ok "Ollama selected — make sure ollama is running locally"
        ;;
    5)
        ok "Skipped — edit ${W}~/.graphclaw/config.json${NC} to set your key"
        PROVIDER_NAME="(not set)"
        ;;
esac

echo ""
echo -e "  ${D}Messaging channels — press Enter to skip any:${NC}"
echo ""
ask "Telegram bot token" ""
TG_TOKEN="$REPLY"
ask "Discord bot token " ""
DC_TOKEN="$REPLY"
ask "Slack bot token   " ""
SL_BOT_TOKEN="$REPLY"
ask "Slack app token   " ""
SL_APP_TOKEN="$REPLY"

echo ""
echo -e "  ${D}DevOps skill API keys — press Enter to skip:${NC}"
echo ""
ask "Base44 API key  " ""
BASE44_KEY="$REPLY"
ask "Loveable API key" ""
LOVEABLE_KEY="$REPLY"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Write config & shell integration
# ─────────────────────────────────────────────────────────────────────────────

step "Writing config & shell integration"

# config.json
cat > "$CONFIG_FILE" << EOF
{
  "workspace": "$WORKSPACE_DIR",
  "multi_user": $MULTI_USER,
  "agents": {
    "model": "$DEFAULT_MODEL",
    "max_tokens": 8192,
    "temperature": 0.7,
    "max_tool_iterations": 200,
    "dream": {
      "enabled": true,
      "interval_hours": 2
    }
  },
  "providers": {
    "default_provider": "openrouter",
    "openrouter": {
      "api_key": "$OPENROUTER_KEY",
      "base_url": "https://openrouter.ai/api/v1"
    },
    "anthropic": {"api_key": "$ANTHROPIC_KEY"},
    "openai":    {"api_key": "$OPENAI_KEY"}
  },
  "channels": {
    "telegram": {
      "enabled": $([ -n "$TG_TOKEN" ] && echo "true" || echo "false"),
      "bot_token": "$TG_TOKEN"
    },
    "discord": {
      "enabled": $([ -n "$DC_TOKEN" ] && echo "true" || echo "false"),
      "bot_token": "$DC_TOKEN"
    },
    "slack": {
      "enabled": $([ -n "$SL_BOT_TOKEN" ] && echo "true" || echo "false"),
      "bot_token": "$SL_BOT_TOKEN",
      "app_token": "$SL_APP_TOKEN"
    },
    "email":    {"enabled": false},
    "whatsapp": {"enabled": false}
  },
  "auth": {
    "enabled": $MULTI_USER,
    "secret_key": "$JWT_SECRET"
  },
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
    echo "# Graphclaw environment — loaded at startup"
    echo "GRAPHCLAW_CONFIG_PATH=$CONFIG_FILE"
    [ -n "$OPENROUTER_KEY" ] && echo "OPENROUTER_API_KEY=$OPENROUTER_KEY"
    [ -n "$ANTHROPIC_KEY"  ] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_KEY"
    [ -n "$OPENAI_KEY"     ] && echo "OPENAI_API_KEY=$OPENAI_KEY"
    [ -n "$BASE44_KEY"     ] && echo "BASE44_API_KEY=$BASE44_KEY"
    [ -n "$LOVEABLE_KEY"   ] && echo "LOVEABLE_API_KEY=$LOVEABLE_KEY"
} > "$ENV_FILE"
ok ".env written to ${W}$ENV_FILE${NC}"

# run.sh
cat > "$GRAPHCLAW_DIR/run.sh" << EOF
#!/usr/bin/env bash
set -a
source "$ENV_FILE"
set +a
exec jac run "$SCRIPT_DIR/graphclaw/main.jac" "\$@"
EOF
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

# Fish shell
FISH_RC="$HOME/.config/fish/config.fish"
if [ -f "$FISH_RC" ]; then
    if ! grep -q "alias graphclaw" "$FISH_RC" 2>/dev/null; then
        echo "alias graphclaw '$GRAPHCLAW_DIR/run.sh'" >> "$FISH_RC"
        ok "Added ${W}graphclaw${NC} alias to Fish config"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${G}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║                                                           ║"
echo "  ║   ✓  Graphclaw installed successfully!                    ║"
echo "  ║                                                           ║"
echo -e "  ╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "  ${BOLD}${W}Configuration${NC}"
echo -e "  ${D}──────────────────────────────────────────${NC}"
printf   "  %-12s %s\n" "Mode:"     "$([ "$MULTI_USER" = "true" ] && echo 'Multi-user (JWT auth enabled)' || echo 'Single-user')"
printf   "  %-12s %s\n" "Provider:" "$PROVIDER_NAME"
printf   "  %-12s %s\n" "Model:"    "$DEFAULT_MODEL"
printf   "  %-12s %s\n" "Config:"   "$CONFIG_FILE"
printf   "  %-12s %s\n" "Workspace:" "$WORKSPACE_DIR"
echo ""

echo -e "  ${BOLD}${W}Next steps${NC}"
echo -e "  ${D}──────────────────────────────────────────${NC}"
if [ -n "$SHELL_RC" ]; then
    echo -e "  ${ARROW} Reload your shell:"
    echo -e "       ${W}source $SHELL_RC${NC}"
    echo ""
fi
echo -e "  ${ARROW} Start in CLI mode:"
echo -e "       ${W}graphclaw${NC}   ${D}(after reloading shell)${NC}"
echo -e "       ${W}$GRAPHCLAW_DIR/run.sh${NC}   ${D}(works immediately)${NC}"
echo ""
if [ "$MULTI_USER" = "true" ]; then
    echo -e "  ${ARROW} Start as HTTP server:"
    echo -e "       ${W}jac start $SCRIPT_DIR/graphclaw/main.jac${NC}"
    echo -e "       ${D}→ http://localhost:8000/docs${NC}"
    echo ""
fi
echo -e "  ${ARROW} Edit config anytime:"
echo -e "       ${W}\$EDITOR ~/.graphclaw/config.json${NC}"
echo ""
