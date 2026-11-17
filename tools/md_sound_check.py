#!/usr/bin/env python3
"""Compares how a Mega Drive song sounds in the app's preview and elsewhere.

    python3 tools/md_sound_check.py preview.wav other.wav [--align] [--min-corr 0.7]

Both files are WAVs (any rate, 16-bit, mono or stereo). Each is cut into
blocks of 1/10 s and measured: loudness (RMS) and brightness (zero
crossings per second). The other file must make sound through most of the
song, and its loudness must rise and fall with the preview's (correlation
at least --min-corr), which shows the notes, envelopes and levels land in
the same places. --align first finds the best offset within 3 s, in
steps of 1/100 s, for recordings that start late (a ROM's boot). Brightness is printed so the
preview's FM tone can be compared with an accurate YM2612 core.
Exits 1 if the check fails.
"""
import math
import struct
import sys

BLOCK_SECONDS = 0.1


def read_wav(path):
    """Returns (rate, channels, 16-bit PCM bytes). Reads plain and
    WAVE_FORMAT_EXTENSIBLE headers (libvgm writes the latter)."""
    data = open(path, "rb").read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        sys.exit(f"{path}: not a WAV file")
    i = 12
    fmt = None
    while i + 8 <= len(data):
        tag, size = data[i:i + 4], struct.unpack_from("<I", data, i + 4)[0]
        body = data[i + 8:i + 8 + size]
        if tag == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", body)
        elif tag == b"data":
            if fmt is None or fmt[0] not in (1, 0xFFFE) or fmt[5] != 16:
                sys.exit(f"{path}: expected 16-bit PCM")
            return fmt[2], fmt[1], body
        i += 8 + size + (size & 1)
    sys.exit(f"{path}: no data chunk")


def read_mono(path, seconds):
    rate, channels, raw = read_wav(path)
    raw = raw[:int(rate * seconds) * channels * 2]
    values = struct.unpack(f"<{len(raw) // 2}h", raw)
    return rate, [sum(values[i:i + channels]) / channels / 32768.0 for i in range(0, len(values), channels)]


def best_offset(preview_loudness, path, seconds, search_seconds=3.0, steps=10):
    """The offset (samples) into the file at path, in steps of 1/steps of a
    block, whose block loudness best follows preview_loudness."""
    rate, mono = read_mono(path, seconds)
    sub = int(rate * BLOCK_SECONDS) // steps
    sums, squares = [], []
    for start in range(0, len(mono) - sub + 1, sub):
        chunk = mono[start:start + sub]
        sums.append(sum(chunk))
        squares.append(sum(x * x for x in chunk))
    size = sub * steps
    best, best_shift = -2.0, 0
    for shift in range(0, int(search_seconds / BLOCK_SECONDS * steps) + 1):
        loud = []
        for b in range(shift, len(sums) - steps + 1, steps):
            total = sum(sums[b:b + steps])
            mean = total / size
            loud.append(math.sqrt(max(sum(squares[b:b + steps]) / size - mean * mean, 0.0)))
        if len(loud) < 2:
            break
        c = correlation(preview_loudness, loud)
        if c > best:
            best, best_shift = c, shift
    return best_shift * sub


def blocks(path, seconds, skip=0):
    rate, mono = read_mono(path, seconds)
    mono = mono[skip:]
    size = int(rate * BLOCK_SECONDS)
    out = []
    for start in range(0, len(mono) - size + 1, size):
        chunk = mono[start:start + size]
        mean = sum(chunk) / size
        rms = math.sqrt(sum((x - mean) ** 2 for x in chunk) / size)
        crossings = sum(1 for a, b in zip(chunk, chunk[1:]) if (a - mean < 0) != (b - mean < 0))
        out.append((rms, crossings / BLOCK_SECONDS / 2))
    return out


def correlation(a, b):
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    ma, mb = sum(a) / n, sum(b) / n
    cov = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    va = math.sqrt(sum((x - ma) ** 2 for x in a))
    vb = math.sqrt(sum((y - mb) ** 2 for y in b))
    return cov / (va * vb) if va > 0 and vb > 0 else 0.0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    align = "--align" in sys.argv
    min_corr = 0.7
    if "--min-corr" in sys.argv:
        min_corr = float(sys.argv[sys.argv.index("--min-corr") + 1])
        args.remove(sys.argv[sys.argv.index("--min-corr") + 1])
    if len(args) != 2:
        sys.exit(__doc__)
    preview = blocks(args[0], 12)
    loud_p = [b[0] for b in preview]
    skip = best_offset(loud_p, args[1], 16) if align else 0
    other = blocks(args[1], 16 if align else 12, skip)[:len(loud_p)]
    loud_o = [b[0] for b in other]
    shift = skip / read_wav(args[1])[0] / BLOCK_SECONDS if skip else 0
    n = min(len(loud_p), len(loud_o))
    if n < 50:
        sys.exit(f"{args[1]}: too short to compare")
    corr = correlation(loud_p[:n], loud_o[:n])
    peak = max(loud_o[:n])
    quiet = sum(1 for x in loud_o[10:n] if x < peak * 0.05)
    level = (sum(loud_o[:n]) / n) / max(sum(loud_p[:n]) / n, 1e-9)
    bright_p = sum(b[1] for b in preview[:n] if b[0] > 0.01) / max(1, sum(1 for b in preview[:n] if b[0] > 0.01))
    bright_o = sum(b[1] for b in other[:n] if b[0] > 0.01) / max(1, sum(1 for b in other[:n] if b[0] > 0.01))
    bright_corr = correlation([b[1] for b in preview[:n]], [b[1] for b in other[:n]])
    late = f", starting {shift * BLOCK_SECONDS:.2f} s late" if shift else ""
    print(f"{args[1]}{late}: loudness follows the preview with correlation {corr:.2f}; "
          f"level {level:.2f}x the preview's; brightness {bright_o:.0f} vs {bright_p:.0f} crossings/s "
          f"(correlation {bright_corr:.2f}); {quiet} of {n - 10} blocks near silent")
    failed = False
    if peak < 0.01:
        print("  FAIL: no sound")
        failed = True
    if quiet > (n - 10) * 0.2:
        print("  FAIL: silent for too much of the song")
        failed = True
    if corr < min_corr:
        print(f"  FAIL: loudness correlation under {min_corr}")
        failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
