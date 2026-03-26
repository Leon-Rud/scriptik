# Scriptik Windows MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows system tray app using Tauri that records audio, transcribes via the existing Python Whisper server, and copies results to clipboard.

**Architecture:** Tauri (Rust backend + HTML/JS frontend) in a new `scriptik-windows/` directory. Reuses the existing `transcribe_server.py` as a subprocess. Rust handles audio capture (cpal), global hotkey, clipboard, and system tray. Frontend is a minimal popup window for status display.

**Tech Stack:** Rust, Tauri 2, cpal (audio), global-hotkey, arboard (clipboard), HTML/JS/CSS

**Spec:** `docs/superpowers/specs/2026-03-26-windows-mvp-design.md`

---

## File Structure

```
scriptik-windows/
├── src-tauri/
│   ├── src/
│   │   ├── main.rs           # Tauri app entry, system tray, state machine, commands
│   │   ├── audio.rs          # Audio recording via cpal (record to WAV)
│   │   ├── transcriber.rs    # Manage Python transcribe_server.py subprocess
│   │   ├── config.rs         # Parse config from %APPDATA%\scriptik\config
│   │   └── lib.rs            # Module declarations
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── icons/                # App icons (Tauri default + scriptik icon)
│   └── python/
│       └── transcribe_server.py  # Copied from Scriptik/Sources/Scriptik/Resources/
├── src/
│   ├── index.html            # Tray popup window
│   ├── main.js               # Frontend logic, IPC
│   └── style.css             # Styling
├── scripts/
│   └── setup.ps1             # PowerShell: create venv, install whisper, download model
├── package.json              # npm for frontend build
├── .github/
│   └── workflows/
│       └── windows-build.yml
└── README.md
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `scriptik-windows/src-tauri/Cargo.toml`
- Create: `scriptik-windows/src-tauri/tauri.conf.json`
- Create: `scriptik-windows/src-tauri/src/main.rs` (minimal hello-world)
- Create: `scriptik-windows/src-tauri/src/lib.rs`
- Create: `scriptik-windows/src/index.html`
- Create: `scriptik-windows/src/main.js`
- Create: `scriptik-windows/src/style.css`
- Create: `scriptik-windows/package.json`

**Context:** This creates the Tauri 2 project skeleton. We're developing on macOS but targeting Windows. The project should build on both platforms (Tauri is cross-platform) but will only be packaged for Windows.

- [ ] **Step 1: Create Cargo.toml**

```toml
# scriptik-windows/src-tauri/Cargo.toml
[package]
name = "scriptik-windows"
version = "0.1.0"
edition = "2021"

[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-shell = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
cpal = "0.15"
hound = "3.5"
arboard = "3"
global-hotkey = "0.6"
dirs = "6"
tokio = { version = "1", features = ["process", "io-util", "sync", "time", "rt"] }

[build-dependencies]
tauri-build = { version = "2", features = [] }

[[bin]]
name = "scriptik-windows"
path = "src/main.rs"
```

- [ ] **Step 2: Create tauri.conf.json**

```json
{
  "$schema": "https://raw.githubusercontent.com/nicedoc/tauri-schema/main/tauri.conf.schema.json",
  "productName": "Scriptik",
  "version": "0.1.0",
  "identifier": "com.scriptik.windows",
  "build": {
    "frontendDist": "../src",
    "devUrl": "http://localhost:1420"
  },
  "app": {
    "withGlobalTauri": true,
    "windows": [
      {
        "title": "Scriptik",
        "width": 350,
        "height": 250,
        "resizable": false,
        "visible": false,
        "decorations": true
      }
    ],
    "trayIcon": {
      "iconPath": "icons/icon.png",
      "iconAsTemplate": false
    }
  },
  "bundle": {
    "active": true,
    "targets": ["msi"],
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/icon.ico"
    ]
  }
}
```

- [ ] **Step 3: Create build.rs**

```rust
// scriptik-windows/src-tauri/build.rs
fn main() {
    tauri_build::build()
}
```

- [ ] **Step 4: Create lib.rs with module declarations**

```rust
// scriptik-windows/src-tauri/src/lib.rs
pub mod audio;
pub mod config;
pub mod transcriber;
```

- [ ] **Step 5: Create minimal main.rs**

```rust
// scriptik-windows/src-tauri/src/main.rs
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod config;
mod transcriber;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 6: Create empty module files**

```rust
// scriptik-windows/src-tauri/src/audio.rs
// Audio recording module - implemented in Task 3
```

```rust
// scriptik-windows/src-tauri/src/config.rs
// Config module - implemented in Task 2
```

```rust
// scriptik-windows/src-tauri/src/transcriber.rs
// Transcription server module - implemented in Task 4
```

- [ ] **Step 7: Create frontend files**

```html
<!-- scriptik-windows/src/index.html -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Scriptik</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div id="app">
    <div id="status">Idle</div>
    <div id="transcription"></div>
  </div>
  <script src="main.js" type="module"></script>
</body>
</html>
```

```css
/* scriptik-windows/src/style.css */
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: 'Segoe UI', sans-serif; background: #1e1e2e; color: #cdd6f4; padding: 16px; }
#status { font-size: 18px; font-weight: 600; margin-bottom: 12px; }
#transcription { font-size: 13px; max-height: 180px; overflow-y: auto; white-space: pre-wrap; opacity: 0.8; }
```

```javascript
// scriptik-windows/src/main.js
// Frontend logic - implemented in Task 7
```

- [ ] **Step 8: Create package.json**

```json
{
  "name": "scriptik-windows",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "tauri": "cargo tauri"
  }
}
```

- [ ] **Step 9: Copy icon and create icons directory**

Copy `icon.png` from repo root to `scriptik-windows/src-tauri/icons/icon.png`. Also create placeholder `32x32.png`, `128x128.png`, and `icon.ico` (can use the same icon resized, or Tauri's default icons for now).

- [ ] **Step 10: Commit**

```bash
git add scriptik-windows/
git commit -m "feat(windows): scaffold Tauri project"
```

---

### Task 2: Config Module

**Files:**
- Create: `scriptik-windows/src-tauri/src/config.rs`

**Context:** Reads a simple key=value config file. On Windows: `%APPDATA%\scriptik\config`. On macOS (dev): `~/.config/scriptik/config`. Same format as the existing macOS app uses. Provides defaults for all values.

Existing config format (from `scriptik-cli` and macOS app):
```
WHISPER_MODEL=medium
PAUSE_THRESHOLD=1.5
INITIAL_PROMPT=Docker, FastAPI, PostgreSQL, React
AUTO_PASTE=true
LANGUAGE=auto
HOTKEY=Ctrl+Shift+R
```

- [ ] **Step 1: Write config.rs with tests**

```rust
// scriptik-windows/src-tauri/src/config.rs
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub whisper_model: String,
    pub pause_threshold: f64,
    pub initial_prompt: String,
    pub language: String,
    pub hotkey: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            whisper_model: "medium".to_string(),
            pause_threshold: 1.5,
            initial_prompt: String::new(),
            language: "auto".to_string(),
            hotkey: "Ctrl+Shift+R".to_string(),
        }
    }
}

impl Config {
    pub fn load() -> Self {
        let path = Self::config_path();
        if let Ok(contents) = fs::read_to_string(&path) {
            Self::parse(&contents)
        } else {
            Self::default()
        }
    }

    pub fn config_dir() -> PathBuf {
        if cfg!(windows) {
            dirs::config_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("scriptik")
        } else {
            dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join(".config")
                .join("scriptik")
        }
    }

    pub fn config_path() -> PathBuf {
        Self::config_dir().join("config")
    }

    pub fn data_dir() -> PathBuf {
        if cfg!(windows) {
            dirs::data_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join("scriptik")
        } else {
            dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join(".local/share/scriptik")
        }
    }

    fn parse(contents: &str) -> Self {
        let mut map = HashMap::new();
        for line in contents.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((key, value)) = line.split_once('=') {
                let value = value.trim().trim_matches('"');
                map.insert(key.trim().to_uppercase(), value.to_string());
            }
        }

        let defaults = Self::default();
        Self {
            whisper_model: map.get("WHISPER_MODEL").cloned().unwrap_or(defaults.whisper_model),
            pause_threshold: map.get("PAUSE_THRESHOLD")
                .and_then(|v| v.parse().ok())
                .unwrap_or(defaults.pause_threshold),
            initial_prompt: map.get("INITIAL_PROMPT").cloned().unwrap_or(defaults.initial_prompt),
            language: map.get("LANGUAGE").cloned().unwrap_or(defaults.language),
            hotkey: map.get("HOTKEY").cloned().unwrap_or(defaults.hotkey),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_full_config() {
        let input = r#"
WHISPER_MODEL=small
PAUSE_THRESHOLD=2.0
INITIAL_PROMPT=Docker, FastAPI
LANGUAGE=en
HOTKEY=Ctrl+Alt+R
"#;
        let config = Config::parse(input);
        assert_eq!(config.whisper_model, "small");
        assert_eq!(config.pause_threshold, 2.0);
        assert_eq!(config.initial_prompt, "Docker, FastAPI");
        assert_eq!(config.language, "en");
        assert_eq!(config.hotkey, "Ctrl+Alt+R");
    }

    #[test]
    fn test_parse_empty_uses_defaults() {
        let config = Config::parse("");
        assert_eq!(config.whisper_model, "medium");
        assert_eq!(config.pause_threshold, 1.5);
        assert_eq!(config.language, "auto");
    }

    #[test]
    fn test_parse_with_comments_and_quotes() {
        let input = r#"
# This is a comment
WHISPER_MODEL="large"
PAUSE_THRESHOLD=3.0
"#;
        let config = Config::parse(input);
        assert_eq!(config.whisper_model, "large");
        assert_eq!(config.pause_threshold, 3.0);
    }

    #[test]
    fn test_parse_invalid_threshold_uses_default() {
        let input = "PAUSE_THRESHOLD=notanumber";
        let config = Config::parse(input);
        assert_eq!(config.pause_threshold, 1.5);
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd scriptik-windows/src-tauri && cargo test --lib config`
Expected: All 4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add scriptik-windows/src-tauri/src/config.rs
git commit -m "feat(windows): add config parser with defaults"
```

---

### Task 3: Audio Recording Module

**Files:**
- Create: `scriptik-windows/src-tauri/src/audio.rs`

**Context:** Records audio from the default input device using the `cpal` crate, writes a 16kHz 16-bit mono WAV file (Whisper's preferred input). The existing macOS app uses `AVAudioRecorder` in `Scriptik/Sources/Scriptik/Services/AudioRecorder.swift` — this is the Rust equivalent. Recording happens in a background thread; start/stop are controlled via an `Arc<AtomicBool>` flag.

- [ ] **Step 1: Write audio.rs**

```rust
// scriptik-windows/src-tauri/src/audio.rs
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::SampleFormat;
use hound::{WavSpec, WavWriter};
use std::io::BufWriter;
use std::fs::File;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

const TARGET_SAMPLE_RATE: u32 = 16000;
const TARGET_CHANNELS: u16 = 1;

pub struct Recorder {
    recording: Arc<AtomicBool>,
    output_path: PathBuf,
}

impl Recorder {
    pub fn new() -> Self {
        let temp_dir = std::env::temp_dir().join("scriptik");
        std::fs::create_dir_all(&temp_dir).ok();
        Self {
            recording: Arc::new(AtomicBool::new(false)),
            output_path: temp_dir.join("recording.wav"),
        }
    }

    pub fn output_path(&self) -> &PathBuf {
        &self.output_path
    }

    pub fn is_recording(&self) -> bool {
        self.recording.load(Ordering::Relaxed)
    }

    /// Start recording in a background thread. Returns an error string if setup fails.
    pub fn start(&self) -> Result<(), String> {
        if self.is_recording() {
            return Err("Already recording".to_string());
        }

        let host = cpal::default_host();
        let device = host.default_input_device()
            .ok_or("No audio input device found")?;

        let supported_config = device.default_input_config()
            .map_err(|e| format!("Failed to get input config: {e}"))?;

        let sample_rate = supported_config.sample_rate().0;
        let channels = supported_config.channels();
        let sample_format = supported_config.sample_format();

        // We'll collect samples and resample/downmix when writing
        let samples: Arc<Mutex<Vec<f32>>> = Arc::new(Mutex::new(Vec::new()));
        let samples_clone = samples.clone();

        let recording_flag = self.recording.clone();
        recording_flag.store(true, Ordering::Relaxed);

        let output_path = self.output_path.clone();
        let recording_for_thread = recording_flag.clone();

        std::thread::spawn(move || {
            let err_fn = |err| eprintln!("Audio stream error: {err}");

            let stream = match sample_format {
                SampleFormat::F32 => {
                    let samples = samples_clone.clone();
                    device.build_input_stream(
                        &supported_config.into(),
                        move |data: &[f32], _: &cpal::InputCallbackInfo| {
                            if let Ok(mut buf) = samples.lock() {
                                buf.extend_from_slice(data);
                            }
                        },
                        err_fn,
                        None,
                    )
                }
                SampleFormat::I16 => {
                    let samples = samples_clone.clone();
                    device.build_input_stream(
                        &supported_config.into(),
                        move |data: &[i16], _: &cpal::InputCallbackInfo| {
                            if let Ok(mut buf) = samples.lock() {
                                buf.extend(data.iter().map(|&s| s as f32 / i16::MAX as f32));
                            }
                        },
                        err_fn,
                        None,
                    )
                }
                _ => {
                    eprintln!("Unsupported sample format: {sample_format:?}");
                    recording_for_thread.store(false, Ordering::Relaxed);
                    return;
                }
            };

            let stream = match stream {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("Failed to build audio stream: {e}");
                    recording_for_thread.store(false, Ordering::Relaxed);
                    return;
                }
            };

            if let Err(e) = stream.play() {
                eprintln!("Failed to start audio stream: {e}");
                recording_for_thread.store(false, Ordering::Relaxed);
                return;
            }

            // Wait until recording flag is cleared
            while recording_for_thread.load(Ordering::Relaxed) {
                std::thread::sleep(std::time::Duration::from_millis(50));
            }

            drop(stream);

            // Write WAV: downmix to mono if needed, resample to 16kHz
            let raw_samples = samples_clone.lock().unwrap().clone();
            if let Err(e) = write_wav(&output_path, &raw_samples, sample_rate, channels) {
                eprintln!("Failed to write WAV: {e}");
            }
        });

        Ok(())
    }

    pub fn stop(&self) {
        self.recording.store(false, Ordering::Relaxed);
    }
}

fn write_wav(path: &PathBuf, samples: &[f32], source_rate: u32, channels: u16) -> Result<(), String> {
    // Downmix to mono
    let mono: Vec<f32> = if channels > 1 {
        samples.chunks(channels as usize)
            .map(|chunk| chunk.iter().sum::<f32>() / channels as f32)
            .collect()
    } else {
        samples.to_vec()
    };

    // Simple linear resample to 16kHz
    let resampled = if source_rate != TARGET_SAMPLE_RATE {
        let ratio = TARGET_SAMPLE_RATE as f64 / source_rate as f64;
        let new_len = (mono.len() as f64 * ratio) as usize;
        (0..new_len)
            .map(|i| {
                let src_idx = i as f64 / ratio;
                let idx = src_idx as usize;
                let frac = src_idx - idx as f64;
                let s0 = mono.get(idx).copied().unwrap_or(0.0);
                let s1 = mono.get(idx + 1).copied().unwrap_or(s0);
                (s0 as f64 * (1.0 - frac) + s1 as f64 * frac) as f32
            })
            .collect()
    } else {
        mono
    };

    let spec = WavSpec {
        channels: TARGET_CHANNELS,
        sample_rate: TARGET_SAMPLE_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let file = File::create(path).map_err(|e| format!("Failed to create WAV file: {e}"))?;
    let mut writer = WavWriter::new(BufWriter::new(file), spec)
        .map_err(|e| format!("Failed to create WAV writer: {e}"))?;

    for sample in &resampled {
        let s = (*sample * i16::MAX as f32).clamp(i16::MIN as f32, i16::MAX as f32) as i16;
        writer.write_sample(s).map_err(|e| format!("Failed to write sample: {e}"))?;
    }

    writer.finalize().map_err(|e| format!("Failed to finalize WAV: {e}"))?;
    Ok(())
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd scriptik-windows/src-tauri && cargo check`
Expected: No errors (audio tests require a real audio device, so we test via compilation + manual testing).

- [ ] **Step 3: Commit**

```bash
git add scriptik-windows/src-tauri/src/audio.rs
git commit -m "feat(windows): add audio recording module (cpal + WAV)"
```

---

### Task 4: Transcription Server Module

**Files:**
- Create: `scriptik-windows/src-tauri/src/transcriber.rs`
- Copy: `Scriptik/Sources/Scriptik/Resources/transcribe_server.py` → `scriptik-windows/src-tauri/python/transcribe_server.py`

**Context:** This mirrors `Scriptik/Sources/Scriptik/Services/TranscriptionServer.swift`. It spawns the Python `transcribe_server.py` as a child process, communicates via JSON over stdin/stdout. The Python script already handles both `mlx-whisper` (Apple Silicon) and `openai-whisper` (all platforms) — on Windows it will use `openai-whisper` automatically since `mlx-whisper` won't be installed.

The protocol is: send a JSON line to stdin, read a JSON line from stdout.
- Startup: server sends `{"type": "ready", "model": "...", "backend": "..."}`
- Transcribe: send `{"type": "transcribe", "recording_path": "...", "transcription_path": "...", ...}` → receive `{"type": "transcription_done", "text": "...", "duration_seconds": N}`
- Errors: `{"type": "error", "message": "..."}`

- [ ] **Step 1: Copy transcribe_server.py**

```bash
mkdir -p scriptik-windows/src-tauri/python
cp Scriptik/Sources/Scriptik/Resources/transcribe_server.py scriptik-windows/src-tauri/python/transcribe_server.py
```

No modifications needed — the Python script already supports both mlx-whisper and openai-whisper. On Windows, only openai-whisper will be available, and the script handles that via try/except import.

One fix needed: line 43 uses `os.environ.get("HOME", "/tmp")` for the cache dir — on Windows, `HOME` may not be set. Replace with a cross-platform approach:

In `scriptik-windows/src-tauri/python/transcribe_server.py`, change line 43 from:
```python
cache_dir = os.path.join(os.environ.get("HOME", "/tmp"), ".cache", "whisper")
```
to:
```python
cache_dir = os.path.join(os.path.expanduser("~"), ".cache", "whisper")
```

- [ ] **Step 2: Write transcriber.rs**

```rust
// scriptik-windows/src-tauri/src/transcriber.rs
use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::{mpsc, oneshot, Mutex};
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq)]
pub enum ServerState {
    Stopped,
    Starting,
    Ready,
    Busy,
}

pub struct TranscriptionServer {
    state: Arc<Mutex<ServerState>>,
    request_tx: Arc<Mutex<Option<mpsc::Sender<ServerRequest>>>>,
}

struct ServerRequest {
    payload: Value,
    response_tx: oneshot::Sender<Result<Value, String>>,
}

impl TranscriptionServer {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(ServerState::Stopped)),
            request_tx: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn state(&self) -> ServerState {
        self.state.lock().await.clone()
    }

    /// Start the Python transcription server process.
    pub async fn start(&self, python_path: &str, model: &str, server_script: &str) -> Result<(), String> {
        let mut state = self.state.lock().await;
        if *state != ServerState::Stopped {
            return Err("Server already running".to_string());
        }
        *state = ServerState::Starting;
        drop(state);

        let mut child = Command::new(python_path)
            .arg(server_script)
            .arg(model)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .env("PYTHONUNBUFFERED", "1")
            .env("PYTHONIOENCODING", "utf-8")
            .spawn()
            .map_err(|e| format!("Failed to start Python server: {e}"))?;

        let stdin = child.stdin.take().ok_or("Failed to get stdin")?;
        let stdout = child.stdout.take().ok_or("Failed to get stdout")?;
        let stderr = child.stderr.take().ok_or("Failed to get stderr")?;

        let (request_tx, request_rx) = mpsc::channel::<ServerRequest>(16);
        *self.request_tx.lock().await = Some(request_tx);

        let state_clone = self.state.clone();

        // Spawn the server communication loop
        tokio::spawn(async move {
            Self::server_loop(child, stdin, stdout, stderr, request_rx, state_clone).await;
        });

        // Wait for ready signal (up to 60s for model download)
        let start_time = std::time::Instant::now();
        loop {
            let s = self.state.lock().await.clone();
            match s {
                ServerState::Ready => return Ok(()),
                ServerState::Stopped => return Err("Server failed to start".to_string()),
                _ => {}
            }
            if start_time.elapsed().as_secs() > 60 {
                return Err("Server startup timed out".to_string());
            }
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
    }

    async fn server_loop(
        _child: Child,
        mut stdin: tokio::process::ChildStdin,
        stdout: tokio::process::ChildStdout,
        stderr: tokio::process::ChildStderr,
        mut request_rx: mpsc::Receiver<ServerRequest>,
        state: Arc<Mutex<ServerState>>,
    ) {
        let mut stdout_reader = BufReader::new(stdout).lines();
        let mut stderr_reader = BufReader::new(stderr).lines();

        // Track pending response
        let mut pending_response: Option<oneshot::Sender<Result<Value, String>>> = None;

        // Log stderr in background
        tokio::spawn(async move {
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                eprintln!("[whisper-server] {line}");
            }
        });

        loop {
            tokio::select! {
                // Handle incoming requests to send to the server
                Some(req) = request_rx.recv() => {
                    let json_str = serde_json::to_string(&req.payload).unwrap() + "\n";
                    if let Err(e) = stdin.write_all(json_str.as_bytes()).await {
                        let _ = req.response_tx.send(Err(format!("Failed to write to server: {e}")));
                        continue;
                    }
                    if let Err(e) = stdin.flush().await {
                        let _ = req.response_tx.send(Err(format!("Failed to flush: {e}")));
                        continue;
                    }
                    pending_response = Some(req.response_tx);
                }
                // Handle responses from the server
                result = stdout_reader.next_line() => {
                    match result {
                        Ok(Some(line)) => {
                            if let Ok(json) = serde_json::from_str::<Value>(&line) {
                                let msg_type = json.get("type").and_then(|t| t.as_str()).unwrap_or("");
                                match msg_type {
                                    "ready" => {
                                        *state.lock().await = ServerState::Ready;
                                    }
                                    "transcription_done" | "model_reloaded" | "error" | "pong" => {
                                        if let Some(tx) = pending_response.take() {
                                            let _ = tx.send(Ok(json));
                                        }
                                        *state.lock().await = ServerState::Ready;
                                    }
                                    _ => {
                                        eprintln!("Unknown server message type: {msg_type}");
                                    }
                                }
                            }
                        }
                        Ok(None) | Err(_) => {
                            // Server process ended
                            if let Some(tx) = pending_response.take() {
                                let _ = tx.send(Err("Server process terminated".to_string()));
                            }
                            *state.lock().await = ServerState::Stopped;
                            break;
                        }
                    }
                }
            }
        }
    }

    /// Send a transcription request to the server.
    pub async fn transcribe(
        &self,
        recording_path: &str,
        transcription_path: &str,
        pause_threshold: f64,
        model: &str,
        initial_prompt: &str,
        language: &str,
    ) -> Result<String, String> {
        {
            let mut state = self.state.lock().await;
            if *state != ServerState::Ready {
                return Err("Server not ready".to_string());
            }
            *state = ServerState::Busy;
        }

        let payload = json!({
            "type": "transcribe",
            "recording_path": recording_path,
            "transcription_path": transcription_path,
            "pause_threshold": pause_threshold,
            "model": model,
            "initial_prompt": initial_prompt,
            "language": language,
        });

        let (response_tx, response_rx) = oneshot::channel();
        let request = ServerRequest { payload, response_tx };

        let tx = self.request_tx.lock().await;
        let tx = tx.as_ref().ok_or("Server not started")?;
        tx.send(request).await.map_err(|_| "Failed to send request")?;
        drop(tx);

        let response = tokio::time::timeout(
            std::time::Duration::from_secs(120),
            response_rx,
        )
        .await
        .map_err(|_| "Transcription timed out".to_string())?
        .map_err(|_| "Response channel closed".to_string())??;

        let msg_type = response.get("type").and_then(|t| t.as_str()).unwrap_or("");
        if msg_type == "error" {
            let msg = response.get("message").and_then(|m| m.as_str()).unwrap_or("Unknown error");
            return Err(msg.to_string());
        }

        // Read the transcription file (server writes it)
        let text = std::fs::read_to_string(transcription_path)
            .map_err(|e| format!("Failed to read transcription: {e}"))?
            .trim()
            .to_string();

        if text.is_empty() {
            return Err("Transcription produced no output".to_string());
        }

        Ok(text)
    }

    pub async fn stop(&self) {
        *self.state.lock().await = ServerState::Stopped;
        *self.request_tx.lock().await = None;
    }

    /// Find the transcribe_server.py script path.
    /// Looks relative to the executable, then in common install locations.
    pub fn find_server_script() -> Option<PathBuf> {
        // Next to executable
        if let Ok(exe) = std::env::current_exe() {
            let dir = exe.parent()?;
            let path = dir.join("python").join("transcribe_server.py");
            if path.exists() {
                return Some(path);
            }
            // Tauri bundles resources in a _up_ directory on some platforms
            let path = dir.join("..").join("python").join("transcribe_server.py");
            if path.exists() {
                return Some(path);
            }
        }

        // In app data
        let data_dir = crate::config::Config::data_dir();
        let path = data_dir.join("transcribe_server.py");
        if path.exists() {
            return Some(path);
        }

        None
    }

    /// Find Python executable. Checks the venv first, then system Python.
    pub fn find_python() -> Option<String> {
        let data_dir = crate::config::Config::data_dir();

        // Check venv
        let venv_python = if cfg!(windows) {
            data_dir.join("venv").join("Scripts").join("python.exe")
        } else {
            data_dir.join("venv").join("bin").join("python3")
        };
        if venv_python.exists() {
            return Some(venv_python.to_string_lossy().to_string());
        }

        // Fallback to system python
        let system = if cfg!(windows) { "python" } else { "python3" };
        if std::process::Command::new(system).arg("--version").output().is_ok() {
            return Some(system.to_string());
        }

        None
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd scriptik-windows/src-tauri && cargo check`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add scriptik-windows/src-tauri/src/transcriber.rs scriptik-windows/src-tauri/python/
git commit -m "feat(windows): add transcription server module + copy Python script"
```

---

### Task 5: System Tray, State Machine, and Tauri Commands (Integration)

**Files:**
- Modify: `scriptik-windows/src-tauri/src/main.rs`
- Modify: `scriptik-windows/src/index.html`
- Modify: `scriptik-windows/src/main.js`
- Modify: `scriptik-windows/src/style.css`

**Context:** This task wires everything together. The main.rs sets up:
1. System tray with right-click menu
2. Global hotkey registration
3. Tauri commands that the frontend calls
4. App state machine (Idle → Recording → Transcribing → Idle)

The frontend shows a small popup with status and last transcription.

**Dependencies:** Tasks 1-4 must be complete (scaffolding, config, audio, transcriber).

- [ ] **Step 1: Write the full main.rs**

```rust
// scriptik-windows/src-tauri/src/main.rs
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod audio;
mod config;
mod transcriber;

use audio::Recorder;
use config::Config;
use transcriber::TranscriptionServer;

use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager, hotkey::{Code, HotKey, Modifiers}};
use std::sync::Arc;
use tauri::{
    AppHandle, Emitter, Manager,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
};
use tokio::sync::Mutex;

#[derive(Debug, Clone, serde::Serialize)]
enum AppStatus {
    Idle,
    Recording,
    Transcribing,
}

struct AppState {
    status: Mutex<AppStatus>,
    recorder: Recorder,
    server: TranscriptionServer,
    config: Config,
    last_transcription: Mutex<String>,
}

#[tauri::command]
async fn get_status(state: tauri::State<'_, Arc<AppState>>) -> Result<String, String> {
    let status = state.status.lock().await;
    Ok(serde_json::to_string(&*status).unwrap())
}

#[tauri::command]
async fn get_last_transcription(state: tauri::State<'_, Arc<AppState>>) -> Result<String, String> {
    Ok(state.last_transcription.lock().await.clone())
}

#[tauri::command]
async fn toggle_recording(app: AppHandle, state: tauri::State<'_, Arc<AppState>>) -> Result<(), String> {
    do_toggle(app, &state).await
}

async fn do_toggle(app: AppHandle, state: &Arc<AppState>) -> Result<(), String> {
    let current = state.status.lock().await.clone();
    match current {
        AppStatus::Idle => {
            // Start recording
            state.recorder.start()?;
            *state.status.lock().await = AppStatus::Recording;
            let _ = app.emit("status-changed", "Recording");
        }
        AppStatus::Recording => {
            // Stop recording, start transcription
            state.recorder.stop();
            *state.status.lock().await = AppStatus::Transcribing;
            let _ = app.emit("status-changed", "Transcribing");

            // Wait a moment for the WAV file to be written
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;

            let recording_path = state.recorder.output_path().to_string_lossy().to_string();
            let transcription_path = std::env::temp_dir()
                .join("scriptik")
                .join("transcription.txt")
                .to_string_lossy()
                .to_string();

            let config = &state.config;

            match state.server.transcribe(
                &recording_path,
                &transcription_path,
                config.pause_threshold,
                &config.whisper_model,
                &config.initial_prompt,
                &config.language,
            ).await {
                Ok(text) => {
                    // Copy to clipboard
                    if let Ok(mut clipboard) = arboard::Clipboard::new() {
                        let _ = clipboard.set_text(&text);
                    }
                    *state.last_transcription.lock().await = text.clone();
                    let _ = app.emit("transcription-done", text);
                }
                Err(e) => {
                    let _ = app.emit("transcription-error", e.clone());
                    eprintln!("Transcription error: {e}");
                }
            }

            *state.status.lock().await = AppStatus::Idle;
            let _ = app.emit("status-changed", "Idle");
        }
        AppStatus::Transcribing => {
            // Can't toggle while transcribing
        }
    }
    Ok(())
}

fn parse_hotkey(hotkey_str: &str) -> Option<HotKey> {
    let parts: Vec<&str> = hotkey_str.split('+').map(|s| s.trim()).collect();
    let mut modifiers = Modifiers::empty();
    let mut key_code = None;

    for part in &parts {
        match part.to_lowercase().as_str() {
            "ctrl" | "control" => modifiers |= Modifiers::CONTROL,
            "shift" => modifiers |= Modifiers::SHIFT,
            "alt" => modifiers |= Modifiers::ALT,
            "super" | "win" | "meta" => modifiers |= Modifiers::SUPER,
            other => {
                // Single letter or key name
                key_code = match other {
                    "a" => Some(Code::KeyA), "b" => Some(Code::KeyB), "c" => Some(Code::KeyC),
                    "d" => Some(Code::KeyD), "e" => Some(Code::KeyE), "f" => Some(Code::KeyF),
                    "g" => Some(Code::KeyG), "h" => Some(Code::KeyH), "i" => Some(Code::KeyI),
                    "j" => Some(Code::KeyJ), "k" => Some(Code::KeyK), "l" => Some(Code::KeyL),
                    "m" => Some(Code::KeyM), "n" => Some(Code::KeyN), "o" => Some(Code::KeyO),
                    "p" => Some(Code::KeyP), "q" => Some(Code::KeyQ), "r" => Some(Code::KeyR),
                    "s" => Some(Code::KeyS), "t" => Some(Code::KeyT), "u" => Some(Code::KeyU),
                    "v" => Some(Code::KeyV), "w" => Some(Code::KeyW), "x" => Some(Code::KeyX),
                    "y" => Some(Code::KeyY), "z" => Some(Code::KeyZ),
                    "space" => Some(Code::Space),
                    "f1" => Some(Code::F1), "f2" => Some(Code::F2), "f3" => Some(Code::F3),
                    "f4" => Some(Code::F4), "f5" => Some(Code::F5), "f6" => Some(Code::F6),
                    _ => None,
                };
            }
        }
    }

    key_code.map(|code| HotKey::new(Some(modifiers), code))
}

fn main() {
    let config = Config::load();
    let recorder = Recorder::new();
    let server = TranscriptionServer::new();

    let app_state = Arc::new(AppState {
        status: Mutex::new(AppStatus::Idle),
        recorder,
        server,
        config: config.clone(),
        last_transcription: Mutex::new(String::new()),
    });

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(app_state.clone())
        .invoke_handler(tauri::generate_handler![
            get_status,
            get_last_transcription,
            toggle_recording,
        ])
        .setup(move |app| {
            let app_handle = app.handle().clone();

            // Build tray menu
            let toggle_item = MenuItem::with_id(app.handle(), "toggle", "Start Recording", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app.handle(), "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app.handle(), &[&toggle_item, &quit_item])?;

            // Build tray icon
            let _tray = TrayIconBuilder::new()
                .menu(&menu)
                .tooltip("Scriptik")
                .on_menu_event(move |app, event| {
                    match event.id().as_ref() {
                        "toggle" => {
                            let app = app.clone();
                            let state = app.state::<Arc<AppState>>().inner().clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = do_toggle(app, &state).await;
                            });
                        }
                        "quit" => {
                            std::process::exit(0);
                        }
                        _ => {}
                    }
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            // Register global hotkey
            let hotkey_manager = GlobalHotKeyManager::new().expect("Failed to init hotkey manager");
            if let Some(hotkey) = parse_hotkey(&config.hotkey) {
                hotkey_manager.register(hotkey).expect("Failed to register hotkey");

                let app_handle_hotkey = app_handle.clone();
                let state_for_hotkey = app_state.clone();
                std::thread::spawn(move || {
                    // Keep manager alive
                    let _manager = hotkey_manager;
                    loop {
                        if let Ok(_event) = GlobalHotKeyEvent::receiver().recv() {
                            let app = app_handle_hotkey.clone();
                            let state = state_for_hotkey.clone();
                            tauri::async_runtime::spawn(async move {
                                let _ = do_toggle(app, &state).await;
                            });
                        }
                    }
                });
            }

            // Start transcription server in background
            let state_for_server = app_state.clone();
            tauri::async_runtime::spawn(async move {
                let python = TranscriptionServer::find_python();
                let script = TranscriptionServer::find_server_script();

                match (python, script) {
                    (Some(python), Some(script)) => {
                        let script_str = script.to_string_lossy().to_string();
                        if let Err(e) = state_for_server.server.start(
                            &python,
                            &state_for_server.config.whisper_model,
                            &script_str,
                        ).await {
                            eprintln!("Failed to start transcription server: {e}");
                        }
                    }
                    _ => {
                        eprintln!("Python or transcribe_server.py not found. Run setup.ps1 first.");
                    }
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 2: Write the frontend JavaScript**

```javascript
// scriptik-windows/src/main.js
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const statusEl = document.getElementById("status");
const transcriptionEl = document.getElementById("transcription");

// Listen for status changes from Rust backend
listen("status-changed", (event) => {
  statusEl.textContent = event.payload;
  statusEl.className = event.payload.toLowerCase();
});

listen("transcription-done", (event) => {
  transcriptionEl.textContent = event.payload;
  // Flash "copied" indicator
  const copied = document.createElement("div");
  copied.textContent = "Copied to clipboard";
  copied.className = "copied-toast";
  document.body.appendChild(copied);
  setTimeout(() => copied.remove(), 2000);
});

listen("transcription-error", (event) => {
  transcriptionEl.textContent = "Error: " + event.payload;
});

// Load initial state
async function init() {
  try {
    const status = await invoke("get_status");
    statusEl.textContent = JSON.parse(status);
    const text = await invoke("get_last_transcription");
    if (text) transcriptionEl.textContent = text;
  } catch (e) {
    console.error("Init error:", e);
  }
}

init();
```

- [ ] **Step 3: Update the HTML and CSS**

```html
<!-- scriptik-windows/src/index.html -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Scriptik</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div id="app">
    <h1>Scriptik</h1>
    <div id="status" class="idle">Idle</div>
    <div id="transcription-label">Last transcription:</div>
    <div id="transcription">No transcriptions yet</div>
  </div>
  <script src="main.js" type="module"></script>
</body>
</html>
```

```css
/* scriptik-windows/src/style.css */
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  background: #1e1e2e;
  color: #cdd6f4;
  padding: 16px;
  min-height: 250px;
}
h1 {
  font-size: 16px;
  font-weight: 600;
  margin-bottom: 12px;
  color: #89b4fa;
}
#status {
  font-size: 20px;
  font-weight: 700;
  margin-bottom: 16px;
  padding: 8px 12px;
  border-radius: 6px;
  text-align: center;
}
#status.idle { background: #313244; color: #a6adc8; }
#status.recording { background: #45243e; color: #f38ba8; }
#status.transcribing { background: #3e3529; color: #f9e2af; }
#transcription-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: #6c7086;
  margin-bottom: 4px;
}
#transcription {
  font-size: 13px;
  max-height: 140px;
  overflow-y: auto;
  white-space: pre-wrap;
  opacity: 0.85;
  line-height: 1.5;
  font-family: 'Cascadia Code', 'Consolas', monospace;
}
.copied-toast {
  position: fixed;
  bottom: 12px;
  left: 50%;
  transform: translateX(-50%);
  background: #a6e3a1;
  color: #1e1e2e;
  padding: 6px 16px;
  border-radius: 4px;
  font-size: 13px;
  font-weight: 600;
  animation: fadeout 2s forwards;
}
@keyframes fadeout {
  0%, 70% { opacity: 1; }
  100% { opacity: 0; }
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cd scriptik-windows/src-tauri && cargo check`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add scriptik-windows/
git commit -m "feat(windows): integrate tray, hotkey, audio, transcription, and frontend"
```

---

### Task 6: PowerShell Setup Script

**Files:**
- Create: `scriptik-windows/scripts/setup.ps1`

**Context:** Equivalent to `./scriptik-cli --setup` on macOS. Creates a Python venv, installs openai-whisper, and downloads the configured Whisper model. Should be run once before first use.

- [ ] **Step 1: Write setup.ps1**

```powershell
# scriptik-windows/scripts/setup.ps1
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
```

- [ ] **Step 2: Commit**

```bash
git add scriptik-windows/scripts/setup.ps1
git commit -m "feat(windows): add PowerShell setup script"
```

---

### Task 7: GitHub Actions CI

**Files:**
- Create: `scriptik-windows/.github/workflows/windows-build.yml`

**Context:** CI pipeline to verify the Tauri app builds on Windows. No audio or transcription tests (no mic in CI). Just build verification.

- [ ] **Step 1: Write the workflow**

```yaml
# scriptik-windows/.github/workflows/windows-build.yml
name: Windows Build

on:
  push:
    paths:
      - 'scriptik-windows/**'
  pull_request:
    paths:
      - 'scriptik-windows/**'

jobs:
  build:
    runs-on: windows-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Rust cache
        uses: Swatinem/rust-cache@v2
        with:
          workspaces: scriptik-windows/src-tauri

      - name: Install Tauri CLI
        run: cargo install tauri-cli --version "^2"

      - name: Build Tauri app
        working-directory: scriptik-windows
        run: cargo tauri build
        env:
          # Skip code signing for CI
          TAURI_SIGNING_PRIVATE_KEY: ""

      - name: Upload MSI
        uses: actions/upload-artifact@v4
        with:
          name: scriptik-windows-msi
          path: scriptik-windows/src-tauri/target/release/bundle/msi/*.msi
          if-no-files-found: warn
```

- [ ] **Step 2: Commit**

```bash
git add scriptik-windows/.github/
git commit -m "ci(windows): add GitHub Actions build workflow"
```

---

### Task 8: README

**Files:**
- Create: `scriptik-windows/README.md`

- [ ] **Step 1: Write README**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add scriptik-windows/README.md
git commit -m "docs(windows): add README"
```

---

## Task Dependency Graph

```
Task 1 (Scaffolding)
├── Task 2 (Config)      ─┐
├── Task 3 (Audio)        ├── Task 5 (Integration)
├── Task 4 (Transcriber) ─┘
├── Task 6 (Setup Script)     [independent]
├── Task 7 (CI)                [independent]
└── Task 8 (README)            [independent]
```

**Parallelizable groups:**
- **Group A** (after Task 1): Tasks 2, 3, 4, 6, 7, 8 — all independent
- **Group B** (after Group A): Task 5 — depends on Tasks 2, 3, 4
