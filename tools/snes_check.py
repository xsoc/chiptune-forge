#!/usr/bin/env python3
"""Checks smconv's soundbank against the BRR the app expects.

    python3 tools/snes_check.py soundbank.bnk sample_*.brr

smconv (PVSnesLib) converts our Impulse Tracker modules into a soundbank,
encoding every sample as BRR on the way. The app previews songs with its own
port of that encoder, so each BRR file the app wrote must appear in the bank
byte for byte. The bank is LoROM: a table of 128 module pointers and one
source pointer per sample (16-bit address from $8000 and an 8-bit bank of
32 KB), then the modules, then each source as length, loop offset and data.
Exits 1 if a sample is missing or differs.
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
    failed = 0
    for path in sys.argv[2:]:
        mine = open(path, "rb").read()
        if mine in blobs:
            print(f"  {path}: {len(mine)} bytes, identical in the bank")
            continue
        failed += 1
        same_size = [b for b in blobs if len(b) == len(mine)]
        if same_size:
            diff = sum(1 for a, b in zip(mine, same_size[0]) if a != b)
            print(f"  {path}: differs from the bank's {len(mine)}-byte source in {diff} bytes")
        else:
            print(f"  {path}: no source of {len(mine)} bytes in the bank")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
