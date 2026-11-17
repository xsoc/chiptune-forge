#!/usr/bin/env python3
"""Checks smconv's soundbank against the BRR the app expects.

    python3 tools/snes_check.py soundbank.bnk sample_*.brr

smconv (PVSnesLib) converts our Impulse Tracker modules into a soundbank,
encoding every sample as BRR on the way. The app previews songs with its own
port of that encoder, so every source in the bank must be one of the BRR
files the app wrote, byte for byte (files for samples this bank's module
does not use are listed and skipped). The bank is LoROM: a table of 128 module pointers and one
source pointer per sample (16-bit address from $8000 and an 8-bit bank of
32 KB), then the modules, then each source as length, loop offset and data.
Exits 1 if a bank source matches none of the files.
"""
import struct
import sys


def sources(path):
    data = open(path, "rb").read()
    count, modules = struct.unpack_from("<HH", data, 0)
    out = []
    table = 4 + 3 * 128
    for i in range(count):
        addr, bank = struct.unpack_from("<HB", data, table + i * 3)
        offset = bank * 0x8000 + (addr - 0x8000)
        length, loop = struct.unpack_from("<HH", data, offset)
        out.append((data[offset + 4:offset + 4 + length], loop))
    return modules, out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    modules, bank = sources(sys.argv[1])
    print(f"{sys.argv[1]}: {modules} module(s), {len(bank)} BRR sources")
    blobs = [b for b, _ in bank]
    mine = {path: open(path, "rb").read() for path in sys.argv[2:]}
    for path, data in mine.items():
        if data in blobs:
            print(f"  {path}: {len(data)} bytes, identical in the bank")
        else:
            print(f"  {path}: not in this bank")
    failed = 0
    for i, blob in enumerate(blobs):
        if blob in mine.values():
            continue
        failed += 1
        same_size = [(p, d) for p, d in mine.items() if len(d) == len(blob)]
        if same_size:
            diffs = ", ".join(f"{p} in {sum(1 for a, b in zip(d, blob) if a != b)} bytes" for p, d in same_size)
            print(f"  source {i} ({len(blob)} bytes) matches no file; same size: {diffs}")
        else:
            print(f"  source {i} ({len(blob)} bytes) matches no file")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
