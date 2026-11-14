class_name MdSfx
extends RefCounted
## A sound effect for the Mega Drive, the way SGDK games usually play them:
## as a sample on SGDK's XGM driver, which mixes up to four 8-bit sounds at
## 14 kHz on FM 6's DAC, over the music.
##
## The sound is rendered at XGM's rate and rounded to 8 bits, so the
## preview has the console's grain, and it exports as an 8-bit WAV that
## SGDK's rescomp takes as it is.

## XGM's sample rate.
const RATE := 14000
## Headroom, so loud sounds don't clip when XGM mixes them with others.
const LEVEL := 0.85

var name := "sfx"
## The sound at [constant RATE], already rounded to 8 bits, -1 to 1.
var samples := PackedFloat32Array()


static func from_sfx(sfx: ChipSfx, sound_name := "") -> MdSfx:
	var out := MdSfx.new()
	out.name = sound_name if sound_name != "" else sfx.get_sound_name()
	var raw := sfx.render(RATE)
	out.samples.resize(raw.size())
	for i in raw.size():
		out.samples[i] = roundf(clampf(raw[i] * LEVEL, -1.0, 1.0) * 127.0) / 127.0
	return out


func seconds() -> float:
	return samples.size() / float(RATE)


## The sound at [param rate], held between samples as the DAC holds them.
func render(rate := 44100) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := int(ceilf(samples.size() * float(rate) / RATE))
	out.resize(count)
	var step := float(RATE) / rate
	for i in count:
		out[i] = samples[mini(int(i * step), samples.size() - 1)]
	return out


## The sound as an 8-bit mono WAV at 14 kHz.
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


## SGDK resource lines for a kit of sounds.
static func res_lines(sounds: Array) -> String:
	var lines: PackedStringArray = []
	for sfx: MdSfx in sounds:
		lines.append("WAV %s \"%s.wav\" XGM" % [symbol(sfx.name), sfx.name])
	return "\n".join(lines) + "\n"


static func symbol(sound_name: String) -> String:
	return "sfx_" + PsgWriter.symbol(sound_name)


## How to use the exported sounds, for the README inside the zip.
static func readme(kit: String, sounds: Array) -> String:
	var lines: PackedStringArray = [
		"%s: sound effects for the Mega Drive / Genesis, for SGDK" % kit,
		"",
		"Each sound is an 8-bit, 14 kHz WAV for SGDK's XGM driver, which plays up",
		"to four of them at once on FM 6 over the music (Chiptune Forge's music",
		"leaves FM 6 free for this).",
		"",
		"Put the WAVs and resources.res in your project's res/ folder (or add its",
		"lines to your own .res file). Then, once at startup, give each sound an id",
		"from 64 up:",
		"",
		"  #include <genesis.h>",
		"  #include \"resources.h\"",
		"",
	]
	for i in sounds.size():
		var sym := symbol((sounds[i] as MdSfx).name)
		lines.append("  XGM_setPCM(%d, %s, sizeof(%s));" % [64 + i, sym, sym])
	lines.append_array([
		"",
		"and play one with its id, a priority (0 to 15) and one of the PCM",
		"channels (SOUND_PCM_CH2 to SOUND_PCM_CH4; CH1 is for the music's samples):",
		"",
		"  XGM_startPlayPCM(64, 1, SOUND_PCM_CH2);",
		"",
		"Sounds:",
	])
	for i in sounds.size():
		var sfx: MdSfx = sounds[i]
		lines.append("  %d  %s  (%.2f s, %d bytes)" % [64 + i, symbol(sfx.name), sfx.seconds(), sfx.samples.size()])
	return "\n".join(lines) + "\n"
