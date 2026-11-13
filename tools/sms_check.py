#!/usr/bin/env python3
"""Checks PSGlib data the app exported against PSGlib's own tools' output.

    python3 tools/sms_check.py ours.psg theirs.psg [more.psg ...]

Plays each file the way PSGlib's PSGFrame does (latch and data bytes go to
the chip, $38-$3F wait, $01 marks the loop, $00 ends) and records the chip's
registers after every frame, up to the end of the first pass. Every file
must give the same registers frame by frame as the first one, so a file
from vgm2psg (which drops writes that change nothing) matches ours. Also
checks that the data uses only uncompressed PSGlib commands and makes
sound. Exits 1 on any difference.
"""
import sys


def play(path):
    data = open(path, "rb").read()
    tone = [0, 0, 0]
    att = [15, 15, 15, 15]
    noise = 0
    latch = 0
    frames = []
    loops = 0
    i = 0
    while i < len(data):
        b = data[i]
        i += 1
        if b & 0x80:
            latch = (b >> 4) & 7
            ch, vol = latch >> 1, latch & 1
            if vol:
                att[ch] = b & 15
            elif ch < 3:
                tone[ch] = (tone[ch] & 0x3F0) | (b & 15)
            else:
                noise = b & 7
        elif b >= 0x40:
            ch, vol = latch >> 1, latch & 1
            if vol:
                att[ch] = b & 15
            elif ch < 3:
                tone[ch] = (tone[ch] & 15) | ((b & 0x3F) << 4)
            else:
                noise = b & 7
        elif 0x38 <= b <= 0x3F:
            state = (tuple(tone), tuple(att), noise)
            frames.extend([state] * (b - 0x37))
        elif b == 0x01:
            loops += 1
        elif b == 0x00:
            break
        else:
            raise ValueError(f"{path}: unexpected byte {b:#04x} at {i - 1}")
    if loops > 1:
        raise ValueError(f"{path}: {loops} loop markers")
    if i != len(data):
        raise ValueError(f"{path}: {len(data) - i} bytes after the end marker")
    return frames


def main():
    paths = sys.argv[1:]
    reference = play(paths[0])
    loud = sum(1 for f in reference if min(f[1]) < 15)
    print(f"{paths[0]}: {len(reference)} frames, {loud} with sound")
    if loud == 0:
        print("silent")
        return 1
    for path in paths[1:]:
        other = play(path)
        if len(other) != len(reference):
            print(f"{path}: {len(other)} frames, expected {len(reference)}")
            return 1
        for n, (a, b) in enumerate(zip(reference, other)):
            if a != b:
                print(f"{path}: frame {n} differs: {b} vs {a}")
                return 1
        print(f"{path}: same registers on every frame")
    return 0


if __name__ == "__main__":
    sys.exit(main())
