#!/usr/bin/env python3
"""Whisper daemon — loads model once, transcribes on demand.

Protocol (stdin/stdout, line-based):
  Startup: prints "READY" when model is loaded
  Input:   path to WAV file (one per line)
  Output:  transcript text (one per line, empty string if nothing recognized)
"""

import os
import sys

def main():
    model_name = os.environ.get("WHISPER_MODEL", "small")

    # Suppress warnings from ctranslate2/torch
    os.environ["CT2_VERBOSE"] = "0"
    import logging
    logging.disable(logging.WARNING)

    from faster_whisper import WhisperModel

    print(f"Loading Whisper model '{model_name}'...", file=sys.stderr)
    model = WhisperModel(model_name, device="cpu", compute_type="int8")
    print(f"Model ready.", file=sys.stderr)

    # Signal ready
    sys.stdout.write("READY\n")
    sys.stdout.flush()

    for line in sys.stdin:
        path = line.strip()
        if not path:
            sys.stdout.write("\n")
            sys.stdout.flush()
            continue

        try:
            segments, info = model.transcribe(
                path,
                language=None,
                beam_size=5,
                vad_filter=True,
                vad_parameters=dict(min_silence_duration_ms=500),
            )
            text = " ".join(s.text.strip() for s in segments)
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            text = ""

        sys.stdout.write(text + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
