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
        fail "git is required. Install from https://git-scm.com and retry."
    }
} else {
    ok "Using source at $ScriptDir"
}

$GraphclawDir = "$env:USERPROFILE\.graphclaw"
$WorkspaceDir = "$GraphclawDir\workspace"
$ConfigFile   = "$GraphclawDir\config.json"
$EnvFile      = "$GraphclawDir\.env"
$VenvDir      = "$GraphclawDir\venv"

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
& $VenvPip install "jaclang>=0.7.0" -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = "Stop"; fail "Failed to install jaclang." }

info "Installing graphclaw..."
& $VenvPip install -e $ScriptDir -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = "Stop"; fail "Failed to install graphclaw." }

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
Write-Color "    1)  OpenRouter   -- one key, access to all major models  (recommended)" White
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
        hint "Get your key at: openrouter.ai/keys"
        $OpenrouterKey = ask_required "OpenRouter API key"
        ok "OpenRouter configured"
    }
    "2" {
        hint "Get your key at: console.anthropic.com/settings/keys"
        $AnthropicKey = ask_required "Anthropic API key"
        $DefaultModel = "anthropic/claude-sonnet-4-6"
        $ProviderName = "Anthropic"
        ok "Anthropic configured"
    }
    "3" {
        hint "Get your key at: platform.openai.com/api-keys"
        $OpenaiKey = ask_required "OpenAI API key"
        $DefaultModel = "openai/gpt-4o"
        $ProviderName = "OpenAI"
        ok "OpenAI configured"
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
Write-Color "  Messaging channels (all optional -- skip any by pressing Enter):" DarkGray
Write-Host ""

hint "Telegram: open Telegram, message @BotFather, send /newbot"
$TgToken = ask_optional "Telegram bot token"

hint "Discord: discord.com/developers/applications -> New App -> Bot -> Reset Token"
$DcToken = ask_optional "Discord bot token"

hint "Slack: api.slack.com/apps -> Create App -> OAuth & Permissions -> Bot Token"
$SlBotToken = ask_optional "Slack bot token (xoxb-...)"
$SlAppToken = ""
if ($SlBotToken) {
    hint "Slack app token: api.slack.com/apps -> Your App -> Basic Information -> App-Level Tokens"
    $SlAppToken = ask_required "Slack app token (xapp-...)"
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
    "discord":  { "enabled": $dcEnabled, "bot_token": "$DcToken" },
    "slack":    { "enabled": $slEnabled, "bot_token": "$SlBotToken", "app_token": "$SlAppToken" },
    "email":    { "enabled": false },
    "whatsapp": { "enabled": false }
  },
  "auth": { "enabled": $MultiUser, "secret_key": "$JwtSecret" },
  "skills": {
    "registry_url": "https://clawhub.ai/api/v1",
    "installed_path": "$EscSkillPath"
  }
}
"@
Write-NoBom $ConfigFile $ConfigJson
ok "Config written to $ConfigFile"

# .env — written without BOM so batch/Python can read it cleanly
$envLines = @("# Graphclaw environment", "GRAPHCLAW_CONFIG_PATH=$ConfigFile")
if ($OpenrouterKey) { $envLines += "OPENROUTER_API_KEY=$OpenrouterKey" }
if ($AnthropicKey)  { $envLines += "ANTHROPIC_API_KEY=$AnthropicKey" }
if ($OpenaiKey)     { $envLines += "OPENAI_API_KEY=$OpenaiKey" }
if ($Base44Key)     { $envLines += "BASE44_API_KEY=$Base44Key" }
if ($LoveableKey)   { $envLines += "LOVEABLE_API_KEY=$LoveableKey" }
Write-NoBom $EnvFile ($envLines -join "`r`n")
ok ".env written to $EnvFile"

# run.bat — activates venv, sets config path, runs jac
$RunBat = "$GraphclawDir\run.bat"
$MainJac = "$ScriptDir\graphclaw\main.jac"
$RunBatContent = "@echo off`r`ncall `"$VenvDir\Scripts\activate.bat`"`r`nset GRAPHCLAW_CONFIG_PATH=$ConfigFile`r`njac run `"$MainJac`" %*`r`n"
Write-NoBom $RunBat $RunBatContent
ok "Startup script: $RunBat"

# run.ps1 — PowerShell equivalent (activates venv, runs jac)
$RunPs1 = "$GraphclawDir\run.ps1"
$RunPs1Content = "& `"$VenvDir\Scripts\Activate.ps1`"`r`n`$env:GRAPHCLAW_CONFIG_PATH = `"$ConfigFile`"`r`njac run `"$MainJac`" @args`r`n"
Write-NoBom $RunPs1 $RunPs1Content
ok "PowerShell startup: $RunPs1"

# PowerShell profile function
$ProfileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null }

$AliasLine = "function graphclaw { & '$RunPs1' @args }"
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
Write-Color "     Or run directly without reloading:" DarkGray
Write-Color "         $RunBat" White
Write-Host ""
if ($MultiUser -eq "true") {
    Write-Color "  Start as HTTP server:" White
    Write-Color "      jac start graphclaw/main.jac" Cyan
    Write-Host ""
}
Write-Color "  Edit config anytime:" White
Write-Color "      notepad $ConfigFile" Cyan
Write-Host ""
