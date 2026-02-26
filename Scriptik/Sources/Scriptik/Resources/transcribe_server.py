#!/usr/bin/env python3
"""Persistent Whisper transcription server for Scriptik.

Loads the model once on startup, then listens for JSON commands on stdin
and writes JSON responses to stdout (newline-delimited JSON).

Usage:
    PYTHONUNBUFFERED=1 python3 transcribe_server.py <model_name>
"""
import sys
import os
import json
import time
import warnings
import tempfile
import wave
import struct

warnings.filterwarnings("ignore")

# ── Model loading ──────────────────────────────────────────────────────

MLX_MODEL_MAP = {
    "tiny":   "mlx-community/whisper-tiny-mlx",
    "base":   "mlx-community/whisper-base-mlx",
    "small":  "mlx-community/whisper-small-mlx",
    "medium": "mlx-community/whisper-medium-mlx",
    "large":  "mlx-community/whisper-large-v3-mlx",
}

USE_MLX = False
mlx_whisper = None
whisper = None

try:
    import mlx_whisper as _mlx_whisper
    mlx_whisper = _mlx_whisper
    USE_MLX = True
except ImportError:
    import whisper as _whisper
    whisper = _whisper

cache_dir = os.path.join(os.environ.get("HOME", "/tmp"), ".cache", "whisper")

# Global model state
current_model_name = None
current_model = None  # Only used for openai-whisper


def send(obj):
    """Write a JSON line to stdout and flush."""
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def make_silent_wav(path, duration=0.5, sample_rate=16000):
    """Create a tiny silent WAV file for MLX warm-up."""
    n_frames = int(sample_rate * duration)
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(struct.pack(f"<{n_frames}h", *([0] * n_frames)))


def load_model(model_name):
    """Load (or reload) the whisper model."""
    global current_model_name, current_model

    if USE_MLX:
        repo = MLX_MODEL_MAP.get(model_name, MLX_MODEL_MAP["medium"])
        # MLX caches lazily, so do a dummy transcribe to force loading
        tmp_wav = os.path.join(tempfile.gettempdir(), "scriptik_warmup.wav")
        make_silent_wav(tmp_wav)
        try:
            mlx_whisper.transcribe(tmp_wav, path_or_hf_repo=repo)
        except Exception:
            pass  # Warm-up errors are non-fatal
        finally:
            try:
                os.unlink(tmp_wav)
            except OSError:
                pass
        current_model = None  # MLX doesn't hold a model object
    else:
        current_model = whisper.load_model(model_name, download_root=cache_dir)

    current_model_name = model_name
    backend = "mlx" if USE_MLX else "openai-whisper"
    return backend


def do_transcribe(request):
    """Run transcription and return response dict."""
    recording_path = request["recording_path"]
    transcription_path = request["transcription_path"]
    pause_threshold = float(request.get("pause_threshold", 1.5))
    model_name = request.get("model", current_model_name or "medium")
    initial_prompt = request.get("initial_prompt", "") or None
    language = request.get("language", "auto")
    if language == "auto":
        language = None

    # Reload model if it changed
    if model_name != current_model_name:
        load_model(model_name)

    t0 = time.time()

    if USE_MLX:
        repo = MLX_MODEL_MAP.get(current_model_name, MLX_MODEL_MAP["medium"])
        transcribe_opts = dict(
            path_or_hf_repo=repo,
            word_timestamps=True,
            condition_on_previous_text=False,
            no_speech_threshold=0.05,
            logprob_threshold=-2.0,
            compression_ratio_threshold=2.8,
        )
        if language:
            transcribe_opts["language"] = language
        if initial_prompt:
            transcribe_opts["initial_prompt"] = initial_prompt

        result = mlx_whisper.transcribe(recording_path, **transcribe_opts)

        # Auto-detect: restrict to Hebrew/English
        if not language:
            detected = result.get("language", "en")
            if detected not in ("he", "en"):
                transcribe_opts["language"] = "en"
                result = mlx_whisper.transcribe(recording_path, **transcribe_opts)
    else:
        if language is None:
            import numpy as np
            audio = whisper.load_audio(recording_path)
            audio_padded = whisper.pad_or_trim(audio)
            mel = whisper.log_mel_spectrogram(audio_padded).to(current_model.device)
            _, probs = current_model.detect_language(mel)
            allowed = {"he": probs.get("he", 0), "en": probs.get("en", 0)}
            language = max(allowed, key=allowed.get)

        transcribe_opts = dict(
            language=language,
            word_timestamps=True,
            condition_on_previous_text=False,
            no_speech_threshold=0.05,
            logprob_threshold=-2.0,
            compression_ratio_threshold=2.8,
        )
        if initial_prompt:
            transcribe_opts["initial_prompt"] = initial_prompt

        result = current_model.transcribe(recording_path, **transcribe_opts)

    # ── Format output (same logic as transcribe.py) ──
    output_lines = []
    prev_end = 0.0

    for segment in result["segments"]:
        words = segment.get("words", [])
        if not words:
            gap = segment["start"] - prev_end
            if gap >= pause_threshold and prev_end > 0:
                output_lines.append(
                    f'  [{prev_end:.1f}s --> {segment["start"]:.1f}s] [pause {gap:.1f}s]'
                )
            output_lines.append(
                f'  [{segment["start"]:.1f}s --> {segment["end"]:.1f}s] {segment["text"].strip()}'
            )
            prev_end = segment["end"]
            continue

        for word_info in words:
            gap = word_info["start"] - prev_end
            if gap >= pause_threshold and prev_end > 0:
                output_lines.append(
                    f'  [{prev_end:.1f}s --> {word_info["start"]:.1f}s] [pause {gap:.1f}s]'
                )
            prev_end = word_info["end"]

        text = segment["text"].strip()
        output_lines.append(
            f'  [{segment["start"]:.1f}s --> {segment["end"]:.1f}s] {text}'
        )
        prev_end = segment["end"]

    # Filter repeated hallucinated segments
    filtered = []
    prev_text = ""
    for line in output_lines:
        parts = line.rsplit("] ", 1)
        text = parts[-1].strip() if len(parts) > 1 else line.strip()
        if text.startswith("[pause"):
            filtered.append(line)
        elif text != prev_text:
            filtered.append(line)
            prev_text = text

    output = "\n".join(filtered)
    with open(transcription_path, "w", encoding="utf-8") as f:
        f.write(output)

    duration = time.time() - t0
    return {"type": "transcription_done", "text": output, "duration_seconds": round(duration, 2)}


# ── Main loop ──────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: transcribe_server.py <model_name>", file=sys.stderr)
        sys.exit(1)

    model_name = sys.argv[1]

    # Load model and send ready signal
    backend = load_model(model_name)
    send({"type": "ready", "model": model_name, "backend": backend})

    # Process commands from stdin
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError as e:
            send({"type": "error", "message": f"Invalid JSON: {e}"})
            continue

        cmd_type = request.get("type", "")

        try:
            if cmd_type == "ping":
                send({"type": "pong"})

            elif cmd_type == "transcribe":
                response = do_transcribe(request)
                send(response)

            elif cmd_type == "reload_model":
                new_model = request.get("model", "medium")
                backend = load_model(new_model)
                send({"type": "model_reloaded", "model": new_model, "backend": backend})

            else:
                send({"type": "error", "message": f"Unknown command type: {cmd_type}"})

        except Exception as e:
            send({"type": "error", "message": str(e)})


if __name__ == "__main__":
    main()
