# Scriptik Windows Build Script
# Builds the application using dotnet publish.

$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$OutputDir = Join-Path $ProjectDir "publish"

Write-Host "Building Scriptik for Windows..."
Write-Host "  Project: $ProjectDir"
Write-Host "  Output:  $OutputDir"
Write-Host ""

# Build self-contained single-file executable
dotnet publish $ProjectDir `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $OutputDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Build failed." -ForegroundColor Red
    exit 1
}

# Copy Python scripts to output
$PythonDir = Join-Path $OutputDir "Python"
if (!(Test-Path $PythonDir)) { New-Item -ItemType Directory -Path $PythonDir | Out-Null }

Copy-Item (Join-Path $ProjectDir "Python\transcribe_server.py") $PythonDir -Force
Copy-Item (Join-Path $ProjectDir "Python\transcribe.py") $PythonDir -Force

Write-Host ""
Write-Host "[ok] Build complete!" -ForegroundColor Green
Write-Host "  Executable: $OutputDir\Scriptik.exe"
Write-Host "  Run setup.ps1 first to install the Python/Whisper environment."
