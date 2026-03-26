# Scriptik for Windows

Voice-to-text for Windows — record, transcribe locally with Whisper, and copy to clipboard.
System tray app with global hotkey support. No cloud, no subscription.

This is the Windows companion to [Scriptik for macOS](../README.md).

## Requirements

- **Windows 10/11**
- **Python 3.8+** ([python.org](https://www.python.org/downloads/))
- **ffmpeg** (`winget install ffmpeg`)

## Setup

1. Download `Scriptik-setup.msi` from the [latest release](https://github.com/Leon-Rud/scriptik/releases/latest)
2. Install the MSI
3. Open PowerShell and run the setup script:

```powershell
cd "C:\Program Files\Scriptik"
.\scripts\setup.ps1
```

This creates a Python virtual environment and downloads the Whisper model.

## Usage

1. Launch **Scriptik** from the Start Menu
2. A system tray icon appears (bottom-right, near the clock)
3. Press **Ctrl+Shift+R** (default) to start recording
4. Press again to stop — transcription is copied to clipboard
5. Left-click the tray icon to see the last transcription
6. Right-click for menu (Start/Stop Recording, Quit)

## Configuration

Edit `%APPDATA%\scriptik\config`:

```
WHISPER_MODEL=medium
PAUSE_THRESHOLD=1.5
INITIAL_PROMPT=Docker, FastAPI, PostgreSQL
LANGUAGE=auto
HOTKEY=Ctrl+Shift+R
```

Restart the app after changing config.

## Building from Source

Requires: Rust toolchain, Tauri CLI

```bash
cd scriptik-windows
cargo install tauri-cli
cargo tauri build
```

The MSI installer is output to `src-tauri/target/release/bundle/msi/`.
