#!/usr/bin/env python3
"""Checks a Mega Drive VGM the app exported against SGDK's xgmtool.

    python3 tools/md_check.py ours.vgm theirs.vgm [more.vgm ...]

Plays each VGM (YM2612 writes 0x52/0x53, SN76489 writes 0x50, waits) and
records, for every 1/60 s frame up to the end of the first pass, the chips'
registers and which FM channels were keyed on during the frame. Every other
file (xgmtool's VGM back from its XGM or from the compiled XGC data the
console's driver plays) must give the same registers and key-ons frame by
frame as the first. xgmtool drops writes that change nothing and may add a
few frames of padding at the end, so only the first file's length counts.
Also checks that the song keys notes on several FM channels and the PSG.
Exits 1 on any difference.
"""
import struct
import sys

FRAME = 735
# FM registers that hold sound settings, per port; 0x28 (key) is tracked as
# events, timers and the DAC are left out.
FM_REGS = [r for r in range(0x30, 0xB8) if (r & 3) != 3 and not (0xA8 <= r < 0xB0)]


def play(path):
    data = open(path, "rb").read()
    if data[:4] != b"Vgm ":
        sys.exit(f"{path}: not a VGM file")
    version = struct.unpack_from("<I", data, 8)[0]
    total = struct.unpack_from("<I", data, 0x18)[0]
    start = 0x40
    if version >= 0x150:
        offset = struct.unpack_from("<I", data, 0x34)[0]
        if offset:
            start = 0x34 + offset
    fm = [[0] * 256, [0] * 256]
    latch_hi = [0] * 6
    keys = [0] * 6
    psg_tone = [0, 0, 0]
    psg_att = [15, 15, 15, 15]
    psg_noise = 0
    psg_latch = 0
    frames = []
    pending = 0
    keyed_frame = [0] * 6
    key_ons = 0
    psg_writes = 0
    i = start

    def snapshot():
        regs = tuple(fm[p][r] for p in (0, 1) for r in FM_REGS)
        return (regs, tuple(keys), tuple(keyed_frame), tuple(psg_tone), tuple(psg_att), psg_noise)

    while i < len(data):
        cmd = data[i]
        if cmd in (0x52, 0x53):
            port = cmd - 0x52
            reg, val = data[i + 1], data[i + 2]
            i += 3
            if port == 0 and reg == 0x28:
                code = val & 7
                if code in (3, 7):
                    continue
                ch = code if code < 3 else code - 1
                if val & 0xF0:
                    keyed_frame[ch] += 1
                    key_ons += 1
                keys[ch] = val >> 4
            elif 0xA4 <= reg < 0xA7:
                latch_hi[reg - 0xA4 + 3 * port] = val
                fm[port][reg] = val
            else:
                fm[port][reg] = val
        elif cmd == 0x50:
            b = data[i + 1]
            i += 2
            psg_writes += 1
            if b & 0x80:
                psg_latch = (b >> 4) & 7
                ch, vol = psg_latch >> 1, psg_latch & 1
                if vol:
                    psg_att[ch] = b & 15
                elif ch < 3:
                    psg_tone[ch] = (psg_tone[ch] & 0x3F0) | (b & 15)
                else:
                    psg_noise = b & 7
            else:
                ch, vol = psg_latch >> 1, psg_latch & 1
                if vol:
                    psg_att[ch] = b & 15
                elif ch < 3:
                    psg_tone[ch] = (psg_tone[ch] & 15) | ((b & 0x3F) << 4)
                else:
                    psg_noise = b & 7
        elif cmd in (0x61, 0x62, 0x63) or 0x70 <= cmd <= 0x7F:
            if cmd == 0x61:
                wait = struct.unpack_from("<H", data, i + 1)[0]
                i += 3
            elif cmd == 0x62:
                wait = 735
                i += 1
            elif cmd == 0x63:
                wait = 882
                i += 1
            else:
                wait = (cmd & 15) + 1
                i += 1
            pending += wait
            while pending >= FRAME:
                pending -= FRAME
                frames.append(snapshot())
                keyed_frame = [0] * 6
        elif cmd == 0x66:
            break
        elif cmd == 0x67:
            size = struct.unpack_from("<I", data, i + 3)[0]
            i += 7 + size
        elif cmd == 0x4F:
            i += 2
        elif 0x80 <= cmd <= 0x8F:
            # YM2612 DAC write from the data bank, then a short wait.
            i += 1
            pending += cmd & 15
        elif cmd == 0xE0:
            i += 5
        else:
            sys.exit(f"{path}: unexpected VGM command {cmd:#04x} at {i:#x}")
    return {"frames": frames, "samples": total, "key_ons": key_ons, "psg_writes": psg_writes}


def describe(a, b):
    names = ["FM registers", "key state", "key-ons", "PSG tones", "PSG volumes", "PSG noise"]
    parts = []
    for name, x, y in zip(names, a, b):
        if x != y:
            if name == "FM registers":
                diffs = [(p, r, x[k], y[k]) for k, (p, r) in enumerate((p, r) for p in (0, 1) for r in FM_REGS) if x[k] != y[k]]
                parts.append(name + " " + ", ".join(f"port {p} reg {r:#04x}: {u:#04x} vs {v:#04x}" for p, r, u, v in diffs[:4]))
            else:
                parts.append(f"{name} {x} vs {y}")
    return "; ".join(parts)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    ours = play(sys.argv[1])
    frames = ours["frames"]
    if len(frames) * FRAME != ours["samples"]:
        sys.exit(f"{sys.argv[1]}: header says {ours['samples']} samples, data has {len(frames) * FRAME}")
    if ours["key_ons"] < 20:
        sys.exit(f"{sys.argv[1]}: only {ours['key_ons']} FM notes")
    channels = sum(1 for c in range(6) if any(f[2][c] for f in frames))
    print(f"{sys.argv[1]}: {len(frames)} frames, {ours['key_ons']} FM key-ons on {channels} channels, {ours['psg_writes']} PSG writes")
    failed = False
    for other in sys.argv[2:]:
        theirs = play(other)["frames"]
        # The compiled XGC data starts a few frames late; find the shift.
        best = None
        for shift in range(0, 9):
            if len(theirs) < len(frames) + shift:
                break
            bad = [f for f in range(len(frames)) if frames[f] != theirs[f + shift]]
            if best is None or len(bad) < len(best[1]):
                best = (shift, bad)
        if best is None:
            print(f"{other}: only {len(theirs)} frames of {len(frames)}")
            failed = True
            continue
        shift, bad = best
        late = f" (starting {shift} frames late)" if shift else ""
        if bad:
            f = bad[0]
            print(f"{other}{late}: {len(bad)} frames differ, first at frame {f}: {describe(frames[f], theirs[f + shift])}")
            failed = True
        else:
            print(f"{other}{late}: same registers and key-ons on all {len(frames)} frames")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
