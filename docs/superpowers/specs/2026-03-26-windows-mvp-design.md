# Scriptik Windows MVP — Design Spec

## Goal

Build a Windows version of Scriptik using Tauri (Rust + web frontend) that provides core voice-to-text functionality. Ships as a standalone `.msi` installer. Reuses the existing Python Whisper transcription server.

The macOS Swift codebase is untouched — this is a separate project in `scriptik-windows/`.

## MVP Scope

### Included

- System tray icon with right-click menu (Start/Stop Recording, Settings, Quit)
- Global hotkey (default: Ctrl+Shift+R) to toggle recording
- Audio recording via Rust `cpal` crate (saves WAV to temp directory)
- Transcription via Python `transcribe_server.py` subprocess (persistent JSON-RPC server)
- Automatic clipboard copy of transcription result
- Tray popup window showing: current status (idle/recording/transcribing), last transcription text
- Config file at `%APPDATA%\scriptik\config` (same key-value format as macOS)
- Timestamps and pause detection in output (handled by existing Python code)

### Excluded (future phases)

- Floating circle indicator
- Auto-paste into active app
- Transcription history UI
- Web dashboard
- Sound feedback
- Settings UI (config file only for MVP)
- Multi-monitor awareness
- Launch at login

## Architecture

```
scriptik-windows/
├── src-tauri/
│   ├── src/
│   │   ├── main.rs           # App entry, system tray, event handling
│   │   ├── audio.rs          # Audio recording via cpal
│   │   ├── transcriber.rs    # Manages Python transcription server subprocess
│   │   ├── hotkey.rs         # Global hotkey registration
│   │   ├── config.rs         # Read/write config from %APPDATA%
│   │   └── clipboard.rs      # Copy text to clipboard
│   ├── Cargo.toml
│   └── tauri.conf.json
├── src/
│   ├── index.html            # Tray popup window
│   ├── main.js               # Frontend logic (status display, IPC with Rust)
│   └── style.css
├── python/
│   └── transcribe_server.py  # Copied from repo root (same file macOS uses)
├── scripts/
│   └── setup.ps1             # PowerShell setup: install Python deps, download model
├── .github/
│   └── workflows/
│       └── windows-build.yml # CI: build + package on windows-latest
└── README.md
```

## Component Details

### 1. System Tray (main.rs)

Tauri's built-in `SystemTray` API.

**Menu items:**
- "Start Recording" / "Stop Recording" (toggles based on state)
- Separator
- "Quit"

**Left-click:** Opens the tray popup window (small, anchored to tray icon).
**Right-click:** Shows the context menu.

**State machine:**
```
Idle → (hotkey or tray click) → Recording → (hotkey or tray click) → Transcribing → Idle
```

Tray icon changes color per state: gray (idle), red (recording), yellow (transcribing).

### 2. Audio Recording (audio.rs)

Uses `cpal` crate for cross-platform audio capture.

- Enumerates default input device
- Records PCM audio, writes to WAV file at `%TEMP%\scriptik\recording.wav`
- Exposes start/stop commands via Tauri commands
- Reports recording duration back to frontend

WAV format: 16kHz, 16-bit mono (Whisper's preferred input).

### 3. Transcription Server (transcriber.rs)

Manages the Python `transcribe_server.py` as a child process.

**Lifecycle:**
1. On first transcription request, spawn `python transcribe_server.py` with stdin/stdout pipes
2. Server loads Whisper model once, stays resident
3. Send JSON-RPC requests: `{"method": "transcribe", "params": {"file": "path/to/recording.wav"}}`
4. Receive JSON response with segments, timestamps, pauses
5. Server stays alive for subsequent requests (no cold start)

**Python environment:**
- `setup.ps1` creates a venv at `%APPDATA%\scriptik\venv\`
- Installs `openai-whisper` (not `mlx-whisper` — that's Apple Silicon only)
- Downloads the configured model on first setup

**Error handling:**
- If Python process crashes, restart on next transcription request
- If Python not found, show error in tray popup with setup instructions

### 4. Global Hotkey (hotkey.rs)

Uses `global-hotkey` crate (same one Tauri uses internally).

- Default: Ctrl+Shift+R
- Configurable via config file
- Registered on app start, unregistered on quit
- Triggers the same state toggle as the tray button

### 5. Clipboard (clipboard.rs)

Uses `arboard` crate (cross-platform clipboard).

- After transcription completes, copy formatted text to clipboard
- Plain text with timestamps and pause markers (same format as macOS)

### 6. Config (config.rs)

Reads `%APPDATA%\scriptik\config` — same key-value format as macOS:

```ini
WHISPER_MODEL=medium
PAUSE_THRESHOLD=1.5
INITIAL_PROMPT=Docker, FastAPI, PostgreSQL, React
LANGUAGE=auto
HOTKEY=Ctrl+Shift+R
```

Parsed on startup. No live reload for MVP — restart app to apply changes.

### 7. Frontend (src/)

Minimal HTML/JS tray popup window (~300x200px).

**Displays:**
- Current state with icon (Idle / Recording [duration] / Transcribing...)
- Last transcription text (scrollable, with timestamps)
- "Copied to clipboard" confirmation

**IPC:** Uses Tauri's `invoke` API to call Rust commands and `listen` for events.

## Setup Flow

User runs `setup.ps1` (PowerShell):

1. Check Python 3 is installed, error if not
2. Create venv at `%APPDATA%\scriptik\venv\`
3. Install `openai-whisper`, `numpy` in venv
4. Create default config at `%APPDATA%\scriptik\config`
5. Download configured Whisper model

Alternatively, the Tauri app detects missing setup on first launch and shows instructions in the tray popup.

## CI / GitHub Actions

**`windows-build.yml`:**
- Trigger: push to `scriptik-windows/**` paths on the feature branch
- Runner: `windows-latest`
- Steps:
  1. Install Rust toolchain
  2. Install Node.js (for Tauri frontend build)
  3. `cargo build --release` in `src-tauri/`
  4. `npm run build` for frontend
  5. `cargo tauri build` to produce `.msi` installer
  6. Upload `.msi` as build artifact

No audio/transcription tests in CI (no microphone, no GPU). Build verification only.

## File Paths (Windows)

| Purpose | Path |
|---------|------|
| Config | `%APPDATA%\scriptik\config` |
| Python venv | `%APPDATA%\scriptik\venv\` |
| Whisper models | `%USERPROFILE%\.cache\whisper\` (openai-whisper default) |
| Temp recording | `%TEMP%\scriptik\recording.wav` |
| Logs | `%APPDATA%\scriptik\logs\` |

## Whisper on Windows

- Uses `openai-whisper` (PyTorch-based), not `mlx-whisper` (Apple Silicon only)
- CUDA acceleration available if user has NVIDIA GPU + CUDA toolkit
- CPU fallback works but is slower (~2-4x vs Apple Silicon MLX)
- Same transcription parameters as macOS: `condition_on_previous_text=False`, `no_speech_threshold=0.05`

## Risks

1. **cpal audio quality** — needs testing on various Windows audio drivers. Fallback: use `pyaudio` via Python subprocess if `cpal` has issues.
2. **Whisper performance on CPU** — Windows users without NVIDIA GPU will have slower transcription. Mitigation: recommend `tiny` or `base` model for CPU-only users.
3. **Python dependency** — users must have Python 3 installed. Mitigation: clear error messaging + setup script.
4. **Global hotkey conflicts** — Ctrl+Shift+R may conflict with other apps. Mitigation: configurable via config file.
