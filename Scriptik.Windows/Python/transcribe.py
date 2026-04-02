"""One-shot Whisper transcription script for Scriptik (Windows).

Usage:
    python transcribe.py <recording_path> <transcription_path> <pause_threshold> <model> [initial_prompt] [language]
"""
import sys
import os
import time
import warnings

warnings.filterwarnings("ignore")

# Fix stdout/stderr encoding on Windows
if sys.platform == "win32":
    sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)
    sys.stderr = open(sys.stderr.fileno(), mode='w', encoding='utf-8', buffering=1)

import whisper

cache_dir = os.path.join(
    os.environ.get("USERPROFILE", os.environ.get("HOME", os.path.expanduser("~"))),
    ".cache", "whisper"
)


def main():
    if len(sys.argv) < 5:
        print("Usage: transcribe.py <recording_path> <transcription_path> <pause_threshold> <model> [initial_prompt] [language]",
              file=sys.stderr)
        sys.exit(1)

    recording_path = sys.argv[1]
    transcription_path = sys.argv[2]
    pause_threshold = float(sys.argv[3])
    model_name = sys.argv[4]
    initial_prompt = sys.argv[5] if len(sys.argv) > 5 else ""
    language = sys.argv[6] if len(sys.argv) > 6 else "auto"

    if not initial_prompt:
        initial_prompt = None
    if language == "auto":
        language = None

    t0 = time.time()

    # Load model
    model = whisper.load_model(model_name, download_root=cache_dir)

    # Auto-detect language (restrict to Hebrew/English)
    if language is None:
        import numpy as np
        audio = whisper.load_audio(recording_path)
        audio_padded = whisper.pad_or_trim(audio)
        mel = whisper.log_mel_spectrogram(audio_padded).to(model.device)
        _, probs = model.detect_language(mel)
        allowed = {"he": probs.get("he", 0), "en": probs.get("en", 0)}
        language = max(allowed, key=allowed.get)

    # Transcribe
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

    result = model.transcribe(recording_path, **transcribe_opts)

    # Format output
    output_lines = []
    prev_end = 0.0

    for segment in result["segments"]:
        words = segment.get("words", [])
        if not words:
            gap = segment["start"] - prev_end
            if gap >= pause_threshold and prev_end > 0:
                output_lines.append(
                    f'[{prev_end:.1f}s --> {segment["start"]:.1f}s] [pause {gap:.1f}s]'
                )
            output_lines.append(
                f'[{segment["start"]:.1f}s --> {segment["end"]:.1f}s]  {segment["text"].strip()}'
            )
            prev_end = segment["end"]
            continue

        for word_info in words:
            gap = word_info["start"] - prev_end
            if gap >= pause_threshold and prev_end > 0:
                output_lines.append(
                    f'[{prev_end:.1f}s --> {word_info["start"]:.1f}s] [pause {gap:.1f}s]'
                )
            prev_end = word_info["end"]

        text = segment["text"].strip()
        output_lines.append(
            f'[{segment["start"]:.1f}s --> {segment["end"]:.1f}s]  {text}'
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
    print(f"Transcription complete in {duration:.1f}s", file=sys.stderr)


if __name__ == "__main__":
    main()
