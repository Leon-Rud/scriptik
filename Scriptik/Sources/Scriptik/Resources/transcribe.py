#!/usr/bin/env python3
"""Whisper transcription script for Scriptik.

Usage:
    python3 transcribe.py <recording.wav> <output.txt> <pause_threshold> <model> [initial_prompt] [language]
"""
import sys
import whisper
import warnings
warnings.filterwarnings("ignore")

recording_file = sys.argv[1]
transcription_file = sys.argv[2]
pause_threshold = float(sys.argv[3])
model_name = sys.argv[4]
initial_prompt = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None
language = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] != "auto" else None

import os
cache_dir = os.path.join(os.environ.get("HOME", "/tmp"), ".cache", "whisper")
model = whisper.load_model(model_name, download_root=cache_dir)

# When auto-detecting, restrict to Hebrew and English only
if language is None:
    import numpy as np
    audio = whisper.load_audio(recording_file)
    audio_padded = whisper.pad_or_trim(audio)
    mel = whisper.log_mel_spectrogram(audio_padded).to(model.device)
    _, probs = model.detect_language(mel)
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

result = model.transcribe(recording_file, **transcribe_opts)

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
with open(transcription_file, "w", encoding="utf-8") as f:
    f.write(output)
