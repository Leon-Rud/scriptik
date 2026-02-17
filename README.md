# Record Toggle

A global keyboard shortcut for macOS that records audio and transcribes it using [OpenAI Whisper](https://github.com/openai/whisper) — all running locally on your machine.

Press once to **start recording**. Press again to **stop, transcribe, and copy to clipboard**.

![macOS](https://img.shields.io/badge/macOS-only-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## How it works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Press       │     │  QuickTime  │     │   Whisper    │     │  Copied to  │
│  Shortcut    │────▶│  Records    │────▶│  Transcribes │────▶│  Clipboard  │
│  (start)     │     │  Audio      │     │  Locally     │     │  (paste!)   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                                                            │
       │              ┌─────────────┐                               │
       └─────────────▶│  Press       │◀──────────────────────────────┘
                      │  Shortcut    │
                      │  (stop)      │
                      └─────────────┘
```

**Features:**
- Works from **any app** via global keyboard shortcut
- **100% local** — no audio leaves your machine
- Auto-detects language (English, Hebrew, and more)
- Timestamps and pause detection in output
- Filters Whisper hallucinations automatically
- macOS notifications for recording state
- Configurable model, prompts, and thresholds

## Install

```bash
git clone https://github.com/Leon-Rud/record-toggle.git
cd record-toggle
./install.sh
```

The installer will:
1. Install the `record-toggle` command
2. Set up a Python environment with Whisper
3. Download the Whisper model (~500MB for `small`)
4. Create a macOS Quick Action for keyboard shortcut binding
5. Open System Settings so you can assign your shortcut

### Requirements

- **macOS** (uses QuickTime Player for recording)
- **Python 3** (`brew install python3` if needed)
- ~1GB disk space (Python venv + Whisper model)

## Usage

After installing and assigning a keyboard shortcut:

1. **Press your shortcut** — recording starts (notification confirms)
2. **Press again** — recording stops, transcription begins
3. **Paste** — transcription is on your clipboard

### Output format

```
  [0.0s --> 2.3s] So the main challenge here was the database schema
  [2.3s --> 4.1s] [pause 1.8s]
  [4.1s --> 8.7s] We decided to use a normalized approach with foreign keys
```

### CLI

```bash
record-toggle            # Toggle recording on/off
record-toggle --setup    # Install Whisper and create config
record-toggle --status   # Check if currently recording
record-toggle --log      # View recent log entries
record-toggle --help     # Show help
```

## Configuration

Edit `~/.config/record-toggle/config`:

```bash
# Whisper model: tiny, base, small, medium, large
# Smaller = faster, larger = more accurate
WHISPER_MODEL="small"

# Seconds of silence before marking a [pause]
PAUSE_THRESHOLD="1.5"

# Hint words to improve transcription accuracy
# Add domain-specific terms, names, or filler words
INITIAL_PROMPT="Docker, FastAPI, PostgreSQL, React"
```

### Model comparison

| Model    | Size   | Speed    | Accuracy |
|----------|--------|----------|----------|
| `tiny`   | 75MB   | ~1s      | Basic    |
| `base`   | 140MB  | ~2s      | Good     |
| `small`  | 500MB  | ~5s      | Great    |
| `medium` | 1.5GB  | ~15s     | Excellent|
| `large`  | 3GB    | ~30s     | Best     |

## Uninstall

```bash
./uninstall.sh
```

Removes the script, Quick Action, config, and Whisper environment.

## Troubleshooting

### No audio recorded
QuickTime Player needs microphone permission. Go to **System Settings > Privacy & Security > Microphone** and ensure QuickTime Player is enabled.

### Transcription is empty or wrong
- Try a larger model: edit `WHISPER_MODEL="medium"` in your config
- Add context words to `INITIAL_PROMPT` for domain-specific terms
- Check logs: `record-toggle --log`

### Shortcut not working
1. Open **System Settings > Keyboard > Keyboard Shortcuts > Services**
2. Look for "Record Toggle" under General
3. Make sure it has a shortcut assigned and is enabled

### Recording stuck
If you see "Recording started" but pressing again doesn't stop it:
```bash
rm /tmp/record-toggle/recording.pid
```

## License

MIT
