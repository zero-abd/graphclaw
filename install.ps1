# ─────────────────────────────────────────────────────────────────────────────
#  Graphclaw Windows Installer (PowerShell)
#  Usage (one-liner, run in PowerShell as Administrator):
#    irm https://raw.githubusercontent.com/zero-abd/graphclaw/main/install.ps1 | iex
#  Or locally:
#    .\install.ps1
# ─────────────────────────────────────────────────────────────────────────────

#Requires -Version 5.1
$ErrorActionPreference = "Stop"

# ── Colors ────────────────────────────────────────────────────────────────────
function Write-Color {
    param([string]$Text, [string]$Color = "White", [switch]$NoNewline)
    if ($NoNewline) { Write-Host $Text -ForegroundColor $Color -NoNewline }
    else            { Write-Host $Text -ForegroundColor $Color }
}

function ok   { Write-Color "  [OK] $args" Green }
function warn { Write-Color "  [!!] $args" Yellow }
function info { Write-Color "  ... $args"  DarkGray }
function fail { Write-Color "  [X] $args"  Red; exit 1 }
function ask  {
    param([string]$Prompt, [string]$Default = "")
    if ($Default) { Write-Host "  [?] $Prompt [$Default]: " -ForegroundColor Cyan -NoNewline }
    else          { Write-Host "  [?] $Prompt: " -ForegroundColor Cyan -NoNewline }
    $r = Read-Host
    if (-not $r -and $Default) { $r = $Default }
    return $r
}

# ── Banner ────────────────────────────────────────────────────────────────────

Clear-Host
Write-Color ""
Write-Color "  ╔═══════════════════════════════════════════════════════════╗" Cyan
Write-Color "  ║                                                           ║" Cyan
Write-Color "  ║    ██████╗ ██████╗  █████╗ ██████╗ ██╗  ██╗              ║" Cyan
Write-Color "  ║   ██╔════╝ ██╔══██╗██╔══██╗██╔══██╗██║  ██║              ║" Cyan
Write-Color "  ║   ██║  ███╗██████╔╝███████║██████╔╝███████║              ║" Cyan
Write-Color "  ║   ██║   ██║██╔══██╗██╔══██║██╔═══╝ ██╔══██║              ║" Cyan
Write-Color "  ║   ╚██████╔╝██║  ██║██║  ██║██║     ██║  ██║              ║" Cyan
Write-Color "  ║    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝  v0.1.0     ║" Cyan
Write-Color "  ║                                                           ║" Cyan
Write-Color "  ║   Graph-native multi-agent AI platform in Jac             ║" DarkGray
Write-Color "  ║                                                           ║" Cyan
Write-Color "  ╚═══════════════════════════════════════════════════════════╝" Cyan
Write-Color ""

$StepN = 0
$TotalSteps = 6

function Step {
    param([string]$Name)
    $script:StepN++
    Write-Color ""
    Write-Color "  [$($script:StepN)/$TotalSteps] $Name" White
    Write-Color ("  " + ("─" * 60)) DarkGray
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Python
# ─────────────────────────────────────────────────────────────────────────────

Step "Checking Python"

$Python = $null
foreach ($cmd in @("python3.13","python3.12","python3","python","py")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        $ver = & $cmd -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        if ($ver) {
            $parts = $ver.Split(".")
            if ([int]$parts[0] -ge 3 -and [int]$parts[1] -ge 12) {
                $Python = $cmd
                break
            }
        }
    }
}

if (-not $Python) {
    Write-Color ""
    fail "Python 3.12+ not found. Download from https://python.org/downloads"
}

$pyVer = & $Python --version 2>&1
ok "Using $pyVer"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Clone / locate repo
# ─────────────────────────────────────────────────────────────────────────────

Step "Locating source"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path 2>$null
$CloneDir  = "$env:TEMP\graphclaw"

if (-not $ScriptDir -or -not (Test-Path "$ScriptDir\pyproject.toml")) {
    info "Cloning graphclaw repository..."
    if (Get-Command git -ErrorAction SilentlyContinue) {
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
# STEP 3 — Install dependencies
# ─────────────────────────────────────────────────────────────────────────────

Step "Installing dependencies"

info "Upgrading pip..."
& $Python -m pip install --upgrade pip -q

info "Installing jaclang (Jac runtime)..."
& $Python -m pip install "jaclang>=0.7.0" -q
if ($LASTEXITCODE -ne 0) { fail "Failed to install jaclang. Check your internet connection and try again." }

info "Installing graphclaw..."
& $Python -m pip install -e $ScriptDir -q
if ($LASTEXITCODE -ne 0) { fail "Failed to install graphclaw package." }

$JacCmd = Get-Command jac -ErrorAction SilentlyContinue
if ($JacCmd) {
    $JacVer = & jac --version 2>&1 | Select-Object -First 1
    ok "jac CLI ready  ($JacVer)"
} else {
    warn "jac not found in PATH — you may need to restart your terminal"
}
ok "graphclaw package installed"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Deployment mode
# ─────────────────────────────────────────────────────────────────────────────

Step "Deployment mode"

Write-Color "  How will you run Graphclaw?" DarkGray
Write-Color ""
Write-Color "    1)  Single-user   — personal agent, no auth required" White
Write-Color "    2)  Multi-user    — hosted platform, JWT auth, per-user memory graphs" White
Write-Color ""

$ModeChoice = ask "Select mode [1/2]" "1"
$MultiUser  = "false"
$JwtSecret  = ""

if ($ModeChoice -eq "2") {
    $MultiUser = "true"
    ok "Multi-user mode selected"
    $JwtSecret = ask "Secret key for JWT (leave blank to auto-generate)" ""
    if (-not $JwtSecret) {
        $JwtSecret = & $Python -c "import secrets; print(secrets.token_hex(32))"
        warn "Generated JWT secret (save this!):  $JwtSecret"
    }
} else {
    ok "Single-user mode selected"
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — LLM provider & channels
# ─────────────────────────────────────────────────────────────────────────────

Step "LLM provider & channels"

Write-Color "  Choose your default LLM provider:" DarkGray
Write-Color ""
Write-Color "    1)  OpenRouter   — one key, access to every major model  (recommended)" White
Write-Color "    2)  Anthropic    — Claude direct" White
Write-Color "    3)  OpenAI       — GPT-4o / GPT-4.1" White
Write-Color "    4)  Ollama       — local models, no API key needed" White
Write-Color "    5)  Skip         — configure manually later" White
Write-Color ""

$ProviderChoice = ask "Select provider [1-5]" "1"
$OpenrouterKey  = ""; $AnthropicKey = ""; $OpenaiKey = ""
$DefaultModel   = "openrouter/anthropic/claude-sonnet-4-6"
$ProviderName   = "OpenRouter"

switch ($ProviderChoice) {
    "1" { $OpenrouterKey = ask "OpenRouter API key" ""; ok "OpenRouter configured" }
    "2" { $AnthropicKey  = ask "Anthropic API key"  ""; $DefaultModel = "anthropic/claude-sonnet-4-6"; $ProviderName = "Anthropic"; ok "Anthropic configured" }
    "3" { $OpenaiKey     = ask "OpenAI API key"     ""; $DefaultModel = "openai/gpt-4o"; $ProviderName = "OpenAI"; ok "OpenAI configured" }
    "4" { $DefaultModel  = "ollama/llama3"; $ProviderName = "Ollama"; ok "Ollama selected — ensure ollama is running locally" }
    "5" { ok "Skipped — edit $ConfigFile to set your key"; $ProviderName = "(not set)" }
}

Write-Color ""
Write-Color "  Messaging channels — leave blank to skip:" DarkGray
Write-Color ""
$TgToken     = ask "Telegram bot token" ""
$DcToken     = ask "Discord bot token " ""
$SlBotToken  = ask "Slack bot token   " ""
$SlAppToken  = ask "Slack app token   " ""

Write-Color ""
Write-Color "  DevOps skill API keys — leave blank to skip:" DarkGray
Write-Color ""
$Base44Key   = ask "Base44 API key  " ""
$LoveableKey = ask "Loveable API key" ""

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Write config & shell integration
# ─────────────────────────────────────────────────────────────────────────────

Step "Writing config & shell integration"

$tgEnabled = if ($TgToken)    { "true"  } else { "false" }
$dcEnabled = if ($DcToken)    { "true"  } else { "false" }
$slEnabled = if ($SlBotToken) { "true"  } else { "false" }

$ConfigJson = @"
{
  "workspace": "$($WorkspaceDir -replace '\\','\\')",
  "multi_user": $MultiUser,
  "agents": {
    "model": "$DefaultModel",
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
      "api_key": "$OpenrouterKey",
      "base_url": "https://openrouter.ai/api/v1"
    },
    "anthropic": {"api_key": "$AnthropicKey"},
    "openai":    {"api_key": "$OpenaiKey"}
  },
  "channels": {
    "telegram": {
      "enabled": $tgEnabled,
      "bot_token": "$TgToken"
    },
    "discord": {
      "enabled": $dcEnabled,
      "bot_token": "$DcToken"
    },
    "slack": {
      "enabled": $slEnabled,
      "bot_token": "$SlBotToken",
      "app_token": "$SlAppToken"
    },
    "email":    {"enabled": false},
    "whatsapp": {"enabled": false}
  },
  "auth": {
    "enabled": $MultiUser,
    "secret_key": "$JwtSecret"
  },
  "skills": {
    "registry_url": "https://clawhub.ai/api/v1",
    "installed_path": "$($GraphclawDir -replace '\\','\\')\\skills\\installed"
  }
}
"@
Set-Content -Path $ConfigFile -Value $ConfigJson -Encoding UTF8
ok "Config written to $ConfigFile"

$EnvContent = @"
# Graphclaw environment — loaded at startup
GRAPHCLAW_CONFIG_PATH=$ConfigFile
$(if ($OpenrouterKey) { "OPENROUTER_API_KEY=$OpenrouterKey" })
$(if ($AnthropicKey)  { "ANTHROPIC_API_KEY=$AnthropicKey"   })
$(if ($OpenaiKey)     { "OPENAI_API_KEY=$OpenaiKey"         })
$(if ($Base44Key)     { "BASE44_API_KEY=$Base44Key"         })
$(if ($LoveableKey)   { "LOVEABLE_API_KEY=$LoveableKey"     })
"@
Set-Content -Path $EnvFile -Value $EnvContent -Encoding UTF8
ok ".env written to $EnvFile"

# run.bat for Windows
$RunBat = "$GraphclawDir\run.bat"
$RunBatContent = @"
@echo off
for /f "tokens=*" %%i in ('type "$EnvFile" ^| findstr /v "^#" ^| findstr /v "^$"') do set %%i
jac run "$ScriptDir\graphclaw\main.jac" %*
"@
Set-Content -Path $RunBat -Value $RunBatContent -Encoding UTF8
ok "Startup script: $RunBat"

# Add to user PATH via PowerShell profile
$ProfileDir = Split-Path $PROFILE -Parent
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

$AliasLine = "function graphclaw { & `"$RunBat`" `$args }"
if (Test-Path $PROFILE) {
    $existing = Get-Content $PROFILE -Raw
    if ($existing -notmatch "function graphclaw") {
        Add-Content -Path $PROFILE -Value "`n$AliasLine"
        ok "Added 'graphclaw' function to $PROFILE"
    } else {
        ok "'graphclaw' already in PowerShell profile"
    }
} else {
    Set-Content -Path $PROFILE -Value $AliasLine -Encoding UTF8
    ok "Created PowerShell profile with 'graphclaw' function"
}

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────

Write-Color ""
Write-Color "  ╔═══════════════════════════════════════════════════════════╗" Green
Write-Color "  ║                                                           ║" Green
Write-Color "  ║   [OK]  Graphclaw installed successfully!                 ║" Green
Write-Color "  ║                                                           ║" Green
Write-Color "  ╚═══════════════════════════════════════════════════════════╝" Green
Write-Color ""

Write-Color "  Configuration" White
Write-Color ("  " + ("─" * 42)) DarkGray
Write-Color ("  Mode:      " + $(if ($MultiUser -eq "true") { "Multi-user (JWT auth enabled)" } else { "Single-user" })) White
Write-Color "  Provider:   $ProviderName"   White
Write-Color "  Model:      $DefaultModel"   White
Write-Color "  Config:     $ConfigFile"     White
Write-Color "  Workspace:  $WorkspaceDir"   White
Write-Color ""

Write-Color "  Next steps" White
Write-Color ("  " + ("─" * 42)) DarkGray
Write-Color "  Reload your PowerShell profile:" White
Write-Color "      . `$PROFILE" Cyan
Write-Color ""
Write-Color "  Start in CLI mode:" White
Write-Color "      graphclaw      (after reloading profile)" Cyan
Write-Color "      $RunBat  (works immediately)" Cyan
Write-Color ""
if ($MultiUser -eq "true") {
    Write-Color "  Start as HTTP server:" White
    Write-Color "      jac start $ScriptDir\graphclaw\main.jac" Cyan
    Write-Color "      => http://localhost:8000/docs" DarkGray
    Write-Color ""
}
Write-Color "  Edit config anytime:" White
Write-Color "      notepad `$env:USERPROFILE\.graphclaw\config.json" Cyan
Write-Color ""
