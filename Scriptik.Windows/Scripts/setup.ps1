# Scriptik Windows Setup Script
# Creates a Python virtual environment and installs openai-whisper + dependencies.

$ErrorActionPreference = "Stop"

$VenvDir = "$env:LOCALAPPDATA\scriptik\venv"
$VenvPython = "$VenvDir\Scripts\python.exe"
$VenvPip = "$VenvDir\Scripts\pip.exe"

Write-Host "[1/4] Creating Python virtual environment at $VenvDir..."
if (Test-Path $VenvDir) {
    Write-Host "  Virtual environment already exists. Updating..."
} else {
    # Try 'python', then 'python3', then 'py' to find a working interpreter
    $pythonCmd = $null
    foreach ($cmd in @("python", "python3", "py")) {
        try {
            $ver = & $cmd --version 2>&1
            if ($ver -match "Python 3\.") {
                $pythonCmd = $cmd
                Write-Host "  Found $ver via '$cmd'"
                break
            }
        } catch { }
    }

    if (-not $pythonCmd) {
        Write-Host "ERROR: Python 3 not found. Is Python installed?" -ForegroundColor Red
        Write-Host "  Install Python from https://python.org or via: winget install Python.Python.3.11"
        exit 1
    }

    & $pythonCmd -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create virtual environment." -ForegroundColor Red
        exit 1
    }
}

# Verify venv python exists
if (!(Test-Path $VenvPython)) {
    Write-Host "ERROR: Venv python not found at $VenvPython" -ForegroundColor Red
    exit 1
}

# Use fully-qualified paths — do not rely on PATH/activation
Write-Host "[2/4] Installing/upgrading pip..."
& $VenvPython -m pip install --upgrade pip --quiet

Write-Host "[3/4] Installing openai-whisper..."
& $VenvPip install openai-whisper --quiet

# Check for NVIDIA GPU and install CUDA-enabled PyTorch if available
Write-Host "[4/4] Checking GPU and installing PyTorch..."
try {
    $gpuInfo = (Get-CimInstance Win32_VideoController).Name
    if ($gpuInfo -match "NVIDIA") {
        Write-Host "  NVIDIA GPU detected. Installing PyTorch with CUDA support..."
        & $VenvPip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 --quiet
    } else {
        Write-Host "  No NVIDIA GPU detected. Installing CPU-only PyTorch..."
        & $VenvPip install torch torchvision torchaudio --quiet
    }
} catch {
    Write-Host "  Could not detect GPU. Installing CPU-only PyTorch..."
    & $VenvPip install torch torchvision torchaudio --quiet
}

# Check for ffmpeg
Write-Host ""
$ffmpegPath = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($ffmpegPath) {
    Write-Host "[ok] ffmpeg found at $($ffmpegPath.Source)" -ForegroundColor Green
} else {
    Write-Host "[!] ffmpeg not found. Whisper requires ffmpeg for audio processing." -ForegroundColor Yellow
    Write-Host "    Install via: winget install Gyan.FFmpeg"
    Write-Host "    Or download from: https://ffmpeg.org/download.html"
}

Write-Host ""
Write-Host "[ok] Setup complete!" -ForegroundColor Green
Write-Host "  Python venv: $VenvDir"
Write-Host "  Python path: $VenvPython"
Write-Host ""
Write-Host "To test: & '$VenvPython' -c 'import whisper; print(whisper.__version__)'"
