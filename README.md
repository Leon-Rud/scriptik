# Record Toggle

A global keyboard shortcut for macOS that records audio and transcribes it using [OpenAI Whisper](https://github.com/openai/whisper) — all running locally on your machine.

Press once to **start recording**. Press again to **stop, transcribe, and copy to clipboard**.

![macOS](https://img.shields.io/badge/macOS_14+-only-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## How it works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Press       │     │  Native     │     │   Whisper    │     │  Copied to  │
│  Shortcut    │────>│  Records    │────>│  Transcribes │────>│  Clipboard  │
│  (start)     │     │  Audio      │     │  Locally     │     │  + paste    │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

**Features:**
- **Native macOS app** — windowed app with Dock icon
- **Global hotkey** — toggle recording from any app
- **100% local** — no audio leaves your machine
- **Floating indicator** — shows recording time and live waveform
- Auto-detects language (English, Hebrew, and more)
- Timestamps and pause detection in output
- Filters Whisper hallucinations automatically
- Configurable model, prompts, and thresholds
- Transcription history with search

## Prerequisites

- **macOS 14+** (Sonoma)
- **Swift 5.10+** (via Homebrew: `brew install swift`)
- **Python 3** (for Whisper)
- **ffmpeg** (`brew install ffmpeg`)

## Install

### Native App (recommended)

```bash
git clone https://github.com/Leon-Rud/record-toggle.git
cd record-toggle

# Set up Whisper (Python venv + model download)
./record-toggle --setup

# Build and install the native app
make install
```

Then launch **Record Toggle** from Applications or Spotlight.

### CLI-only (alternative)

If you prefer a command-line tool without the native app:

```bash
git clone https://github.com/Leon-Rud/record-toggle.git
cd record-toggle
./install.sh
```

## Usage

### Native App

1. Launch **Record Toggle** from /Applications or Spotlight
2. Click **Record** or press your global shortcut to start
3. A floating indicator appears showing elapsed time and audio waveform
4. Click **Stop** or press the shortcut again
5. Transcription runs locally — the result card shows your text
6. Text is automatically copied to clipboard (and auto-pasted if enabled)

**Settings** — configure Whisper model, language, shortcut, and more from the app window.

**History** — browse and search all past transcriptions.

> **Auto-paste setup:** For auto-paste to work, grant Accessibility permission at
> **System Settings > Privacy & Security > Accessibility** and enable Record Toggle.

### CLI

```bash
record-toggle            # Toggle recording on/off
record-toggle --setup    # Install Whisper and create config
record-toggle --status   # Check if currently recording
record-toggle --log      # View recent log entries
record-toggle --help     # Show help
```

### Output format

```
  [0.0s --> 2.3s] So the main challenge here was the database schema
  [2.3s --> 4.1s] [pause 1.8s]
  [4.1s --> 8.7s] We decided to use a normalized approach with foreign keys
```

## Configuration

Edit `~/.config/record-toggle/config` (shared between app and CLI):

```bash
# Whisper model: tiny, base, small, medium, large
WHISPER_MODEL="medium"

# Seconds of silence before marking a [pause]
PAUSE_THRESHOLD="1.5"

# Hint words to improve transcription accuracy
INITIAL_PROMPT="Docker, FastAPI, PostgreSQL, React"

# Auto-paste transcription into active app
AUTO_PASTE="true"

# Language: auto, en, he
LANGUAGE="auto"
```

### Model comparison

| Model    | Size   | Speed    | Accuracy |
|----------|--------|----------|----------|
| `tiny`   | 75MB   | ~1s      | Basic    |
| `base`   | 140MB  | ~2s      | Good     |
| `small`  | 500MB  | ~5s      | Great    |
| `medium` | 1.5GB  | ~15s     | Excellent|
| `large`  | 3GB    | ~30s     | Best     |

## Building from source

```bash
cd RecordToggle
swift build          # Debug build
swift build -c release  # Release build
bash scripts/bundle.sh  # Create .app bundle
```

The app bundle is output to `RecordToggle/build/Record Toggle.app`.

## Uninstall

```bash
./uninstall.sh
```

Removes the CLI script, Quick Action, config, and Whisper environment.

To remove the native app: delete `Record Toggle.app` from Applications.

## Troubleshooting

### Microphone permission
The app needs microphone access. Go to **System Settings > Privacy & Security > Microphone** and enable Record Toggle.

### Auto-paste not working
Auto-paste requires Accessibility permission. Go to **System Settings > Privacy & Security > Accessibility** and enable Record Toggle.

### Transcription is empty or wrong
- Try a larger model in Settings (or edit `WHISPER_MODEL="medium"` in config)
- Add context words to the initial prompt for domain-specific terms
- Check logs: `record-toggle --log`

### Global shortcut not working
Open the app's Settings and set your preferred key combination in the Shortcut tab.

## License

MIT
