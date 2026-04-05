#!/usr/bin/env bash
# Graphclaw installer
# Usage: bash install.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

GRAPHCLAW_DIR="$HOME/.graphclaw"
WORKSPACE_DIR="$GRAPHCLAW_DIR/workspace"
CONFIG_FILE="$GRAPHCLAW_DIR/config.json"

echo ""
echo -e "${BOLD}${CYAN}  ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗ ██████╗██╗      █████╗ ██╗    ██╗${NC}"
echo -e "${BOLD}${CYAN} ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║██╔════╝██║     ██╔══██╗██║    ██║${NC}"
echo -e "${BOLD}${CYAN} ██║  ███╗██████╔╝███████║██████╔╝███████║██║     ██║     ███████║██║ █╗ ██║${NC}"
echo -e "${BOLD}${CYAN} ██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║██║     ██║     ██╔══██║██║███╗██║${NC}"
echo -e "${BOLD}${CYAN} ╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║╚██████╗███████╗██║  ██║╚███╔███╔╝${NC}"
echo -e "${BOLD}${CYAN}  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ ${NC}"
echo ""
echo -e "${BOLD}  Graph-native multi-agent AI platform${NC}"
echo ""

# ── Check Python ──────────────────────────────────────────────────────────────

echo -e "${CYAN}Checking Python...${NC}"
if command -v python3.12 &>/dev/null; then
    PYTHON=python3.12
elif command -v python3.13 &>/dev/null; then
    PYTHON=python3.13
elif command -v python3.14 &>/dev/null; then
    PYTHON=python3.14
elif command -v python3 &>/dev/null; then
    PY_VER=$(python3 -c "import sys; print(sys.version_info.minor)")
    PY_MAJ=$(python3 -c "import sys; print(sys.version_info.major)")
    if [ "$PY_MAJ" -ge 3 ] && [ "$PY_VER" -ge 12 ]; then
        PYTHON=python3
    else
        echo -e "${RED}Python 3.12+ required. Install from https://python.org${NC}"
        exit 1
    fi
else
    echo -e "${RED}Python not found. Install Python 3.12+ from https://python.org${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Using $($PYTHON --version)${NC}"

# ── Install graphclaw package ─────────────────────────────────────────────────

echo ""
echo -e "${CYAN}Installing graphclaw...${NC}"
$PYTHON -m pip install --upgrade pip -q
$PYTHON -m pip install -e "$(dirname "$0")" -q
echo -e "${GREEN}  ✓ Graphclaw installed${NC}"

# ── Single vs Multi-user ──────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Deployment mode:${NC}"
echo "  1) Single-user  — personal agent, no auth required"
echo "  2) Multi-user   — hosted platform, JWT auth, per-user memory graphs"
echo ""
read -p "Select mode [1/2] (default: 1): " MODE_CHOICE
MODE_CHOICE="${MODE_CHOICE:-1}"

if [ "$MODE_CHOICE" = "2" ]; then
    MULTI_USER=true
    echo -e "${GREEN}  ✓ Multi-user mode selected${NC}"
    read -p "  Secret key for JWT (leave blank to generate): " JWT_SECRET
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$($PYTHON -c "import secrets; print(secrets.token_hex(32))")
        echo -e "${YELLOW}  Generated secret key (save this!): $JWT_SECRET${NC}"
    fi
else
    MULTI_USER=false
    JWT_SECRET=""
    echo -e "${GREEN}  ✓ Single-user mode selected${NC}"
fi

# ── LLM Provider ──────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}LLM Provider:${NC}"
echo "  1) OpenRouter  (recommended — access to all models with one key)"
echo "  2) Anthropic   (Claude direct)"
echo "  3) OpenAI"
echo "  4) Ollama      (local, no key needed)"
echo "  5) Skip        (configure manually in ~/.graphclaw/config.json)"
echo ""
read -p "Select provider [1-5] (default: 1): " PROVIDER_CHOICE
PROVIDER_CHOICE="${PROVIDER_CHOICE:-1}"

OPENROUTER_KEY=""
ANTHROPIC_KEY=""
OPENAI_KEY=""
DEFAULT_MODEL="openrouter/anthropic/claude-sonnet-4-6"

case "$PROVIDER_CHOICE" in
    1)
        read -p "  OpenRouter API key: " OPENROUTER_KEY
        echo -e "${GREEN}  ✓ OpenRouter configured${NC}"
        ;;
    2)
        read -p "  Anthropic API key: " ANTHROPIC_KEY
        DEFAULT_MODEL="anthropic/claude-sonnet-4-6"
        echo -e "${GREEN}  ✓ Anthropic configured${NC}"
        ;;
    3)
        read -p "  OpenAI API key: " OPENAI_KEY
        DEFAULT_MODEL="openai/gpt-4o"
        echo -e "${GREEN}  ✓ OpenAI configured${NC}"
        ;;
    4)
        DEFAULT_MODEL="ollama/llama3"
        echo -e "${GREEN}  ✓ Ollama configured (make sure ollama is running)${NC}"
        ;;
    5)
        echo -e "${YELLOW}  Skipping — edit ~/.graphclaw/config.json to set your key${NC}"
        ;;
esac

# ── Channels ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Channels (press Enter to skip any):${NC}"

read -p "  Telegram bot token: " TG_TOKEN
read -p "  Discord bot token:  " DC_TOKEN
read -p "  Slack bot token:    " SL_BOT_TOKEN
read -p "  Slack app token:    " SL_APP_TOKEN

# ── DevOps skills ─────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}DevOps skill API keys (press Enter to skip):${NC}"
read -p "  Base44 API key:    " BASE44_KEY
read -p "  Loveable API key:  " LOVEABLE_KEY

# ── Create workspace ──────────────────────────────────────────────────────────

mkdir -p "$WORKSPACE_DIR/memory"
mkdir -p "$WORKSPACE_DIR/sessions"
mkdir -p "$WORKSPACE_DIR/skills/installed"
mkdir -p "$GRAPHCLAW_DIR/skills/installed"

# ── Write config.json ─────────────────────────────────────────────────────────

echo ""
echo -e "${CYAN}Writing config...${NC}"

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
    "openai": {"api_key": "$OPENAI_KEY"}
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
    "email": {"enabled": false},
    "whatsapp": {"enabled": false}
  },
  "auth": {
    "enabled": $MULTI_USER,
    "secret_key": "$JWT_SECRET"
  },
  "skills": {
    "registry_url": "https://raw.githubusercontent.com/graphclaw/skills-registry/main/index.json",
    "installed_path": "$GRAPHCLAW_DIR/skills/installed"
  }
}
EOF

echo -e "${GREEN}  ✓ Config written to $CONFIG_FILE${NC}"

# ── Write .env for skill API keys ─────────────────────────────────────────────

ENV_FILE="$GRAPHCLAW_DIR/.env"
cat > "$ENV_FILE" << EOF
# Graphclaw environment — loaded at startup
GRAPHCLAW_CONFIG_PATH=$CONFIG_FILE
$([ -n "$BASE44_KEY" ] && echo "BASE44_API_KEY=$BASE44_KEY")
$([ -n "$LOVEABLE_KEY" ] && echo "LOVEABLE_API_KEY=$LOVEABLE_KEY")
$([ -n "$OPENROUTER_KEY" ] && echo "OPENROUTER_API_KEY=$OPENROUTER_KEY")
$([ -n "$ANTHROPIC_KEY" ] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_KEY")
$([ -n "$OPENAI_KEY" ] && echo "OPENAI_API_KEY=$OPENAI_KEY")
EOF

echo -e "${GREEN}  ✓ .env written to $ENV_FILE${NC}"

# ── Write startup script ───────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat > "$GRAPHCLAW_DIR/run.sh" << EOF
#!/usr/bin/env bash
set -a
source "$ENV_FILE"
set +a
exec $PYTHON -m jaclang.cli.cli run "$SCRIPT_DIR/graphclaw/main.jac" "\$@"
EOF
chmod +x "$GRAPHCLAW_DIR/run.sh"

# Shell alias
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q "alias graphclaw=" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "alias graphclaw='$GRAPHCLAW_DIR/run.sh'" >> "$SHELL_RC"
        echo -e "${GREEN}  ✓ Added 'graphclaw' alias to $SHELL_RC${NC}"
    fi
fi

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}✓ Graphclaw installed successfully!${NC}"
echo ""
echo -e "  ${BOLD}Start:${NC}    $GRAPHCLAW_DIR/run.sh"
echo -e "  ${BOLD}Config:${NC}   $CONFIG_FILE"
echo -e "  ${BOLD}Skills:${NC}   $GRAPHCLAW_DIR/skills/installed/"
echo ""
if [ "$MULTI_USER" = "true" ]; then
    echo -e "  ${BOLD}Mode:${NC}     Multi-user (auth enabled)"
    echo -e "  ${BOLD}API:${NC}      jac start graphclaw/main.jac  →  http://localhost:8000"
else
    echo -e "  ${BOLD}Mode:${NC}     Single-user"
fi
echo ""
echo -e "${YELLOW}  Reload your shell or run: source $SHELL_RC${NC}"
echo ""
