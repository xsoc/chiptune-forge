#!/usr/bin/env python3
"""Runs our 6502 player (assets/c64/sid_player.s) in a small 6502 emulator
and checks the SID registers it sets on every frame.

    sid_check.py song.sid expected.bin [--sfx sfx.bin]

song.sid is a PSID file the app exported: our player at $1000 with the
song after it. expected.bin holds the registers the app's preview sets on
each frame, 25 bytes a frame (tools/c64_examples.gd writes it). The check
calls init ($1000) once and play ($1003) once per frame, and compares the
registers written to $D400-$D418. With --sfx it also loads the sound data
at $C000, calls $1006 to use it, and $1009 to play the next sound every 100
frames, and follows the sound data the way the player's format describes.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ay_check import Stream  # noqa: E402

REGS = 25
SFX_AT = 0xC000


class CPU:
    def __init__(self):
        self.mem = bytearray(65536)
        self.a = self.x = self.y = 0
        self.sp = 0xFF
        self.pc = 0
        self.c = self.z = self.n = self.v = 0
        self.d = self.i = 0
        self.sid = [0] * REGS

    def rd(self, addr):
        return self.mem[addr & 0xFFFF]

    def wr(self, addr, v):
        addr &= 0xFFFF
        v &= 0xFF
        if 0xD400 <= addr < 0xD400 + REGS:
            self.sid[addr - 0xD400] = v
        elif 0xA000 <= addr < 0xC000 or addr >= 0xD000:
            raise RuntimeError("write to %04X (pc %04X)" % (addr, self.pc))
        self.mem[addr] = v

    def fetch(self):
        v = self.mem[self.pc]
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def fetch16(self):
        lo = self.fetch()
        return lo | (self.fetch() << 8)

    def push(self, v):
        self.mem[0x100 + self.sp] = v & 0xFF
        self.sp = (self.sp - 1) & 0xFF

    def pull(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.mem[0x100 + self.sp]

    def nz(self, v):
        v &= 0xFF
        self.z = int(v == 0)
        self.n = v >> 7
        return v

    def status(self):
        return (self.n << 7) | (self.v << 6) | 0x30 | (self.d << 3) | (self.i << 2) | (self.z << 1) | self.c

    def set_status(self, p):
        self.n, self.v, self.d, self.i, self.z, self.c = p >> 7 & 1, p >> 6 & 1, p >> 3 & 1, p >> 2 & 1, p >> 1 & 1, p & 1

    # Addressing modes: return an address (or None for the accumulator).
    def addr(self, mode):
        if mode == "imm":
            a = self.pc
            self.pc = (self.pc + 1) & 0xFFFF
            return a
        if mode == "zp":
            return self.fetch()
        if mode == "zpx":
            return (self.fetch() + self.x) & 0xFF
        if mode == "zpy":
            return (self.fetch() + self.y) & 0xFF
        if mode == "abs":
            return self.fetch16()
        if mode == "abx":
            return (self.fetch16() + self.x) & 0xFFFF
        if mode == "aby":
            return (self.fetch16() + self.y) & 0xFFFF
        if mode == "izx":
            z = (self.fetch() + self.x) & 0xFF
            return self.mem[z] | (self.mem[(z + 1) & 0xFF] << 8)
        if mode == "izy":
            z = self.fetch()
            return ((self.mem[z] | (self.mem[(z + 1) & 0xFF] << 8)) + self.y) & 0xFFFF
        raise RuntimeError(mode)

    def adc(self, m):
        r = self.a + m + self.c
        self.v = int(((self.a ^ r) & (m ^ r) & 0x80) != 0)
        self.c = int(r > 0xFF)
        self.a = self.nz(r)

    def sbc(self, m):
        self.adc(m ^ 0xFF)

    def compare(self, reg, m):
        r = reg - m
        self.c = int(r >= 0)
        self.nz(r)

    def step(self):
        op = self.fetch()
        ins, mode = OPS.get(op, (None, None))
        if ins is None:
            raise RuntimeError("opcode %02X not emulated at %04X" % (op, (self.pc - 1) & 0xFFFF))
        if ins in ("BPL", "BMI", "BVC", "BVS", "BCC", "BCS", "BNE", "BEQ"):
            d = self.fetch()
            d = d - 256 if d >= 128 else d
            flag = {"BPL": not self.n, "BMI": self.n, "BVC": not self.v, "BVS": self.v,
                    "BCC": not self.c, "BCS": self.c, "BNE": not self.z, "BEQ": self.z}[ins]
            if flag:
                self.pc = (self.pc + d) & 0xFFFF
            return
        if ins == "JMP":
            if mode == "abs":
                self.pc = self.fetch16()
            else:
                p = self.fetch16()
                self.pc = self.mem[p] | (self.mem[(p & 0xFF00) | ((p + 1) & 0xFF)] << 8)
            return
        if ins == "JSR":
            t = self.fetch16()
            r = (self.pc - 1) & 0xFFFF
            self.push(r >> 8)
            self.push(r & 0xFF)
            self.pc = t
            return
        if ins == "RTS":
            lo = self.pull()
            self.pc = ((self.pull() << 8) | lo) + 1 & 0xFFFF
            return
        if mode == "imp":
            if ins == "CLC": self.c = 0
            elif ins == "SEC": self.c = 1
            elif ins == "CLI": self.i = 0
            elif ins == "SEI": self.i = 1
            elif ins == "CLD": self.d = 0
            elif ins == "CLV": self.v = 0
            elif ins == "TAX": self.x = self.nz(self.a)
            elif ins == "TAY": self.y = self.nz(self.a)
            elif ins == "TXA": self.a = self.nz(self.x)
            elif ins == "TYA": self.a = self.nz(self.y)
            elif ins == "TSX": self.x = self.nz(self.sp)
            elif ins == "TXS": self.sp = self.x
            elif ins == "INX": self.x = self.nz(self.x + 1)
            elif ins == "INY": self.y = self.nz(self.y + 1)
            elif ins == "DEX": self.x = self.nz(self.x - 1)
            elif ins == "DEY": self.y = self.nz(self.y - 1)
            elif ins == "PHA": self.push(self.a)
            elif ins == "PLA": self.a = self.nz(self.pull())
            elif ins == "PHP": self.push(self.status())
            elif ins == "PLP": self.set_status(self.pull())
            elif ins == "NOP": pass
            else: raise RuntimeError(ins)
            return
        if mode == "acc":
            self.a = self.shift(ins, self.a)
            return
        a = self.addr(mode)
        if ins == "LDA": self.a = self.nz(self.rd(a))
        elif ins == "LDX": self.x = self.nz(self.rd(a))
        elif ins == "LDY": self.y = self.nz(self.rd(a))
        elif ins == "STA": self.wr(a, self.a)
        elif ins == "STX": self.wr(a, self.x)
        elif ins == "STY": self.wr(a, self.y)
        elif ins == "ADC": self.adc(self.rd(a))
        elif ins == "SBC": self.sbc(self.rd(a))
        elif ins == "AND": self.a = self.nz(self.a & self.rd(a))
        elif ins == "ORA": self.a = self.nz(self.a | self.rd(a))
        elif ins == "EOR": self.a = self.nz(self.a ^ self.rd(a))
        elif ins == "CMP": self.compare(self.a, self.rd(a))
        elif ins == "CPX": self.compare(self.x, self.rd(a))
        elif ins == "CPY": self.compare(self.y, self.rd(a))
        elif ins == "BIT":
            m = self.rd(a)
            self.z = int((self.a & m) == 0)
            self.n, self.v = m >> 7, (m >> 6) & 1
        elif ins == "INC": self.wr(a, self.nz(self.rd(a) + 1))
        elif ins == "DEC": self.wr(a, self.nz(self.rd(a) - 1))
        else:
            self.wr(a, self.shift(ins, self.rd(a)))

    def shift(self, ins, v):
        if ins == "ASL":
            self.c = v >> 7
            return self.nz(v << 1)
        if ins == "LSR":
            self.c = v & 1
            return self.nz(v >> 1)
        if ins == "ROL":
            c = self.c
            self.c = v >> 7
            return self.nz((v << 1) | c)
        if ins == "ROR":
            c = self.c
            self.c = v & 1
            return self.nz((v >> 1) | (c << 7))
        raise RuntimeError(ins)

    def call(self, addr, a=0, x=0, limit=200000):
        """Runs a subroutine until it returns."""
        self.a, self.x = a, x
        self.sp = 0xFD
        self.push(0xFF)
        self.push(0xFE)  # returns to $FFFF
        self.pc = addr
        for _ in range(limit):
            if self.pc == 0xFFFF:
                return
            self.step()
        raise RuntimeError("no return after %d instructions (pc %04X)" % (limit, self.pc))


def _ops():
    table = {}
    groups = {
        "LDA": {"imm": 0xA9, "zp": 0xA5, "zpx": 0xB5, "abs": 0xAD, "abx": 0xBD, "aby": 0xB9, "izx": 0xA1, "izy": 0xB1},
        "LDX": {"imm": 0xA2, "zp": 0xA6, "zpy": 0xB6, "abs": 0xAE, "aby": 0xBE},
        "LDY": {"imm": 0xA0, "zp": 0xA4, "zpx": 0xB4, "abs": 0xAC, "abx": 0xBC},
        "STA": {"zp": 0x85, "zpx": 0x95, "abs": 0x8D, "abx": 0x9D, "aby": 0x99, "izx": 0x81, "izy": 0x91},
        "STX": {"zp": 0x86, "zpy": 0x96, "abs": 0x8E},
        "STY": {"zp": 0x84, "zpx": 0x94, "abs": 0x8C},
        "ADC": {"imm": 0x69, "zp": 0x65, "zpx": 0x75, "abs": 0x6D, "abx": 0x7D, "aby": 0x79, "izx": 0x61, "izy": 0x71},
        "SBC": {"imm": 0xE9, "zp": 0xE5, "zpx": 0xF5, "abs": 0xED, "abx": 0xFD, "aby": 0xF9, "izx": 0xE1, "izy": 0xF1},
        "AND": {"imm": 0x29, "zp": 0x25, "zpx": 0x35, "abs": 0x2D, "abx": 0x3D, "aby": 0x39, "izx": 0x21, "izy": 0x31},
        "ORA": {"imm": 0x09, "zp": 0x05, "zpx": 0x15, "abs": 0x0D, "abx": 0x1D, "aby": 0x19, "izx": 0x01, "izy": 0x11},
        "EOR": {"imm": 0x49, "zp": 0x45, "zpx": 0x55, "abs": 0x4D, "abx": 0x5D, "aby": 0x59, "izx": 0x41, "izy": 0x51},
        "CMP": {"imm": 0xC9, "zp": 0xC5, "zpx": 0xD5, "abs": 0xCD, "abx": 0xDD, "aby": 0xD9, "izx": 0xC1, "izy": 0xD1},
        "CPX": {"imm": 0xE0, "zp": 0xE4, "abs": 0xEC},
        "CPY": {"imm": 0xC0, "zp": 0xC4, "abs": 0xCC},
        "BIT": {"zp": 0x24, "abs": 0x2C},
        "INC": {"zp": 0xE6, "zpx": 0xF6, "abs": 0xEE, "abx": 0xFE},
        "DEC": {"zp": 0xC6, "zpx": 0xD6, "abs": 0xCE, "abx": 0xDE},
        "ASL": {"acc": 0x0A, "zp": 0x06, "zpx": 0x16, "abs": 0x0E, "abx": 0x1E},
        "LSR": {"acc": 0x4A, "zp": 0x46, "zpx": 0x56, "abs": 0x4E, "abx": 0x5E},
        "ROL": {"acc": 0x2A, "zp": 0x26, "zpx": 0x36, "abs": 0x2E, "abx": 0x3E},
        "ROR": {"acc": 0x6A, "zp": 0x66, "zpx": 0x76, "abs": 0x6E, "abx": 0x7E},
        "JMP": {"abs": 0x4C, "ind": 0x6C},
        "JSR": {"abs": 0x20},
    }
    for ins, modes in groups.items():
        for mode, op in modes.items():
            table[op] = (ins, mode)
    implied = {"CLC": 0x18, "SEC": 0x38, "CLI": 0x58, "SEI": 0x78, "CLD": 0xD8, "CLV": 0xB8, "TAX": 0xAA, "TAY": 0xA8,
               "TXA": 0x8A, "TYA": 0x98, "TSX": 0xBA, "TXS": 0x9A, "INX": 0xE8, "INY": 0xC8, "DEX": 0xCA, "DEY": 0x88,
               "PHA": 0x48, "PLA": 0x68, "PHP": 0x08, "PLP": 0x28, "NOP": 0xEA}
    for ins, op in implied.items():
        table[op] = (ins, "imp")
    table[0x60] = ("RTS", "imp")
    for ins, op in {"BPL": 0x10, "BMI": 0x30, "BVC": 0x50, "BVS": 0x70, "BCC": 0x90, "BCS": 0xB0, "BNE": 0xD0, "BEQ": 0xF0}.items():
        table[op] = (ins, "rel")
    return table


OPS = _ops()


def main():
    args = sys.argv[1:]
    psid = open(args[0], "rb").read()
    expected = open(args[1], "rb").read()
    sfx = open(args[args.index("--sfx") + 1], "rb").read() if "--sfx" in args else None
    if psid[:4] != b"PSID":
        sys.exit("not a PSID file")
    offset = (psid[6] << 8) | psid[7]
    init = (psid[0x0A] << 8) | psid[0x0B]
    play = (psid[0x0C] << 8) | psid[0x0D]
    load = psid[offset] | (psid[offset + 1] << 8)
    body = psid[offset + 2:]
    cpu = CPU()
    cpu.mem[load:load + len(body)] = body
    frames = [list(expected[i:i + REGS]) for i in range(0, len(expected), REGS)]
    sounds = None
    if sfx is not None:
        cpu.mem[SFX_AT:SFX_AT + len(sfx)] = sfx
        sounds = [sfx[5 + i * 2] | (sfx[6 + i * 2] << 8) for i in range(sfx[4])]
    cpu.call(init)
    if sfx is not None:
        cpu.call(load + 6, SFX_AT & 0xFF, SFX_AT >> 8)
    playing = None
    for f in range(len(frames)):
        if f > 0:
            cpu.call(play)
        want = list(frames[f])
        if sounds is not None and f > 0:
            if playing is not None:
                playing.step()
                if playing.on:
                    for r in range(7, 14):
                        want[r] = playing.regs[r]
            if f % 100 == 0:
                n = (f // 100 - 1) % len(sounds)
                cpu.call(load + 9, n)
                playing = Stream(sfx, sounds[n], 0, REGS, {})
        if cpu.sid != want:
            r = next(i for i in range(REGS) if cpu.sid[i] != want[i])
            print("Frame %d, register %d: the player set %d, expected %d" % (f, r, cpu.sid[r], want[r]))
            print("  player:  ", cpu.sid)
            print("  expected:", want)
            sys.exit(1)
    print("The 6502 player set the expected SID registers on all %d frames%s" % (len(frames), " with sound effects" if sfx else ""))


if __name__ == "__main__":
    main()
