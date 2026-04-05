# ─────────────────────────────────────────────────────────────────────────────
#  Graphclaw Windows Installer (PowerShell)
#  Usage:
#    irm https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.ps1 | iex
#  Or locally:
#    .\install.ps1
# ─────────────────────────────────────────────────────────────────────────────

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Color {
    param([string]$Text, [string]$Color = "White", [switch]$NoNewline)
    if ($NoNewline) { Write-Host $Text -ForegroundColor $Color -NoNewline }
    else            { Write-Host $Text -ForegroundColor $Color }
}

function ok   { param([string]$Msg) Write-Color "  [OK] $Msg" Green }
function warn { param([string]$Msg) Write-Color "  [!!] $Msg" Yellow }
function info { param([string]$Msg) Write-Color "  ...  $Msg" DarkGray }
function fail { param([string]$Msg) Write-Color "  [X]  $Msg" Red; exit 1 }
function hint { param([string]$Msg) Write-Color "       $Msg" DarkGray }

# Write file without BOM (PS5.1 Encoding UTF8 adds BOM — this doesn't)
function Write-NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# ask_optional — empty input is fine
function ask_optional {
    param([string]$Prompt)
    Write-Host "  [?] ${Prompt} " -ForegroundColor Cyan -NoNewline
    Write-Host "(optional, Enter to skip): " -ForegroundColor DarkGray -NoNewline
    return Read-Host
}

# ask_required — loops until non-empty
function ask_required {
    param([string]$Prompt)
    while ($true) {
        Write-Host "  [?] ${Prompt}: " -ForegroundColor Cyan -NoNewline
        $r = Read-Host
        if ($r) { return $r }
        Write-Color "      Required — please enter a value." Red
    }
}

# ask_choice — loops until input is in $Valid
function ask_choice {
    param([string]$Prompt, [string[]]$Valid, [string]$Default)
    while ($true) {
        Write-Host "  [?] ${Prompt} " -ForegroundColor Cyan -NoNewline
        Write-Host "[default: ${Default}]: " -ForegroundColor DarkGray -NoNewline
        $r = Read-Host
        if (-not $r) { $r = $Default }
        if ($Valid -contains $r) { return $r }
        Write-Color "      Invalid — enter one of: $($Valid -join ', ')" Red
    }
}

# ── Banner ────────────────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Color "  +===========================================================+" Cyan
Write-Color "  |                                                           |" Cyan
Write-Color "  |    GRAPHCLAW                              v0.1.0          |" Cyan
Write-Color "  |    Graph-native multi-agent AI platform in Jac            |" Cyan
Write-Color "  |                                                           |" Cyan
Write-Color "  +===========================================================+" Cyan
Write-Host ""

$StepN = 0
$TotalSteps = 6

function Step {
    param([string]$Name)
    $script:StepN++
    Write-Host ""
    Write-Color "  [$($script:StepN)/$TotalSteps] $Name" White
    Write-Color ("  " + ("-" * 60)) DarkGray
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 -- Python
# ─────────────────────────────────────────────────────────────────────────────

Step "Checking Python"

function Test-PythonExe {
    param([string]$Exe)
    if (-not (Test-Path $Exe -ErrorAction SilentlyContinue)) { return $false }
    try {
        $ver = & $Exe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        if ($ver -match '^\d+\.\d+$') {
            $parts = $ver.Split(".")
            return ([int]$parts[0] -eq 3 -and [int]$parts[1] -ge 12 -and [int]$parts[1] -le 13)
        }
    } catch { }
    return $false
}

function Find-Python {
    # 1. Windows Python Launcher -- most reliable, works regardless of PATH
    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        foreach ($tag in @("3.13","3.12")) {
            try {
                $exe = & py -$tag -c "import sys; print(sys.executable)" 2>$null
                if ($exe -and (Test-PythonExe $exe)) { return $exe }
            } catch { }
        }
    }

    # 2. Known install paths (user + system, winget and manual installs)
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:ProgramFiles\Python313\python.exe",
        "$env:ProgramFiles\Python312\python.exe",
        "C:\Python313\python.exe",
        "C:\Python312\python.exe"
    )
    foreach ($p in $candidates) {
        if (Test-PythonExe $p) { return $p }
    }

    # 3. PATH scan -- skip 3.14+
    foreach ($cmd in @("python3.13","python3.12","python3","python")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            if (Test-PythonExe $found.Source) { return $found.Source }
            try {
                $ver = & $found.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
                if ($ver -match '^3\.1[4-9]') {
                    warn "Python $ver found but 3.14+ is not supported yet (jaclang incompatible). Skipping."
                }
            } catch { }
        }
    }
    return $null
}

$Python = Find-Python

if (-not $Python) {
    info "Python 3.12-3.13 not found -- installing Python 3.13 via winget..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        # winget exits 0 for both fresh install and "already installed" -- both are fine
        winget install --id Python.Python.3.13 --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        # Refresh PATH and retry
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
        $Python = Find-Python
    }
    if (-not $Python) {
        Write-Host ""
        Write-Color "  Python 3.13 is installed but needs a new terminal session to be found." Yellow
        Write-Host ""
        Write-Color "  Please open a NEW PowerShell window and run:" White
        Write-Color "      irm https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.ps1 | iex" Cyan
        Write-Host ""
        exit 0
    }
}

$pyVer = & $Python --version 2>&1
ok "Using $pyVer"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 -- Clone / locate repo
# ─────────────────────────────────────────────────────────────────────────────

Step "Locating source"

$GraphclawDir = "$env:USERPROFILE\.graphclaw"
$WorkspaceDir = "$GraphclawDir\workspace"
$ConfigFile   = "$GraphclawDir\config.json"
$EnvFile      = "$GraphclawDir\.env"
$VenvDir      = "$GraphclawDir\venv"
$SourceDir    = "$GraphclawDir\source"

$ScriptDir = $null
try { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch {}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    fail "git is required. Install from https://git-scm.com and retry."
}

if (Test-Path "$SourceDir\.git") {
    ok "Using managed source at $SourceDir"
} elseif ($ScriptDir -and (Test-Path "$ScriptDir\pyproject.toml" -ErrorAction SilentlyContinue) -and (Test-Path "$ScriptDir\.git" -ErrorAction SilentlyContinue)) {
    info "Creating managed source copy..."
    if (Test-Path $SourceDir) { Remove-Item -Recurse -Force $SourceDir }
    git clone --quiet $ScriptDir $SourceDir 2>$null
    ok "Managed source created at $SourceDir"
} else {
    info "Cloning graphclaw repository..."
    if (Test-Path $SourceDir) { Remove-Item -Recurse -Force $SourceDir }
    git clone --depth 1 https://github.com/zero-abd/graphclaw $SourceDir -q 2>$null
    ok "Cloned managed source to $SourceDir"
}

New-Item -ItemType Directory -Force -Path "$WorkspaceDir\memory" | Out-Null
New-Item -ItemType Directory -Force -Path "$WorkspaceDir\sessions" | Out-Null
New-Item -ItemType Directory -Force -Path "$WorkspaceDir\skills\installed" | Out-Null
New-Item -ItemType Directory -Force -Path "$GraphclawDir\skills\installed" | Out-Null

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 -- Create venv & install dependencies
# ─────────────────────────────────────────────────────────────────────────────

Step "Installing dependencies"

info "Creating virtual environment at $VenvDir"
& $Python -m venv $VenvDir
if ($LASTEXITCODE -ne 0) { fail "Failed to create virtual environment." }

# Activate venv — all pip/jac commands now install here
$VenvPython = "$VenvDir\Scripts\python.exe"
$VenvPip    = "$VenvDir\Scripts\pip.exe"
ok "Virtual environment created"

$ErrorActionPreference = "Continue"

info "Upgrading pip..."
& $VenvPython -m pip install --upgrade pip -q 2>&1 | Out-Null

info "Installing jaclang (Jac runtime)..."
$jacOut = & $VenvPip install "jaclang>=0.13.5,<0.14" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Color "  pip output:" DarkGray
    $jacOut | ForEach-Object { Write-Color "    $_" DarkGray }
    $ErrorActionPreference = "Stop"; fail "Failed to install jaclang."
}

info "Installing graphclaw..."
$gcOut = & $VenvPip install -e "${SourceDir}[channels]" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Color "  pip output:" DarkGray
    $gcOut | ForEach-Object { Write-Color "    $_" DarkGray }
    $ErrorActionPreference = "Stop"; fail "Failed to install graphclaw."
}

$ErrorActionPreference = "Stop"

# Verify jac is in the venv
$VenvJac = "$VenvDir\Scripts\jac.exe"
if (Test-Path $VenvJac) {
    ok "jac CLI ready: $VenvJac"
} else {
    warn "jac not found in venv -- this shouldn't happen"
}
ok "All dependencies installed in venv"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 -- Deployment mode
# ─────────────────────────────────────────────────────────────────────────────

Step "Deployment mode"

Write-Color "  How will you run Graphclaw?" DarkGray
Write-Host ""
Write-Color "    1)  Single-user   -- personal agent, no auth  (best for most users)" White
Write-Color "    2)  Multi-user    -- hosted server, JWT auth, per-user memory" White
Write-Host ""

$ModeChoice = ask_choice "Select mode [1/2]" @("1","2") "1"
$MultiUser  = "false"
$JwtSecret  = ""

if ($ModeChoice -eq "2") {
    $MultiUser = "true"
    ok "Multi-user mode selected"
    $JwtSecret = ask_optional "JWT secret key (blank = auto-generate)"
    if (-not $JwtSecret) {
        $JwtSecret = & $Python -c "import secrets; print(secrets.token_hex(32))"
        warn "Generated JWT secret -- save this: $JwtSecret"
    }
} else {
    ok "Single-user mode selected"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 -- LLM provider & channels
# ─────────────────────────────────────────────────────────────────────────────

Step "LLM provider & channels"

Write-Color "  Choose your default LLM provider:" DarkGray
Write-Host ""
Write-Color "    1)  OpenRouter   -- one key, route models like Claude through OpenRouter  (recommended)" White
Write-Color "    2)  Anthropic    -- Claude direct (claude.ai/settings -> API Keys)" White
Write-Color "    3)  OpenAI       -- GPT-4o (platform.openai.com/api-keys)" White
Write-Color "    4)  Ollama       -- local models, no API key needed" White
Write-Color "    5)  Skip         -- configure manually in ~/.graphclaw/config.json" White
Write-Host ""

$ProviderChoice = ask_choice "Select provider [1-5]" @("1","2","3","4","5") "1"
$OpenrouterKey  = ""; $AnthropicKey = ""; $OpenaiKey = ""
$DefaultModel   = "openrouter/anthropic/claude-sonnet-4-6"
$ProviderName   = "OpenRouter"

switch ($ProviderChoice) {
    "1" {
        hint "OpenRouter key only -- you do NOT need an Anthropic key for the default Claude-via-OpenRouter model"
        hint "Get your key at: https://openrouter.ai/keys"
        $OpenrouterKey = ask_optional "Paste OpenRouter API key now"
        if ($OpenrouterKey) {
            ok "OpenRouter configured"
        } else {
            hint "Set it later with an environment variable instead:"
            hint "macOS / Linux: export OPENROUTER_API_KEY='your-key'"
            hint "Windows PowerShell: `$env:OPENROUTER_API_KEY='your-key'"
            warn "No OpenRouter key saved yet -- Graphclaw will prompt again in the CLI if it needs one"
        }
    }
    "2" {
        hint "Get your key at: https://console.anthropic.com/settings/keys"
        $AnthropicKey = ask_optional "Paste Anthropic API key now"
        $DefaultModel = "anthropic/claude-sonnet-4-6"
        $ProviderName = "Anthropic"
        if ($AnthropicKey) {
            ok "Anthropic configured"
        } else {
            hint "Set it later with an environment variable instead:"
            hint "macOS / Linux: export ANTHROPIC_API_KEY='your-key'"
            hint "Windows PowerShell: `$env:ANTHROPIC_API_KEY='your-key'"
            warn "No Anthropic key saved yet -- Graphclaw will prompt again in the CLI if it needs one"
        }
    }
    "3" {
        hint "Get your key at: https://platform.openai.com/api-keys"
        $OpenaiKey = ask_optional "Paste OpenAI API key now"
        $DefaultModel = "openai/gpt-4o"
        $ProviderName = "OpenAI"
        if ($OpenaiKey) {
            ok "OpenAI configured"
        } else {
            hint "Set it later with an environment variable instead:"
            hint "macOS / Linux: export OPENAI_API_KEY='your-key'"
            hint "Windows PowerShell: `$env:OPENAI_API_KEY='your-key'"
            warn "No OpenAI key saved yet -- Graphclaw will prompt again in the CLI if it needs one"
        }
    }
    "4" {
        $DefaultModel = "ollama/llama3"
        $ProviderName = "Ollama"
        ok "Ollama -- make sure 'ollama serve' is running"
    }
    "5" {
        ok "Skipped -- edit ~/.graphclaw/config.json to add your key later"
        $ProviderName = "(not set)"
    }
}

Write-Host ""
Write-Color "  Pick the first chat interface you want to set up:" DarkGray
Write-Color "  You can add more later by re-running install.ps1 or editing ~/.graphclaw/config.json." DarkGray
Write-Host ""
Write-Color "    1)  Telegram   -- easiest for personal use" White
Write-Color "    2)  Discord    -- best for servers / communities" White
Write-Color "    3)  Slack      -- best for internal teams" White
Write-Color "    4)  Skip for now -- configure later" White
Write-Host ""

$ChannelChoice = ask_choice "Select first chat interface [1-4]" @("1","2","3","4") "1"
$TgToken = ""; $DcToken = ""; $SlBotToken = ""; $SlAppToken = ""

function Resolve-TelegramBotUsername {
    param([string]$Token)
    if (-not $Token) { return $null }
    try {
        $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$Token/getMe" -Method Get -TimeoutSec 10
        $username = [string]$resp.result.username
        if ($username) { return $username.TrimStart("@") }
    } catch { }
    return $null
}

function Configure-Telegram {
    Write-Host ""
    Write-Color "  Telegram setup walkthrough" White
    hint "Open BotFather: https://t.me/BotFather"
    hint "1. Send /newbot"
    hint "2. Choose a display name for your bot"
    hint "3. Choose a unique username ending in 'bot'"
    hint "4. Copy the token BotFather gives you"
    hint "5. Start a chat with your bot so it can message you back"
    $script:TgToken = ask_optional "Paste Telegram bot token"
    if ($script:TgToken) {
        ok "Telegram configured"
        $tgUsername = Resolve-TelegramBotUsername $script:TgToken
        if ($tgUsername) {
            hint "Client onboarding link: https://t.me/$tgUsername"
            hint "Tell the client to open that link, press Start, then send any message."
        } else {
            hint "Next step: open your bot in Telegram, press Start, then send any message."
        }
        hint "If Telegram replies with a pairing code, approve it locally with:"
        hint "  pairing list telegram"
        hint "  pairing approve telegram <code>"
    }
}

function Configure-Discord {
    Write-Host ""
    Write-Color "  Discord setup walkthrough" White
    hint "Open Discord Developer Portal: https://discord.com/developers/applications"
    hint "1. Click New Application"
    hint "2. Open the Bot tab and click Add Bot"
    hint "3. Reset / copy the bot token"
    hint "4. In Bot settings, enable Message Content Intent"
    hint "5. In OAuth2 -> URL Generator, select 'bot' scope and invite the bot to your server"
    $script:DcToken = ask_optional "Paste Discord bot token"
    if ($script:DcToken) { ok "Discord configured" }
}

function Configure-Slack {
    Write-Host ""
    Write-Color "  Slack setup walkthrough" White
    hint "Open Slack app builder: https://api.slack.com/apps"
    hint "1. Click Create New App"
    hint "2. Add a bot user under App Home"
    hint "3. In OAuth & Permissions, install the app and copy the Bot User OAuth Token (xoxb-...)"
    hint "4. Enable Socket Mode"
    hint "5. In Basic Information -> App-Level Tokens, create a token with connections:write (xapp-...)"
    hint "6. Invite the bot to the channel you want to use"
    $script:SlBotToken = ask_optional "Paste Slack bot token (xoxb-...)"
    if ($script:SlBotToken) {
        $script:SlAppToken = ask_required "Paste Slack app token (xapp-...)"
        ok "Slack configured"
    }
}

switch ($ChannelChoice) {
    "1" { Configure-Telegram }
    "2" { Configure-Discord }
    "3" { Configure-Slack }
    "4" { ok "Skipped messaging channels for now -- add one later in ~/.graphclaw/config.json or by re-running install.ps1" }
}

Write-Host ""
Write-Color "  DevOps skill API keys (optional):" DarkGray
Write-Host ""
hint "Base44: app.base44.com/settings -> API Keys"
$Base44Key = ask_optional "Base44 API key"
hint "Loveable: lovable.dev/settings -> API"
$LoveableKey = ask_optional "Loveable API key"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 -- Write config & shell integration
# ─────────────────────────────────────────────────────────────────────────────

Step "Writing config & shell integration"

$DefaultProviderKey = "openrouter"
switch ($ProviderChoice) {
    "2" { $DefaultProviderKey = "anthropic" }
    "3" { $DefaultProviderKey = "openai" }
    "4" { $DefaultProviderKey = "ollama" }
}

$env:GRAPHCLAW_CONFIG_MERGE_PATH = $ConfigFile
$env:GRAPHCLAW_WORKSPACE_PATH = $WorkspaceDir
$env:GRAPHCLAW_INSTALLED_SKILLS = "$GraphclawDir\skills\installed"
$env:GRAPHCLAW_DEFAULT_MODEL = $DefaultModel
$env:GRAPHCLAW_DEFAULT_PROVIDER = $DefaultProviderKey
$env:GRAPHCLAW_MULTI_USER = $MultiUser
$env:GRAPHCLAW_JWT_SECRET = $JwtSecret
$env:GRAPHCLAW_OPENROUTER_KEY = $OpenrouterKey
$env:GRAPHCLAW_ANTHROPIC_KEY = $AnthropicKey
$env:GRAPHCLAW_OPENAI_KEY = $OpenaiKey
$env:GRAPHCLAW_TG_TOKEN = $TgToken
$env:GRAPHCLAW_DC_TOKEN = $DcToken
$env:GRAPHCLAW_SL_BOT_TOKEN = $SlBotToken
$env:GRAPHCLAW_SL_APP_TOKEN = $SlAppToken

$ConfigMerge = @'
import json
import os
from pathlib import Path

config_path = Path(os.environ["GRAPHCLAW_CONFIG_MERGE_PATH"])
existing = {}
if config_path.exists():
    try:
        existing = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception:
        existing = {}
if not isinstance(existing, dict):
    existing = {}

cfg = existing
cfg["workspace"] = cfg.get("workspace") or os.environ["GRAPHCLAW_WORKSPACE_PATH"]
cfg["multi_user"] = os.environ["GRAPHCLAW_MULTI_USER"].lower() == "true"

agents = cfg.setdefault("agents", {})
agents["model"] = os.environ["GRAPHCLAW_DEFAULT_MODEL"]
agents.setdefault("max_tokens", 8192)
agents.setdefault("temperature", 0.7)
agents.setdefault("max_tool_iterations", 200)
dream = agents.setdefault("dream", {})
dream.setdefault("enabled", True)
dream.setdefault("interval_hours", 2)

providers = cfg.setdefault("providers", {})
providers["default_provider"] = os.environ["GRAPHCLAW_DEFAULT_PROVIDER"]
providers.setdefault("openrouter", {"base_url": "https://openrouter.ai/api/v1"})
providers.setdefault("anthropic", {})
providers.setdefault("openai", {})
providers.setdefault("ollama", {"base_url": "http://localhost:11434"})
if os.environ.get("GRAPHCLAW_OPENROUTER_KEY"):
    providers["openrouter"]["api_key"] = os.environ["GRAPHCLAW_OPENROUTER_KEY"]
providers["openrouter"].setdefault("base_url", "https://openrouter.ai/api/v1")
if os.environ.get("GRAPHCLAW_ANTHROPIC_KEY"):
    providers["anthropic"]["api_key"] = os.environ["GRAPHCLAW_ANTHROPIC_KEY"]
if os.environ.get("GRAPHCLAW_OPENAI_KEY"):
    providers["openai"]["api_key"] = os.environ["GRAPHCLAW_OPENAI_KEY"]

channels = cfg.setdefault("channels", {})
channels.setdefault("telegram", {"enabled": False, "bot_token": "", "allowed_ids": []})
channels.setdefault("discord", {"enabled": False, "bot_token": "", "allowed_ids": []})
channels.setdefault("slack", {"enabled": False, "bot_token": "", "app_token": "", "allowed_ids": []})
channels.setdefault("email", {"enabled": False})
channels.setdefault("whatsapp", {"enabled": False})
if os.environ.get("GRAPHCLAW_TG_TOKEN"):
    channels["telegram"]["enabled"] = True
    channels["telegram"]["bot_token"] = os.environ["GRAPHCLAW_TG_TOKEN"]
if os.environ.get("GRAPHCLAW_DC_TOKEN"):
    channels["discord"]["enabled"] = True
    channels["discord"]["bot_token"] = os.environ["GRAPHCLAW_DC_TOKEN"]
if os.environ.get("GRAPHCLAW_SL_BOT_TOKEN"):
    channels["slack"]["enabled"] = True
    channels["slack"]["bot_token"] = os.environ["GRAPHCLAW_SL_BOT_TOKEN"]
if os.environ.get("GRAPHCLAW_SL_APP_TOKEN"):
    channels["slack"]["app_token"] = os.environ["GRAPHCLAW_SL_APP_TOKEN"]

auth = cfg.setdefault("auth", {})
auth["enabled"] = os.environ["GRAPHCLAW_MULTI_USER"].lower() == "true"
if os.environ.get("GRAPHCLAW_JWT_SECRET"):
    auth["secret_key"] = os.environ["GRAPHCLAW_JWT_SECRET"]
else:
    auth.setdefault("secret_key", "")

skills = cfg.setdefault("skills", {})
skills.setdefault("registry_url", "https://clawhub.ai/api/v1")
skills["installed_path"] = os.environ["GRAPHCLAW_INSTALLED_SKILLS"]

config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
'@
$ConfigMergePath = Join-Path $env:TEMP "graphclaw-config-merge.py"
Write-NoBom $ConfigMergePath $ConfigMerge
& $VenvPython $ConfigMergePath
Remove-Item $ConfigMergePath -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { fail "Failed to write merged config." }
ok "Config written to $ConfigFile"

$envMap = @{}
if (Test-Path $EnvFile) {
    foreach ($line in (Get-Content $EnvFile -ErrorAction SilentlyContinue)) {
        if (-not $line -or $line.Trim().StartsWith("#") -or -not ($line -match "=")) { continue }
        $key, $value = $line -split "=", 2
        $envMap[$key] = $value
    }
}
$envMap["GRAPHCLAW_CONFIG_PATH"] = $ConfigFile
$envMap["GRAPHCLAW_HOME"] = $GraphclawDir
if ($OpenrouterKey) { $envMap["OPENROUTER_API_KEY"] = $OpenrouterKey }
if ($AnthropicKey)  { $envMap["ANTHROPIC_API_KEY"] = $AnthropicKey }
if ($OpenaiKey)     { $envMap["OPENAI_API_KEY"] = $OpenaiKey }
if ($Base44Key)     { $envMap["BASE44_API_KEY"] = $Base44Key }
if ($LoveableKey)   { $envMap["LOVEABLE_API_KEY"] = $LoveableKey }
$envLines = @("# Graphclaw environment")
foreach ($key in @("GRAPHCLAW_CONFIG_PATH","GRAPHCLAW_HOME","OPENROUTER_API_KEY","ANTHROPIC_API_KEY","OPENAI_API_KEY","BASE44_API_KEY","LOVEABLE_API_KEY")) {
    if ($envMap.ContainsKey($key) -and $envMap[$key]) {
        $envLines += "${key}=$($envMap[$key])"
    }
}
Write-NoBom $EnvFile ($envLines -join "`r`n")
ok ".env written to $EnvFile"

$RunBat = "$GraphclawDir\run.bat"
$MainJac = "$SourceDir\graphclaw\main.jac"
$RunBatContent = @"
@echo off
call "$VenvDir\Scripts\activate.bat"
set GRAPHCLAW_CONFIG_PATH=$ConfigFile
set GRAPHCLAW_HOME=$GraphclawDir
if /I "%~1"=="update" (
  shift
  "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager update %*
  goto :eof
)
if /I "%~1"=="rollback" (
  shift
  "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager rollback %*
  goto :eof
)
if /I "%~1"=="status" (
  shift
  "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager status %*
  goto :eof
)
jac run --no-autonative "$MainJac" %*
"@
Write-NoBom $RunBat $RunBatContent
ok "Startup script: $RunBat"

$RunPs1 = "$GraphclawDir\run.ps1"
$RunPs1Content = @"
& "$VenvDir\Scripts\Activate.ps1"
`$env:GRAPHCLAW_CONFIG_PATH = "$ConfigFile"
`$env:GRAPHCLAW_HOME = "$GraphclawDir"
if (`$args.Count -gt 0) {
  switch (`$args[0]) {
    "update" {
      if (`$args.Count -gt 1) {
        & "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager update @(`$args[1..(`$args.Count-1)])
      } else {
        & "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager update
      }
      return
    }
    "rollback" {
      if (`$args.Count -gt 1) {
        & "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager rollback @(`$args[1..(`$args.Count-1)])
      } else {
        & "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager rollback
      }
      return
    }
    "status" {
      if (`$args.Count -gt 1) {
        & "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager status @(`$args[1..(`$args.Count-1)])
      } else {
        & "$VenvDir\Scripts\python.exe" -m graphclaw.update_manager status
      }
      return
    }
  }
}
jac run --no-autonative "$MainJac" @args
"@
Write-NoBom $RunPs1 $RunPs1Content
ok "PowerShell startup: $RunPs1"

# PowerShell profile function
$ProfileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null }

$AliasLine = "function graphclaw { & '$RunPs1' @args }"
Invoke-Expression $AliasLine
ok "Loaded 'graphclaw' into the current PowerShell session"
if (Test-Path $PROFILE) {
    $existing = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($existing -and $existing -match "function graphclaw") {
        ok "'graphclaw' already in PowerShell profile"
    } else {
        Add-Content -Path $PROFILE -Value "`n$AliasLine"
        ok "Added 'graphclaw' to PowerShell profile"
    }
} else {
    Write-NoBom $PROFILE $AliasLine
    ok "Created PowerShell profile with 'graphclaw'"
}

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Color "  +===========================================================+" Green
Write-Color "  |                                                           |" Green
Write-Color "  |   [OK]  Graphclaw installed successfully!                 |" Green
Write-Color "  |                                                           |" Green
Write-Color "  +===========================================================+" Green
Write-Host ""

Write-Color "  Configuration" White
Write-Color ("  " + ("-" * 42)) DarkGray
$modeLabel = if ($MultiUser -eq "true") { "Multi-user (JWT auth)" } else { "Single-user" }
Write-Host "  Mode:       $modeLabel"
Write-Host "  Provider:   $ProviderName"
Write-Host "  Model:      $DefaultModel"
Write-Host "  Config:     $ConfigFile"
Write-Host "  Venv:       $VenvDir"
Write-Host ""

Write-Color "  Next steps" White
Write-Color ("  " + ("-" * 42)) DarkGray
Write-Color "  1. Reload your PowerShell profile (required once):" Yellow
Write-Color "         . `$PROFILE" Cyan
Write-Host ""
Write-Color "  2. Run graphclaw:" White
Write-Color "         graphclaw" Cyan
Write-Host ""
Write-Color "  Later, manage updates safely with:" DarkGray
Write-Color "         graphclaw update" White
Write-Color "         graphclaw rollback" White
Write-Host ""
if ($MultiUser -eq "true") {
    Write-Color "  Start as HTTP server:" White
    Write-Color "      jac start graphclaw/main.jac" Cyan
    Write-Host ""
}
Write-Color "  Edit config anytime:" White
Write-Color "      notepad $ConfigFile" Cyan
Write-Host ""
