#!/usr/bin/env python3
"""Checks that a WAV FamiStudio rendered from an exported project makes sound.

    python3 tools/nes_check.py song.wav [min_seconds]

Exits 1 if the file is missing, too short, or silent.
"""
import array
import sys
import wave


def main() -> int:
    path = sys.argv[1]
    min_seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 0.1
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        frames = w.getnframes()
        width = w.getsampwidth()
        data = w.readframes(frames)
    if width != 2:
        print(f"{path}: expected 16-bit samples, got {width * 8}-bit")
        return 1
    samples = array.array("h", data)
    seconds = frames / rate
    peak = max((abs(s) for s in samples), default=0) / 32768.0
    print(f"{path}: {seconds:.2f} s, peak {peak:.3f}")
    if seconds < min_seconds:
        print("too short")
        return 1
    if peak < 0.02:
        print("silent")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
