# Scriptik Windows Setup Script
# Creates a Python virtual environment and installs openai-whisper + dependencies.

$ErrorActionPreference = "Stop"

$VenvDir = "$env:LOCALAPPDATA\scriptik\venv"

Write-Host "[1/4] Creating Python virtual environment at $VenvDir..."
if (Test-Path $VenvDir) {
    Write-Host "  Virtual environment already exists. Updating..."
} else {
    python -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create virtual environment. Is Python installed?" -ForegroundColor Red
        Write-Host "  Install Python from https://python.org or via: winget install Python.Python.3.11"
        exit 1
    }
}

# Activate venv
$ActivateScript = "$VenvDir\Scripts\Activate.ps1"
if (!(Test-Path $ActivateScript)) {
    Write-Host "ERROR: Venv activation script not found at $ActivateScript" -ForegroundColor Red
    exit 1
}
& $ActivateScript

Write-Host "[2/4] Installing/upgrading pip..."
python -m pip install --upgrade pip --quiet

Write-Host "[3/4] Installing openai-whisper..."
pip install openai-whisper --quiet

# Check for NVIDIA GPU and install CUDA-enabled PyTorch if available
Write-Host "[4/4] Checking GPU and installing PyTorch..."
try {
    $gpuInfo = (Get-CimInstance Win32_VideoController).Name
    if ($gpuInfo -match "NVIDIA") {
        Write-Host "  NVIDIA GPU detected. Installing PyTorch with CUDA support..."
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 --quiet
    } else {
        Write-Host "  No NVIDIA GPU detected. Installing CPU-only PyTorch..."
        pip install torch torchvision torchaudio --quiet
    }
} catch {
    Write-Host "  Could not detect GPU. Installing CPU-only PyTorch..."
    pip install torch torchvision torchaudio --quiet
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
Write-Host "  Python path: $VenvDir\Scripts\python.exe"
Write-Host ""
Write-Host "To test: & '$VenvDir\Scripts\python.exe' -c 'import whisper; print(whisper.__version__)'"
