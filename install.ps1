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

# ask_optional — empty input is fine
function ask_optional {
    param([string]$Prompt)
    Write-Host "  [?] ${Prompt} (optional, Enter to skip): " -ForegroundColor Cyan -NoNewline
    $r = Read-Host
    return $r
}

# ask_required — loops until non-empty
function ask_required {
    param([string]$Prompt)
    while ($true) {
        Write-Host "  [?] ${Prompt}: " -ForegroundColor Cyan -NoNewline
        $r = Read-Host
        if ($r) { return $r }
        Write-Color "     This field is required. Please enter a value." Red
    }
}

# ask_choice — loops until input matches one of the valid values
function ask_choice {
    param([string]$Prompt, [string[]]$Valid, [string]$Default)
    while ($true) {
        Write-Host "  [?] ${Prompt} [${Default}]: " -ForegroundColor Cyan -NoNewline
        $r = Read-Host
        if (-not $r) { $r = $Default }
        if ($Valid -contains $r) { return $r }
        Write-Color "     Invalid choice '$r'. Enter one of: $($Valid -join ', ')" Red
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

$Python = $null
foreach ($cmd in @("python3.13","python3.12","python3","python","py")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        try {
            $ver = & $cmd -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
            if ($ver -match '^\d+\.\d+$') {
                $parts = $ver.Split(".")
                if ([int]$parts[0] -ge 3 -and [int]$parts[1] -ge 12) {
                    $Python = $cmd
                    break
                }
            }
        } catch { }
    }
}

if (-not $Python) {
    Write-Host ""
    fail "Python 3.12+ not found. Download from https://python.org/downloads"
}

$pyVer = & $Python --version 2>&1
ok "Using $pyVer"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 -- Clone / locate repo
# ─────────────────────────────────────────────────────────────────────────────

Step "Locating source"

$ScriptDir = $null
try { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch {}
$CloneDir = "$env:TEMP\graphclaw"

if (-not $ScriptDir -or -not (Test-Path "$ScriptDir\pyproject.toml" -ErrorAction SilentlyContinue)) {
    info "Cloning graphclaw repository..."
    if (Get-Command git -ErrorAction SilentlyContinue) {
        if (Test-Path $CloneDir) { Remove-Item -Recurse -Force $CloneDir }
        git clone --depth 1 https://github.com/zero-abd/graphclaw $CloneDir -q 2>$null
        ok "Cloned to $CloneDir"
        $ScriptDir = $CloneDir
    } else {
        fail "git is required. Install Git for Windows from https://git-scm.com and retry."
    }
} else {
    ok "Using source at $ScriptDir"
}

$GraphclawDir = "$env:USERPROFILE\.graphclaw"
$WorkspaceDir = "$GraphclawDir\workspace"
$ConfigFile   = "$GraphclawDir\config.json"
$EnvFile      = "$GraphclawDir\.env"

New-Item -ItemType Directory -Force -Path "$WorkspaceDir\memory" | Out-Null
New-Item -ItemType Directory -Force -Path "$WorkspaceDir\sessions" | Out-Null
New-Item -ItemType Directory -Force -Path "$WorkspaceDir\skills\installed" | Out-Null
New-Item -ItemType Directory -Force -Path "$GraphclawDir\skills\installed" | Out-Null

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 -- Install dependencies
# ─────────────────────────────────────────────────────────────────────────────

Step "Installing dependencies"

$ErrorActionPreference = "Continue"

info "Upgrading pip..."
& $Python -m pip install --upgrade pip -q 2>&1 | Out-Null

info "Installing jaclang (Jac runtime)..."
& $Python -m pip install "jaclang>=0.7.0" -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = "Stop"; fail "Failed to install jaclang." }

info "Installing graphclaw..."
& $Python -m pip install -e $ScriptDir -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = "Stop"; fail "Failed to install graphclaw." }

$ErrorActionPreference = "Stop"

$JacCmd = Get-Command jac -ErrorAction SilentlyContinue
if ($JacCmd) {
    $JacVer = (& jac --version 2>&1) | Select-Object -First 1
    ok "jac CLI ready ($JacVer)"
} else {
    warn "jac not found in PATH -- restart your terminal after install"
}
ok "graphclaw package installed"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 -- Deployment mode
# ─────────────────────────────────────────────────────────────────────────────

Step "Deployment mode"

Write-Color "  How will you run Graphclaw?" DarkGray
Write-Host ""
Write-Color "    1)  Single-user   -- personal agent, no auth required" White
Write-Color "    2)  Multi-user    -- hosted platform, JWT auth, per-user memory" White
Write-Host ""

$ModeChoice = ask_choice "Select mode [1/2]" @("1","2") "1"
$MultiUser  = "false"
$JwtSecret  = ""

if ($ModeChoice -eq "2") {
    $MultiUser = "true"
    ok "Multi-user mode selected"
    $JwtSecret = ask_optional "Secret key for JWT (blank to auto-generate)"
    if (-not $JwtSecret) {
        $JwtSecret = & $Python -c "import secrets; print(secrets.token_hex(32))"
        warn "Generated JWT secret (save this!): $JwtSecret"
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
Write-Color "    1)  OpenRouter   -- one key, all models  (recommended)" White
Write-Color "    2)  Anthropic    -- Claude direct" White
Write-Color "    3)  OpenAI       -- GPT-4o / GPT-4.1" White
Write-Color "    4)  Ollama       -- local models, no key needed" White
Write-Color "    5)  Skip         -- configure manually later" White
Write-Host ""

$ProviderChoice = ask_choice "Select provider [1-5]" @("1","2","3","4","5") "1"
$OpenrouterKey  = ""; $AnthropicKey = ""; $OpenaiKey = ""
$DefaultModel   = "openrouter/anthropic/claude-sonnet-4-6"
$ProviderName   = "OpenRouter"

switch ($ProviderChoice) {
    "1" {
        $OpenrouterKey = ask_required "OpenRouter API key"
        ok "OpenRouter configured"
    }
    "2" {
        $AnthropicKey = ask_required "Anthropic API key"
        $DefaultModel = "anthropic/claude-sonnet-4-6"
        $ProviderName = "Anthropic"
        ok "Anthropic configured"
    }
    "3" {
        $OpenaiKey = ask_required "OpenAI API key"
        $DefaultModel = "openai/gpt-4o"
        $ProviderName = "OpenAI"
        ok "OpenAI configured"
    }
    "4" {
        $DefaultModel = "ollama/llama3"
        $ProviderName = "Ollama"
        ok "Ollama -- ensure ollama is running locally"
    }
    "5" {
        ok "Skipped -- edit ~/.graphclaw/config.json to set your key"
        $ProviderName = "(not set)"
    }
}

Write-Host ""
Write-Color "  Messaging channels -- leave blank to skip:" DarkGray
Write-Host ""
$TgToken     = ask_optional "Telegram bot token"
$DcToken     = ask_optional "Discord bot token"
$SlBotToken  = ask_optional "Slack bot token"
$SlAppToken  = ""
if ($SlBotToken) {
    $SlAppToken = ask_required "Slack app token (required when bot token is set)"
}

Write-Host ""
Write-Color "  DevOps skill API keys -- leave blank to skip:" DarkGray
Write-Host ""
$Base44Key   = ask_optional "Base44 API key"
$LoveableKey = ask_optional "Loveable API key"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 -- Write config & shell integration
# ─────────────────────────────────────────────────────────────────────────────

Step "Writing config & shell integration"

$tgEnabled = if ($TgToken)    { "true" } else { "false" }
$dcEnabled = if ($DcToken)    { "true" } else { "false" }
$slEnabled = if ($SlBotToken) { "true" } else { "false" }

$EscWorkspace = $WorkspaceDir -replace '\\','\\'
$EscSkillPath = ($GraphclawDir -replace '\\','\\') + "\\skills\\installed"

$ConfigJson = @"
{
  "workspace": "$EscWorkspace",
  "multi_user": $MultiUser,
  "agents": {
    "model": "$DefaultModel",
    "max_tokens": 8192,
    "temperature": 0.7,
    "max_tool_iterations": 200,
    "dream": { "enabled": true, "interval_hours": 2 }
  },
  "providers": {
    "default_provider": "openrouter",
    "openrouter": { "api_key": "$OpenrouterKey", "base_url": "https://openrouter.ai/api/v1" },
    "anthropic": { "api_key": "$AnthropicKey" },
    "openai": { "api_key": "$OpenaiKey" }
  },
  "channels": {
    "telegram": { "enabled": $tgEnabled, "bot_token": "$TgToken" },
    "discord": { "enabled": $dcEnabled, "bot_token": "$DcToken" },
    "slack": { "enabled": $slEnabled, "bot_token": "$SlBotToken", "app_token": "$SlAppToken" },
    "email": { "enabled": false },
    "whatsapp": { "enabled": false }
  },
  "auth": { "enabled": $MultiUser, "secret_key": "$JwtSecret" },
  "skills": {
    "registry_url": "https://clawhub.ai/api/v1",
    "installed_path": "$EscSkillPath"
  }
}
"@
Set-Content -Path $ConfigFile -Value $ConfigJson -Encoding UTF8
ok "Config written to $ConfigFile"

# .env
$envLines = @("# Graphclaw environment", "GRAPHCLAW_CONFIG_PATH=$ConfigFile")
if ($OpenrouterKey) { $envLines += "OPENROUTER_API_KEY=$OpenrouterKey" }
if ($AnthropicKey)  { $envLines += "ANTHROPIC_API_KEY=$AnthropicKey" }
if ($OpenaiKey)     { $envLines += "OPENAI_API_KEY=$OpenaiKey" }
if ($Base44Key)     { $envLines += "BASE44_API_KEY=$Base44Key" }
if ($LoveableKey)   { $envLines += "LOVEABLE_API_KEY=$LoveableKey" }
$envLines -join "`n" | Set-Content -Path $EnvFile -Encoding UTF8
ok ".env written to $EnvFile"

# run.bat
$RunBat = "$GraphclawDir\run.bat"
@"
@echo off
for /f "usebackq tokens=*" %%i in ("$EnvFile") do (
    echo %%i | findstr /v "^#" >nul && set "%%i"
)
jac run "$ScriptDir\graphclaw\main.jac" %*
"@ | Set-Content -Path $RunBat -Encoding UTF8
ok "Startup script: $RunBat"

# PowerShell profile alias
$ProfileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null }

$AliasLine = "function graphclaw { & '$RunBat' @args }"
if (Test-Path $PROFILE) {
    $existing = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($existing -and $existing -match "function graphclaw") {
        ok "'graphclaw' already in PowerShell profile"
    } else {
        Add-Content -Path $PROFILE -Value "`n$AliasLine"
        ok "Added 'graphclaw' function to PowerShell profile"
    }
} else {
    Set-Content -Path $PROFILE -Value $AliasLine -Encoding UTF8
    ok "Created PowerShell profile with 'graphclaw' function"
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
Write-Host "  Workspace:  $WorkspaceDir"
Write-Host ""

Write-Color "  Next steps" White
Write-Color ("  " + ("-" * 42)) DarkGray
Write-Color "  Reload your PowerShell profile:" White
Write-Color '      . $PROFILE' Cyan
Write-Host ""
Write-Color "  Start in CLI mode:" White
Write-Color "      graphclaw" Cyan
Write-Host ""
if ($MultiUser -eq "true") {
    Write-Color "  Start as HTTP server:" White
    Write-Color "      jac start graphclaw/main.jac" Cyan
    Write-Host ""
}
Write-Color "  Edit config anytime:" White
Write-Color "      notepad ~/.graphclaw/config.json" Cyan
Write-Host ""
