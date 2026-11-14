#!/usr/bin/env python3
"""Runs a Mega Drive ROM in an emulator and records what it plays.

    python3 tools/md_rom_audio.py rom.bin out.wav [seconds]

Uses stable-retro (pip install stable-retro), which bundles the Genesis
Plus GX core, to run the ROM headless for the given time (default 15 s)
and writes the sound as a 16-bit stereo WAV. CI uses it to hear the
example ROM that SGDK built: the XGM driver on the Z80 playing our music.
"""
import os
import shutil
import struct
import sys
import tempfile
import wave

import retro


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    seconds = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0
    # The core is picked by the file extension.
    tmp = tempfile.mkdtemp()
    rom = os.path.join(tmp, "rom.md")
    shutil.copy(sys.argv[1], rom)
    emu = retro.RetroEmulator(rom)
    rate = int(round(emu.get_audio_rate()))
    fps = 60.0
    frames = int(seconds * fps)
    pcm = bytearray()
    for _ in range(frames):
        emu.step()
        audio = emu.get_audio()
        pcm += audio.astype("<i2").tobytes()
    with wave.open(sys.argv[2], "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(pcm))
    samples = len(pcm) // 4
    peak = max(abs(v) for v in struct.unpack(f"<{len(pcm) // 2}h", bytes(pcm))) if pcm else 0
    print(f"{sys.argv[1]}: {frames} frames, {samples} samples at {rate} Hz, peak {peak}")


if __name__ == "__main__":
    main()
