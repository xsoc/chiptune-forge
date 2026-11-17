class_name SnesSfx
extends RefCounted
## A sound effect for the SNES, the way PVSnesLib games play them: a BRR
## sample that SNESMod plays on voice 8, over the music.
##
## The sound is rendered at 16 kHz (SNESMod's pitch 4) and exported as BRR,
## with the assembly and C lines that load it with spcSetSoundEntry.

## The sample rate: SNESMod's sound effect pitch 4 plays 16 kHz.
const RATE := 16000
const PITCH := 4
## Headroom, so the DSP's interpolation doesn't clip.
const LEVEL := 0.8

var name := "sfx"
## The sound at [constant RATE], 16-bit.
var pcm := PackedInt32Array()


static func from_sfx(sfx: ChipSfx, sound_name := "") -> SnesSfx:
	var out := SnesSfx.new()
	out.name = sound_name if sound_name != "" else sfx.get_sound_name()
	var raw := sfx.render(RATE)
	out.pcm.resize(raw.size())
	for i in raw.size():
		out.pcm[i] = clampi(roundi(raw[i] * LEVEL * 32767.0), -32768, 32767)
	return out


func seconds() -> float:
	return pcm.size() / float(RATE)


## The sound as BRR, padded to whole blocks.
func brr_bytes() -> PackedByteArray:
	return SnesBrr.encode(pcm)["data"]


## The sound at [param rate], interpolated from 16 kHz.
func render(rate := 44100) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(ceilf(pcm.size() * float(rate) / RATE))
	out.resize(count)
	var step := float(RATE) / rate
	for i in count:
		var pos := i * step
		var k := int(pos)
		var a := pcm[mini(k, pcm.size() - 1)]
		var b := pcm[mini(k + 1, pcm.size() - 1)]
		out[i] = lerpf(a, b, pos - k) / 32768.0
	return out


static func symbol(sound_name: String) -> String:
	return "sfx_" + PsgWriter.symbol(sound_name)


## WLA-DX assembly that puts the sounds in the ROM, with a label at the
## start and end of each.
static func data_asm(sounds: Array) -> String:
	var lines: PackedStringArray = [".include \"hdr.asm\"", ""]
	for sfx: SnesSfx in sounds:
		lines.append(".section \".%s\" superfree" % symbol(sfx.name))
		lines.append("%s: .incbin \"%s.brr\"" % [symbol(sfx.name), sfx.name])
		lines.append("%s_end:" % symbol(sfx.name))
		lines.append(".ends")
		lines.append("")
	return "\n".join(lines)


## How to use the exported sounds, for the README inside the zip.
static func readme(kit: String, sounds: Array) -> String:
	var lines: PackedStringArray = [
		"%s: sound effects for the SNES, for PVSnesLib" % kit,
		"",
		"Each sound is a BRR sample at 16 kHz. SNESMod plays them on voice 8, over",
		"the music (Chiptune Forge's SNES music leaves voice 8 free).",
		"",
		"Copy the .brr files and data.asm into your project (or add data.asm's",
		"lines to your own). Then, once at startup, after spcBoot() and loading",
		"your music, make room in audio RAM and register each sound:",
		"",
		"  extern char %s;" % ", ".join(PackedStringArray(sounds.map(func(s: SnesSfx) -> String: return "%s, %s_end" % [symbol(s.name), symbol(s.name)]))),
		"  brrsamples sounds[%d];" % sounds.size(),
		"",
		"  spcAllocateSoundRegion(%d);" % _blocks(sounds),
	]
	for i in sounds.size():
		var sym := symbol((sounds[i] as SnesSfx).name)
		lines.append("  spcSetSoundEntry(15, 8, %d, &%s_end - &%s, &%s, &sounds[%d]);" % [PITCH, sym, sym, sym, i])
	lines.append_array([
		"",
		"and play one by its number:",
		"",
		"  spcPlaySound(0);",
		"",
		"Sounds:",
	])
	for i in sounds.size():
		var sfx: SnesSfx = sounds[i]
		lines.append("  %d  %s  (%.2f s, %d bytes)" % [i, symbol(sfx.name), sfx.seconds(), int(ceil(sfx.pcm.size() / 16.0)) * SnesBrr.BLOCK_BYTES])
	return "\n".join(lines) + "\n"


## 256-byte blocks of audio RAM the sounds need, for spcAllocateSoundRegion.
static func _blocks(sounds: Array) -> int:
	var bytes := 0
	for sfx: SnesSfx in sounds:
		bytes += int(ceil(sfx.pcm.size() / 16.0)) * SnesBrr.BLOCK_BYTES
	return int(ceil(bytes / 256.0)) + 1
