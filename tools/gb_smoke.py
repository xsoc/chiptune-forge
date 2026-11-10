"""Runs a Game Boy ROM headless in PyBoy and fails if it stays silent.

    python3 tools/gb_smoke.py rom.gb [seconds] [buttons]

[buttons] is a list of presses such as "a" or "down,a", sent one a second
after the first second (the sound kit example plays a sound on A).
"""
import sys

import numpy as np
from pyboy import PyBoy

rom = sys.argv[1]
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 8.0
presses = [b for b in sys.argv[3].split(",") if b] if len(sys.argv) > 3 else []

pb = PyBoy(rom, window="null", sound_emulated=True, sound_sample_rate=44100)
pb.set_emulation_speed(0)
chunks = []
for frame in range(int(seconds * 59.73)):
    second, offset = divmod(frame, 60)
    if offset == 0 and 1 <= second <= len(presses):
        pb.button(presses[second - 1], 4)
    pb.tick(1, False, True)
    # Skip the first second: the console's power-on state can still be
    # sounding the end of the boot chime.
    if second >= 1:
        chunks.append(np.array(pb.sound.ndarray, copy=True))
pb.stop(False)

audio = np.concatenate(chunks).astype(np.float32)
# Remove the DC level the emulated DAC leaves, so silence reads as 0.
audio -= audio.mean(axis=0)
rms = float(np.sqrt(np.mean(audio ** 2)))
peak = float(np.max(np.abs(audio)))
print(f"{rom}: {audio.shape[0]} samples, rms {rms:.2f}, peak {peak:.0f}")
if rms < 1.0:
    print("The ROM is silent.")
    sys.exit(1)
