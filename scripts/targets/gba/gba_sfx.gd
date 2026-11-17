class_name GbaSfx
extends RefCounted
## A sound effect for the Game Boy Advance, the way Maxmod games play them:
## an 8-bit sample in the soundbank, which mmEffect plays over the music on
## a channel of its own.
##
## The sound is rendered at Maxmod's mixing rate and rounded to 8 bits, so
## the preview has the console's grain, and it exports as an 8-bit WAV that
## mmutil takes as it is.

## The rate the sound is made at: Maxmod mixes at 16 kHz.
const RATE := 16384
## Headroom, so loud sounds don't clip when Maxmod mixes them with the music.
const LEVEL := 0.85

var name := "sfx"
## The sound at [constant RATE], already rounded to 8 bits, -1 to 1.
var samples := PackedFloat32Array()


static func from_sfx(sfx: ChipSfx, sound_name := "") -> GbaSfx:
	var out := GbaSfx.new()
	out.name = sound_name if sound_name != "" else sfx.get_sound_name()
	var raw := sfx.render(RATE)
	out.samples.resize(raw.size())
	for i in raw.size():
		out.samples[i] = roundf(clampf(raw[i] * LEVEL, -1.0, 1.0) * 127.0) / 127.0
	return out


func seconds() -> float:
	return samples.size() / float(RATE)


## The sound at [param rate], held between samples as the mixer holds them.
func render(rate := 44100) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(ceilf(samples.size() * float(rate) / RATE))
	out.resize(count)
	var step := float(RATE) / rate
	for i in count:
		out[i] = samples[mini(int(i * step), samples.size() - 1)]
	return out


## The sound as an 8-bit mono WAV at 16 kHz.
func wav_bytes() -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size())
	for i in samples.size():
		pcm[i] = clampi(roundi(samples[i] * 127.0) + 128, 0, 255)
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_u32(36 + pcm.size()))
	out.append_array("WAVEfmt ".to_ascii_buffer())
	out.append_array(_u32(16))
	out.append_array(PackedByteArray([1, 0, 1, 0]))
	out.append_array(_u32(RATE))
	out.append_array(_u32(RATE))
	out.append_array(PackedByteArray([1, 0, 8, 0]))
	out.append_array("data".to_ascii_buffer())
	out.append_array(_u32(pcm.size()))
	out.append_array(pcm)
	return out


static func _u32(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, value)
	return b


## The id mmutil gives a sound in soundbank.h: SFX_ and its file name in
## capitals, with anything else made an underscore.
static func symbol(sound_name: String) -> String:
	return ItWriter.module_id(sound_name).replace("MOD_", "SFX_")


## How to use the exported sounds, for the README inside the zip.
static func readme(kit: String, sounds: Array) -> String:
	var lines: PackedStringArray = [
		"%s: sound effects for the Game Boy Advance, for Maxmod" % kit,
		"",
		"Each sound is an 8-bit, 16 kHz WAV for Maxmod (devkitPro's sound library).",
		"Put the WAVs in your project's audio/ folder with your music: devkitPro's",
		"GBA Makefile runs mmutil on that folder and makes soundbank.bin and",
		"soundbank.h. Then play a sound over the music with:",
		"",
		"  #include <maxmod.h>",
		"  #include \"soundbank.h\"",
		"",
		"  mmEffect(%s);" % (symbol((sounds[0] as GbaSfx).name) if not sounds.is_empty() else "SFX_COIN"),
		"",
		"Chiptune Forge's music leaves Maxmod's channel 8 free, so a sound never",
		"cuts a part of the song.",
		"",
		"Sounds:",
	]
	for sfx: GbaSfx in sounds:
		lines.append("  %s  (%.2f s, %d bytes)" % [symbol(sfx.name), sfx.seconds(), sfx.samples.size()])
	return "\n".join(lines) + "\n"
