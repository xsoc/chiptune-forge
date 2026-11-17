#!/usr/bin/env python3
"""Runs our Z80 player (assets/msx/ay_player.asm) in a small Z80 emulator
and checks the AY-3-8910 registers it sets on every frame.

    ay_check.py msx|zx program.bin program.sym expected.bin [--60hz]
    ay_check.py msx|zx program.bin program.sym expected.bin --sfx sfx.bin

program.bin and program.sym come from Pasmo (pasmo main.asm program.bin
program.sym) building msx_main.asm or zx_main.asm from an example project
(tools/msx_examples.gd). expected.bin holds the registers the app's preview
sets on each frame, 11 bytes a frame. With --60hz the MSX reports a 60 Hz
machine, and the player must skip every sixth interrupt. With --sfx the
program plays a sound effect every 100 frames, and the check follows the
sound data the way the player's format describes.

The emulator covers the instructions our player and examples use.
"""
import sys

REGS = 11


class Z80:
    def __init__(self, machine):
        self.mem = bytearray(65536)
        self.a = self.f = self.b = self.c = self.d = self.e = self.h = self.l = 0
        self.ix = self.iy = 0
        self.sp = 0xF000
        self.pc = 0
        self.halted = False
        self.machine = machine
        self.latch = 0
        self.ay = [0] * 16
        self.ay_writes = 0

    # Registers by index (b c d e h l (hl) a).
    def get_r(self, i):
        if i == 0: return self.b
        if i == 1: return self.c
        if i == 2: return self.d
        if i == 3: return self.e
        if i == 4: return self.h
        if i == 5: return self.l
        if i == 6: return self.mem[self.hl]
        return self.a

    def set_r(self, i, v):
        v &= 0xFF
        if i == 0: self.b = v
        elif i == 1: self.c = v
        elif i == 2: self.d = v
        elif i == 3: self.e = v
        elif i == 4: self.h = v
        elif i == 5: self.l = v
        elif i == 6: self.wr(self.hl, v)
        else: self.a = v

    @property
    def hl(self): return (self.h << 8) | self.l
    @hl.setter
    def hl(self, v): self.h, self.l = (v >> 8) & 0xFF, v & 0xFF
    @property
    def de(self): return (self.d << 8) | self.e
    @de.setter
    def de(self, v): self.d, self.e = (v >> 8) & 0xFF, v & 0xFF
    @property
    def bc(self): return (self.b << 8) | self.c
    @bc.setter
    def bc(self, v): self.b, self.c = (v >> 8) & 0xFF, v & 0xFF

    def get_rr(self, i):
        return [self.bc, self.de, self.hl, self.sp][i]

    def set_rr(self, i, v):
        v &= 0xFFFF
        if i == 0: self.bc = v
        elif i == 1: self.de = v
        elif i == 2: self.hl = v
        else: self.sp = v

    def wr(self, addr, v):
        if addr < 0x4000 or (self.machine == "msx" and addr < 0xC000):
            raise RuntimeError("write to ROM at %04X (pc %04X)" % (addr, self.pc))
        self.mem[addr & 0xFFFF] = v & 0xFF

    def fetch(self):
        v = self.mem[self.pc]
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def fetch16(self):
        lo = self.fetch()
        return lo | (self.fetch() << 8)

    def push(self, v):
        self.sp = (self.sp - 2) & 0xFFFF
        self.wr(self.sp, v & 0xFF)
        self.wr(self.sp + 1, v >> 8)

    def pop(self):
        v = self.mem[self.sp] | (self.mem[self.sp + 1] << 8)
        self.sp = (self.sp + 2) & 0xFFFF
        return v

    # Flags: S 0x80, Z 0x40, H 0x10, P/V 0x04, N 0x02, C 0x01.
    def szp(self, v):
        f = v & 0x80
        if v == 0: f |= 0x40
        if bin(v).count("1") % 2 == 0: f |= 0x04
        return f

    def alu(self, op, v):
        a = self.a
        if op in (0, 1):  # add, adc
            carry = self.f & 1 if op == 1 else 0
            r = a + v + carry
            self.f = (r & 0x80) | (0x40 if r & 0xFF == 0 else 0) | (1 if r > 0xFF else 0) | ((a ^ v ^ r) & 0x10)
            if (~(a ^ v) & (a ^ r)) & 0x80: self.f |= 0x04
            self.a = r & 0xFF
        elif op in (2, 3, 7):  # sub, sbc, cp
            carry = self.f & 1 if op == 3 else 0
            r = a - v - carry
            f = (r & 0x80) | (0x40 if r & 0xFF == 0 else 0) | (1 if r < 0 else 0) | 0x02 | ((a ^ v ^ r) & 0x10)
            if ((a ^ v) & (a ^ r)) & 0x80: f |= 0x04
            self.f = f
            if op != 7:
                self.a = r & 0xFF
        elif op == 4:
            self.a = a & v
            self.f = self.szp(self.a) | 0x10
        elif op == 5:
            self.a = a ^ v
            self.f = self.szp(self.a)
        elif op == 6:
            self.a = a | v
            self.f = self.szp(self.a)

    def inc8(self, v):
        r = (v + 1) & 0xFF
        self.f = (self.f & 1) | (r & 0x80) | (0x40 if r == 0 else 0) | (0x10 if (v & 0x0F) == 0x0F else 0) | (0x04 if v == 0x7F else 0)
        return r

    def dec8(self, v):
        r = (v - 1) & 0xFF
        self.f = (self.f & 1) | 0x02 | (r & 0x80) | (0x40 if r == 0 else 0) | (0x10 if (v & 0x0F) == 0 else 0) | (0x04 if v == 0x80 else 0)
        return r

    def cond(self, cc):
        return [not self.f & 0x40, bool(self.f & 0x40), not self.f & 1, bool(self.f & 1),
                not self.f & 0x04, bool(self.f & 0x04), not self.f & 0x80, bool(self.f & 0x80)][cc]

    def out(self, port, v):
        if self.machine == "msx":
            port &= 0xFF
            if port == 0xA0:
                self.latch = v & 0x0F
            elif port == 0xA1:
                self.ay[self.latch] = v
                self.ay_writes += 1
        else:
            if port & 0xC002 == 0xC000:
                self.latch = v & 0x0F
            elif port & 0xC002 == 0x8000:
                self.ay[self.latch] = v
                self.ay_writes += 1

    def add16(self, a, b):
        r = a + b
        self.f = (self.f & 0xC4) | (1 if r > 0xFFFF else 0) | (((a ^ b ^ r) >> 8) & 0x10)
        return r & 0xFFFF

    def step(self):
        op = self.fetch()
        if op == 0x76:
            self.halted = True
            return
        if 0x40 <= op < 0x80:
            self.set_r((op >> 3) & 7, self.get_r(op & 7))
            return
        if 0x80 <= op < 0xC0:
            self.alu((op >> 3) & 7, self.get_r(op & 7))
            return
        if op & 0xC7 == 0x06:
            self.set_r((op >> 3) & 7, self.fetch())
            return
        if op & 0xC7 == 0x04:
            i = (op >> 3) & 7
            self.set_r(i, self.inc8(self.get_r(i)))
            return
        if op & 0xC7 == 0x05:
            i = (op >> 3) & 7
            self.set_r(i, self.dec8(self.get_r(i)))
            return
        if op & 0xCF == 0x01:
            self.set_rr(op >> 4, self.fetch16())
            return
        if op & 0xCF == 0x03:
            self.set_rr(op >> 4, self.get_rr(op >> 4) + 1)
            return
        if op & 0xCF == 0x0B:
            self.set_rr(op >> 4, self.get_rr(op >> 4) - 1)
            return
        if op & 0xCF == 0x09:
            self.hl = self.add16(self.hl, self.get_rr(op >> 4))
            return
        if op & 0xC7 == 0xC6:
            self.alu((op >> 3) & 7, self.fetch())
            return
        if op & 0xC7 == 0xC0:
            if self.cond((op >> 3) & 7):
                self.pc = self.pop()
            return
        if op & 0xC7 == 0xC2:
            nn = self.fetch16()
            if self.cond((op >> 3) & 7):
                self.pc = nn
            return
        if op & 0xC7 == 0xC4:
            nn = self.fetch16()
            if self.cond((op >> 3) & 7):
                self.push(self.pc)
                self.pc = nn
            return
        if op & 0xCF == 0xC5:
            i = (op >> 4) & 3
            self.push((self.a << 8) | self.f if i == 3 else self.get_rr(i))
            return
        if op & 0xCF == 0xC1:
            i = (op >> 4) & 3
            v = self.pop()
            if i == 3:
                self.a, self.f = v >> 8, v & 0xFF
            else:
                self.set_rr(i, v)
            return
        if op in (0x18, 0x20, 0x28, 0x30, 0x38, 0x10):
            d = self.fetch()
            d = d - 256 if d >= 128 else d
            if op == 0x10:
                self.b = (self.b - 1) & 0xFF
                take = self.b != 0
            elif op == 0x18:
                take = True
            else:
                take = self.cond((op - 0x20) >> 3)
            if take:
                self.pc = (self.pc + d) & 0xFFFF
            return
        if op == 0x00 or op in (0xF3, 0xFB):
            return
        if op == 0x02: self.wr(self.bc, self.a); return
        if op == 0x12: self.wr(self.de, self.a); return
        if op == 0x0A: self.a = self.mem[self.bc]; return
        if op == 0x1A: self.a = self.mem[self.de]; return
        if op == 0x22:
            nn = self.fetch16(); self.wr(nn, self.l); self.wr(nn + 1, self.h); return
        if op == 0x2A:
            nn = self.fetch16(); self.l = self.mem[nn]; self.h = self.mem[nn + 1]; return
        if op == 0x32: self.wr(self.fetch16(), self.a); return
        if op == 0x3A: self.a = self.mem[self.fetch16()]; return
        if op == 0x2F:
            self.a ^= 0xFF; self.f |= 0x12; return
        if op == 0x0F:
            c = self.a & 1
            self.a = (self.a >> 1) | (c << 7)
            self.f = (self.f & 0xC4) | c
            return
        if op == 0x07:
            c = self.a >> 7
            self.a = ((self.a << 1) | c) & 0xFF
            self.f = (self.f & 0xC4) | c
            return
        if op == 0x37: self.f = (self.f & 0xC4) | 1; return
        if op == 0x3F: self.f = (self.f & 0xC4) | ((self.f & 1) ^ 1); return
        if op == 0xC3: self.pc = self.fetch16(); return
        if op == 0xCD:
            nn = self.fetch16(); self.push(self.pc); self.pc = nn; return
        if op == 0xC9: self.pc = self.pop(); return
        if op == 0xE9: self.pc = self.hl; return
        if op == 0xEB:
            self.d, self.e, self.h, self.l = self.h, self.l, self.d, self.e; return
        if op == 0xD3: self.out((self.a << 8) | self.fetch(), self.a); return
        if op == 0xDB: self.fetch(); self.a = 0xFF; return
        if op == 0xCB: return self.cb(None)
        if op == 0xED: return self.ed()
        if op == 0xDD: return self.dd()
        raise RuntimeError("opcode %02X not emulated at %04X" % (op, (self.pc - 1) & 0xFFFF))

    def cb(self, addr):
        op = self.fetch() if addr is None else self.fetch()
        i = op & 7
        v = self.mem[addr] if addr is not None else self.get_r(i)
        kind = op >> 6
        bit = (op >> 3) & 7
        if kind == 1:
            self.f = (self.f & 1) | 0x10 | (0x44 if not v & (1 << bit) else 0) | (v & 0x80 if bit == 7 else 0)
            return
        if kind == 2:
            v &= ~(1 << bit)
        elif kind == 3:
            v |= 1 << bit
        else:
            c = self.f & 1
            if bit == 0: c, v = v >> 7, (v << 1) | (v >> 7)
            elif bit == 1: c, v = v & 1, (v >> 1) | ((v & 1) << 7)
            elif bit == 2: c, v = v >> 7, (v << 1) | c
            elif bit == 3: c, v = v & 1, (v >> 1) | (c << 7)
            elif bit == 4: c, v = v >> 7, v << 1
            elif bit == 5: c, v = v & 1, (v >> 1) | (v & 0x80)
            elif bit == 7: c, v = v & 1, v >> 1
            else: raise RuntimeError("CB %02X not emulated" % op)
            v &= 0xFF
            self.f = self.szp(v) | c
        if addr is not None:
            self.wr(addr, v)
        else:
            self.set_r(i, v)

    def ed(self):
        op = self.fetch()
        if op == 0xB0:
            while True:
                self.wr(self.de, self.mem[self.hl])
                self.hl = self.hl + 1
                self.de = self.de + 1
                self.bc = self.bc - 1
                if self.bc == 0:
                    break
            self.f &= 0xC1
            return
        if op & 0xC7 == 0x41:
            self.out(self.bc, self.get_r((op >> 3) & 7) if (op >> 3) & 7 != 6 else 0)
            return
        if op in (0x46, 0x56, 0x5E): return
        if op & 0xCF == 0x42 or op & 0xCF == 0x4A:
            v = self.get_rr((op >> 4) & 3)
            carry = self.f & 1
            r = self.hl - v - carry if op & 0x08 == 0 else self.hl + v + carry
            self.f = ((r >> 8) & 0x80) | (0x40 if r & 0xFFFF == 0 else 0) | (1 if r < 0 or r > 0xFFFF else 0) | (0x02 if op & 0x08 == 0 else 0)
            self.hl = r & 0xFFFF
            return
        if op & 0xCF == 0x43:
            nn = self.fetch16(); v = self.get_rr((op >> 4) & 3)
            self.wr(nn, v & 0xFF); self.wr(nn + 1, v >> 8); return
        if op & 0xCF == 0x4B:
            nn = self.fetch16(); self.set_rr((op >> 4) & 3, self.mem[nn] | (self.mem[nn + 1] << 8)); return
        raise RuntimeError("ED %02X not emulated at %04X" % (op, self.pc))

    def dd(self):
        op = self.fetch()

        def disp():
            d = self.fetch()
            return (self.ix + (d - 256 if d >= 128 else d)) & 0xFFFF

        if op == 0x21: self.ix = self.fetch16(); return
        if op == 0xE5: self.push(self.ix); return
        if op == 0xE1: self.ix = self.pop(); return
        if op == 0x2A:
            nn = self.fetch16(); self.ix = self.mem[nn] | (self.mem[nn + 1] << 8); return
        if op == 0x22:
            nn = self.fetch16(); self.wr(nn, self.ix & 0xFF); self.wr(nn + 1, self.ix >> 8); return
        if op & 0xCF == 0x09:
            i = op >> 4
            v = self.ix if i == 2 else self.get_rr(i)
            self.ix = self.add16(self.ix, v)
            return
        if op == 0x23: self.ix = (self.ix + 1) & 0xFFFF; return
        if op == 0x36:
            a = disp(); self.wr(a, self.fetch()); return
        if op == 0x34:
            a = disp(); self.wr(a, self.inc8(self.mem[a])); return
        if op == 0x35:
            a = disp(); self.wr(a, self.dec8(self.mem[a])); return
        if op & 0xC7 == 0x46 and op != 0x76:
            a = disp(); self.set_r((op >> 3) & 7, self.mem[a]); return
        if op & 0xF8 == 0x70 and op != 0x76:
            a = disp(); self.wr(a, self.get_r(op & 7)); return
        if op & 0xC7 == 0x86:
            a = disp(); self.alu((op >> 3) & 7, self.mem[a]); return
        if op == 0xCB:
            a = disp(); return self.cb(a)
        raise RuntimeError("DD %02X not emulated at %04X" % (op, self.pc))

    def run_to_halt(self, limit=2000000):
        self.halted = False
        for _ in range(limit):
            self.step()
            if self.halted:
                return
        raise RuntimeError("no halt after %d instructions (pc %04X)" % (limit, self.pc))


class Stream:
    """A stream as the player's format describes it."""

    def __init__(self, data, start, loop, count=REGS, initial=None):
        self.data, self.pos, self.loop = data, start, loop
        self.wait, self.ret, self.end, self.on = 0, -1, 0, True
        self.regs = [0] * count
        for r, v in ({7: 0x3F} if initial is None else initial).items():
            self.regs[r] = v

    def step(self):
        if not self.on:
            return
        if self.wait:
            self.wait -= 1
            return
        d = self.data
        while True:
            if self.ret >= 0 and self.pos == self.end:
                self.pos, self.ret = self.ret, -1
            b = d[self.pos]
            self.pos += 1
            if b < 0x80:
                self.regs[b] = d[self.pos]
                self.pos += 1
            elif b < 0xC0:
                self.wait = b & 0x3F
                return
            elif b == 0xC0:
                at = d[self.pos] | (d[self.pos + 1] << 8)
                length = d[self.pos + 2] | (d[self.pos + 3] << 8)
                self.ret = self.pos + 4
                self.pos, self.end = at, at + length
            elif b == 0xFE:
                self.pos = self.loop
            else:
                self.on = False
                return


def main():
    args = sys.argv[1:]
    machine, program, symfile, expected_path = args[:4]
    hz60 = "--60hz" in args
    sfx = open(args[args.index("--sfx") + 1], "rb").read() if "--sfx" in args else None
    syms = {}
    for line in open(symfile):
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "EQU":
            syms[parts[0].lower()] = int(parts[2].rstrip("Hh"), 16)
    code = open(program, "rb").read()
    expected = open(expected_path, "rb").read()
    frames = [list(expected[i:i + REGS]) for i in range(0, len(expected), REGS)]
    cpu = Z80(machine)
    if machine == "msx":
        cpu.mem[0x4000:0x4000 + len(code)] = code
        cpu.mem[0x0024] = 0xC9  # ENASLT
        cpu.mem[0x0138] = 0xAF  # RSLREG: xor a
        cpu.mem[0x0139] = 0xC9
        cpu.mem[0x002B] = 0x00 if hz60 else 0x80
        cpu.sp = 0xF380
    else:
        cpu.mem[0x8000:0x8000 + len(code)] = code
        cpu.sp = 0x7FF0
    cpu.pc = syms["start"]
    sounds = None
    if sfx is not None:
        sounds = [sfx[5 + i * 2] | (sfx[6 + i * 2] << 8) for i in range(sfx[4])]
    playing = None
    calls = 0
    checked = 0
    for call in range(len(frames) * 6 // 5 if hz60 else len(frames)):
        cpu.run_to_halt()
        # Frames played so far: the first in ay_init, then one per call
        # less the ones a 60 Hz MSX skips.
        f = call - call // 6 if hz60 else call
        if f >= len(frames):
            break
        want = list(frames[f])
        if sounds is not None and call > 0:
            if playing is not None:
                playing.step()
                if playing.on:
                    s = playing.regs
                    want[2], want[3], want[9] = s[2], s[3], s[9]
                    want[7] = (want[7] & 0xED) | (s[7] & 0x12)
                    if not s[7] & 0x10:
                        want[6] = s[6]
            if call % 100 == 0:
                n = (call // 100 - 1) % len(sounds)
                playing = Stream(sfx, sounds[n], 0)
        got = cpu.ay[:REGS]
        for r in range(REGS):
            mask = 0x3F if r == 7 else 0xFF
            if got[r] & mask != want[r] & mask:
                print("Frame %d (interrupt %d), register %d: the player set %d, expected %d" % (f, call, r, got[r], want[r]))
                print("  player:  ", got)
                print("  expected:", want)
                sys.exit(1)
        if machine == "msx" and got[7] & 0xC0 != 0x80:
            print("Frame %d: the mixer must keep the MSX's I/O port A an input and B an output (%02X)" % (f, got[7]))
            sys.exit(1)
        checked += 1
    print("%s: the Z80 player set the expected registers on all %d frames (%d register writes)%s" % (
        machine, checked, cpu.ay_writes, " at 60 Hz" if hz60 else ""))


if __name__ == "__main__":
    main()
