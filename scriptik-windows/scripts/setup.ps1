# Scriptik Windows Setup - creates venv, installs Whisper, downloads model

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  Scriptik Windows Setup" -ForegroundColor Cyan
Write-Host "  ======================" -ForegroundColor Cyan
Write-Host ""

# --- Check Python 3 ---
$python = $null
foreach ($cmd in @("python", "python3")) {
    try {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python 3") {
            $python = $cmd
            break
        }
    } catch {}
}

if (-not $python) {
    Write-Host "ERROR: Python 3 is required." -ForegroundColor Red
    Write-Host "Download from https://www.python.org/downloads/" -ForegroundColor Yellow
    exit 1
}
Write-Host "[ok] Python found: $(& $python --version 2>&1)" -ForegroundColor Green

# --- Check ffmpeg ---
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "WARNING: ffmpeg not found. Whisper needs it for audio processing." -ForegroundColor Yellow
    Write-Host "Install via: winget install ffmpeg" -ForegroundColor Yellow
    Write-Host "Or download from: https://ffmpeg.org/download.html" -ForegroundColor Yellow
    Write-Host ""
}
else {
    Write-Host "[ok] ffmpeg found" -ForegroundColor Green
}

# --- Setup paths ---
$dataDir = Join-Path $env:APPDATA "scriptik"
$venvDir = Join-Path $dataDir "venv"
$configDir = Join-Path $env:APPDATA "scriptik"
$configFile = Join-Path $configDir "config"

# --- Create venv ---
if (-not (Test-Path $venvDir)) {
    Write-Host ""
    Write-Host "Creating Python virtual environment..." -ForegroundColor Cyan
    & $python -m venv $venvDir
    Write-Host "[ok] Virtual environment created at $venvDir" -ForegroundColor Green
}
else {
    Write-Host "[ok] Virtual environment already exists" -ForegroundColor Green
}

# --- Activate and install dependencies ---
$venvPython = Join-Path $venvDir "Scripts\python.exe"

Write-Host ""
Write-Host "Installing openai-whisper (this may take a few minutes)..." -ForegroundColor Cyan
& $venvPython -m pip install --upgrade pip --quiet
& $venvPython -m pip install openai-whisper numpy --quiet

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to install dependencies." -ForegroundColor Red
    exit 1
}
Write-Host "[ok] openai-whisper installed" -ForegroundColor Green

# --- Create default config ---
if (-not (Test-Path $configFile)) {
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    @"
WHISPER_MODEL=medium
PAUSE_THRESHOLD=1.5
INITIAL_PROMPT=
LANGUAGE=auto
HOTKEY=Ctrl+Shift+R
"@ | Set-Content -Path $configFile -Encoding UTF8
    Write-Host "[ok] Default config created at $configFile" -ForegroundColor Green
}
else {
    Write-Host "[ok] Config already exists at $configFile" -ForegroundColor Green
}

# --- Download Whisper model ---
Write-Host ""
Write-Host "Downloading Whisper model (this may take a while on first run)..." -ForegroundColor Cyan

# Read model from config
$model = "medium"
if (Test-Path $configFile) {
    $configContent = Get-Content $configFile
    foreach ($line in $configContent) {
        if ($line -match "^WHISPER_MODEL=(.+)$") {
            $model = $Matches[1].Trim().Trim('"')
        }
    }
}

& $venvPython -c "import whisper; whisper.load_model('$model')"

if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Model download may have failed. It will retry on first use." -ForegroundColor Yellow
}
else {
    Write-Host "[ok] Whisper model '$model' downloaded" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "  You can now launch Scriptik." -ForegroundColor Cyan
Write-Host ""
