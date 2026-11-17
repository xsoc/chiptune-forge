#!/usr/bin/env python3
"""Checks OGG Vorbis exports against the WAVs they were made from.

Each OGG is decoded with libvorbis (oggdec) and with FFmpeg's own decoder.
Both must give the WAV's length, sample rate and channels back, close to
the original (signal-to-noise ratio of at least 15 dB), and a looping
song's loop must be in the LOOPSTART and LOOPLENGTH tags.

Usage: check_ogg.py file.ogg [...]   (file.wav must sit beside each one)
"""
import array
import math
import os
import subprocess
import sys
import tempfile
import wave


def read_wav(path):
    with wave.open(path) as w:
        assert w.getsampwidth() == 2, path
        data = array.array("h", w.readframes(w.getnframes()))
        return w.getnchannels(), w.getframerate(), data


def loop_from_wav(path):
    with open(path, "rb") as f:
        raw = f.read()
    at = raw.find(b"smpl")
    if at < 0:
        return None
    body = at + 8
    start = int.from_bytes(raw[body + 44:body + 48], "little")
    end = int.from_bytes(raw[body + 48:body + 52], "little") + 1
    return start, end - start


def snr(reference, decoded):
    n = min(len(reference), len(decoded))
    signal = sum(x * x for x in reference[:n]) or 1
    noise = sum((reference[i] - decoded[i]) ** 2 for i in range(n)) or 1
    return 10 * math.log10(signal / noise)


def check(ogg):
    wav_path = os.path.splitext(ogg)[0] + ".wav"
    channels, rate, reference = read_wav(wav_path)
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "oggdec.wav")
        subprocess.run(["oggdec", "-Q", "-o", out, ogg], check=True)
        results = {"libvorbis": read_wav(out)}
        out = os.path.join(tmp, "ffmpeg.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg, "-c:a", "pcm_s16le", out], check=True)
        results["ffmpeg"] = read_wav(out)
    for name, (c, r, data) in results.items():
        assert (c, r) == (channels, rate), f"{ogg}: {name} gives {c} channels at {r} Hz"
        assert len(data) == len(reference), f"{ogg}: {name} gives {len(data) // c} frames, not {len(reference) // c}"
        ratio = snr(reference, data)
        assert ratio >= 15, f"{ogg}: {name} SNR {ratio:.1f} dB"
        print(f"{ogg}: {name} ok, {len(data) // c} frames, SNR {ratio:.1f} dB")
    tags = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream_tags", "-of", "default=nw=1", ogg],
                          capture_output=True, text=True, check=True).stdout.upper()
    loop = loop_from_wav(wav_path)
    if loop:
        assert f"LOOPSTART={loop[0]}" in tags and f"LOOPLENGTH={loop[1]}" in tags, f"{ogg}: loop tags missing: {tags}"
    kbps = os.path.getsize(ogg) * 8 / (len(reference) / channels / rate) / 1000
    print(f"{ogg}: {kbps:.0f} kbps, tags ok")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        check(path)
