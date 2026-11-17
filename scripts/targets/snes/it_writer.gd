class_name ItWriter
extends RefCounted
## Writes a [SnesSong] as an Impulse Tracker module in the shape SNESMod
## needs (PVSnesLib's smconv converts it into a soundbank): instrument mode
## with one sample per instrument, at most 8 channels, 64 patterns and 200
## orders, 16-bit samples with loops on whole BRR blocks, and the echo set
## by "[[SNESMOD]]" commands in the song message. Also writes a small
## PVSnesLib project that plays it.

const MAX_PATTERNS := 64
const MAX_ORDERS := 199
const MAX_ROWS := 200
const HEADER := 0xC0
const INSTRUMENT_BYTES := 554
const SAMPLE_BYTES := 80
## Tracker version we claim (Impulse Tracker 2.14), as other writers do.
const VERSION := 0x0214


## The module's bytes.
## With [param eight_bit], samples are 8-bit (for Maxmod on the GBA, which
## mixes 8-bit samples) instead of 16-bit.
static func module_bytes(snes: SnesSong, eight_bit := false) -> PackedByteArray:
	var layout := pattern_layout(snes)
	var patterns: Array = layout["patterns"]
	var orders: Array = layout["orders"]
	var message := song_message(snes)
	var ins_count := snes.instruments.size()
	var smp_count := snes.samples.size()
	var out := PackedByteArray()
	out.append_array("IMPM".to_ascii_buffer())
	out.append_array(_text(snes.title, 26))
	out.append_array(_u16(snes.steps_per_beat | (snes.steps_per_bar << 8)))
	out.append_array(_u16(orders.size() + 1))
	out.append_array(_u16(ins_count))
	out.append_array(_u16(smp_count))
	out.append_array(_u16(patterns.size()))
	out.append_array(_u16(VERSION))
	out.append_array(_u16(VERSION))
	# Stereo, instruments, linear slides; old effects off.
	out.append_array(_u16(1 | 4 | 8))
	# A song message is attached.
	out.append_array(_u16(1))
	out.append_array(PackedByteArray([128, 48, snes.speed(), snes.tempo, 128, 0]))
	out.append_array(_u16(message.size()))
	var message_offset_at := out.size()
	out.append_array(_u32(0))
	out.append_array(_u32(0))
	for c in 64:
		out.append(snes.pans[c] if c < SnesSong.CHANNEL_COUNT else 32 | 128)
	for c in 64:
		out.append(64)
	for o in orders:
		out.append(int(o))
	out.append(255)
	var pointers_at := out.size()
	for i in ins_count + smp_count + patterns.size():
		out.append_array(_u32(0))
	var put := func(at: int, value: int) -> void: out.encode_u32(at, value)
	for i in ins_count:
		put.call(pointers_at + i * 4, out.size())
		out.append_array(_instrument(snes, i))
	var sample_headers := PackedInt32Array()
	for i in smp_count:
		put.call(pointers_at + (ins_count + i) * 4, out.size())
		sample_headers.append(out.size())
		out.append_array(_sample_header(snes.samples[i], eight_bit))
	for i in patterns.size():
		put.call(pointers_at + (ins_count + smp_count + i) * 4, out.size())
		out.append_array(_pattern(patterns[i]))
	put.call(message_offset_at, out.size())
	out.append_array(message)
	for i in smp_count:
		# Sample data, 16-bit signed, after everything else.
		out.encode_u32(sample_headers[i] + 0x48, out.size())
		var pcm: PackedInt32Array = SnesSamples.get_sample(snes.samples[i])["pcm"]
		var data := PackedByteArray()
		if eight_bit:
			data = eight_bit_pcm(pcm)
		else:
			data.resize(pcm.size() * 2)
			for k in pcm.size():
				data.encode_s16(k * 2, pcm[k])
		out.append_array(data)
	return out


## The song message: a credit, then SNESMod's echo commands.
static func song_message(snes: SnesSong) -> PackedByteArray:
	var echo: Dictionary = snes.echo
	var lines: PackedStringArray = ["%s" % snes.title, "Made with Chiptune Forge", "", "[[SNESMOD]]"]
	if int(echo.get("edl", 0)) > 0:
		lines.append("edl %d" % int(echo["edl"]))
		lines.append("efb %d" % int(echo["efb"]))
		lines.append("evol %d" % int(echo["evol"]))
		var fir: Array = echo.get("fir", [127, 0, 0, 0, 0, 0, 0, 0])
		lines.append("efir " + " ".join(PackedStringArray(fir.map(func(v: int) -> String: return str(v)))))
		var on: Array = []
		for c in SnesSong.CHANNEL_COUNT:
			if int(echo["eon"]) & (1 << c):
				on.append(str(c + 1))
		lines.append("eon " + " ".join(PackedStringArray(on)))
	var text := "\r".join(lines) + "\r"
	var out := text.to_ascii_buffer()
	out.append(0)
	return out


## Cuts the rows into patterns: breaking at sections and the loop start,
## then every 64 rows (longer if the song would need more than 64
## patterns), with identical patterns shared. Returns {patterns: Array of
## row arrays, orders: pattern index per order, loop_order}.
static func pattern_layout(snes: SnesSong) -> Dictionary:
	var rows := snes.rows()
	var breaks := {}
	for section in snes.section_rows:
		breaks[int(section["row"])] = true
	if snes.looping:
		breaks[snes.loop_start_row] = true
	var size := 64
	var result := {}
	while true:
		result = _layout(rows, breaks, size, snes)
		if (result["patterns"] as Array).size() <= MAX_PATTERNS or size >= MAX_ROWS:
			break
		size = mini(size * 2, MAX_ROWS)
	return result


static func _layout(rows: Array, breaks: Dictionary, size: int, snes: SnesSong) -> Dictionary:
	var starts: Array = []
	var r := 0
	while r < rows.size():
		starts.append(r)
		var end := mini(r + size, rows.size())
		for b in range(r + 1, end):
			if breaks.has(b):
				end = b
				break
		r = end
	var patterns: Array = []
	var keys := {}
	var orders: Array = []
	var loop_order := 0
	for i in starts.size():
		var first: int = starts[i]
		var last: int = starts[i + 1] if i + 1 < starts.size() else rows.size()
		if first == snes.loop_start_row:
			loop_order = i
		var chunk: Array = []
		for k in range(first, last):
			chunk.append(rows[k])
		var key := var_to_str(chunk)
		if not keys.has(key):
			keys[key] = patterns.size()
			patterns.append(chunk)
		orders.append(keys[key])
	# The jump at the end points at the loop's first order.
	for p in patterns:
		for row in p:
			var cell = row[SnesSong.SFX_CHANNEL]
			if cell != null and int(cell["command"]) == SnesSong.CMD_JUMP:
				cell["param"] = loop_order
	return {"patterns": patterns, "orders": orders.slice(0, MAX_ORDERS), "loop_order": loop_order}


static func _pattern(rows: Array) -> PackedByteArray:
	var data := PackedByteArray()
	for row in rows:
		for c in SnesSong.CHANNEL_COUNT:
			var cell = row[c]
			if cell == null:
				continue
			var mask := 0
			if int(cell["note"]) >= 0:
				mask |= 1
			if int(cell["instrument"]) > 0:
				mask |= 2
			if int(cell["volume"]) >= 0:
				mask |= 4
			if int(cell["command"]) > 0:
				mask |= 8
			if mask == 0:
				continue
			data.append((c + 1) | 128)
			data.append(mask)
			if mask & 1:
				data.append(int(cell["note"]))
			if mask & 2:
				data.append(int(cell["instrument"]))
			if mask & 4:
				data.append(int(cell["volume"]))
			if mask & 8:
				data.append(int(cell["command"]))
				data.append(int(cell["param"]) & 0xFF)
		data.append(0)
	var out := PackedByteArray()
	out.append_array(_u16(data.size()))
	out.append_array(_u16(rows.size()))
	out.append_array(_u32(0))
	out.append_array(data)
	return out


static func _instrument(snes: SnesSong, index: int) -> PackedByteArray:
	var inst: Dictionary = snes.instruments[index]
	var out := PackedByteArray()
	out.append_array("IMPI".to_ascii_buffer())
	out.append_array(_text(str(inst["name"]).to_lower(), 12))
	# 0, new note action (cut), duplicate check off.
	out.append_array(PackedByteArray([0, 0, 0, 0]))
	out.append_array(_u16(clampi(int(inst.get("fadeout", 0)) * 4, 0, 1024)))
	# Pitch-pan separation, centre, global volume, no default pan, no
	# random variation.
	out.append_array(PackedByteArray([0, 60, 128, 32 | 128, 0, 0]))
	out.append_array(_u16(VERSION))
	out.append_array(PackedByteArray([1, 0]))
	out.append_array(_text(str(inst["name"]), 26))
	# No filter, no MIDI.
	out.append_array(PackedByteArray([0, 0, 0, 0, 0, 0]))
	# Every note plays itself on the instrument's one sample (SNESMod only
	# reads the middle entry).
	for n in 120:
		out.append(n)
		out.append(int(inst["sample"]) + 1)
	out.append_array(_envelope(inst.get("env", {})))
	# Panning and pitch envelopes: off.
	out.append_array(_envelope({}))
	out.append_array(_envelope({}))
	out.resize(INSTRUMENT_BYTES)
	return out


## An envelope block: flags, node count, loop, sustain loop, 25 nodes of
## (level, tick), and a spare byte.
static func _envelope(env: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	var nodes: Array = env.get("nodes", [])
	var sustain := int(env.get("sustain", -1))
	var flags := 0
	if not nodes.is_empty():
		flags |= 1
		if sustain >= 0:
			flags |= 4
	out.append(flags)
	out.append(nodes.size())
	out.append(0)
	out.append(0)
	out.append(maxi(sustain, 0))
	out.append(maxi(sustain, 0))
	for i in 25:
		if i < nodes.size():
			out.append(clampi(int(nodes[i][1]), 0, 64))
			out.append_array(_u16(int(nodes[i][0])))
		else:
			out.append_array(PackedByteArray([0, 0, 0]))
	out.append(0)
	return out


## 16-bit samples rounded to signed 8-bit.
static func eight_bit_pcm(pcm: PackedInt32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(pcm.size())
	for k in pcm.size():
		data[k] = clampi(roundi(pcm[k] / 256.0), -128, 127) & 0xFF
	return data


static func _sample_header(sample_name: String, eight_bit := false) -> PackedByteArray:
	var sample := SnesSamples.get_sample(sample_name)
	var pcm: PackedInt32Array = sample["pcm"]
	var looped := int(sample["loop_length"]) > 0
	var out := PackedByteArray()
	out.append_array("IMPS".to_ascii_buffer())
	out.append_array(_text(sample_name, 12))
	out.append(0)
	out.append(64)
	# Has data, 16-bit, and loops if it does.
	out.append(1 | (0 if eight_bit else 2) | (16 if looped else 0))
	out.append(64)
	out.append_array(_text(sample_name.replace("_", " "), 26))
	# Signed samples; default pan unused.
	out.append(1)
	out.append(32)
	out.append_array(_u32(pcm.size()))
	out.append_array(_u32(int(sample["loop_start"])))
	out.append_array(_u32(int(sample["loop_start"]) + int(sample["loop_length"])))
	out.append_array(_u32(int(sample["c5"])))
	out.append_array(_u32(0))
	out.append_array(_u32(0))
	# Sample pointer, filled in later.
	out.append_array(_u32(0))
	out.append_array(PackedByteArray([0, 0, 0, 0]))
	return out


static func _text(text: String, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	for ch in text:
		var code := ch.unicode_at(0)
		out.append(code if code >= 32 and code < 127 else 32)
		if out.size() >= size - 1:
			break
	out.resize(size)
	return out


static func _u16(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, value & 0xFFFF)
	return b


static func _u32(value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, value)
	return b


## The id smconv gives a module: MOD_ and the file name up to its first dot,
## in capitals, with anything else made an underscore.
static func module_id(file_name: String) -> String:
	var base := file_name.get_file()
	var dot := base.find(".")
	if dot >= 0:
		base = base.substr(0, dot)
	var out := "MOD_"
	for ch in base.to_upper():
		var code := ch.unicode_at(0)
		out += ch if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) else "_"
	return out


## A Makefile for PVSnesLib that converts the module and builds a ROM.
static func makefile(prefix: String) -> String:
	return "\n".join([
		"# Builds %s.sfc, which plays the song. Needs PVSnesLib 4.7 or later:" % prefix,
		"# https://github.com/alekmaul/pvsneslib (set PVSNESLIB_HOME first).",
		"ifeq ($(strip $(PVSNESLIB_HOME)),)",
		"$(error \"Set PVSNESLIB_HOME to where PVSnesLib is installed\")",
		"endif",
		"",
		"AUDIOFILES := res/%s.it" % prefix,
		"export SOUNDBANK := res/soundbank",
		"export ROMNAME := %s" % prefix,
		"",
		"include ${PVSNESLIB_HOME}/devkitsnes/snes_rules",
		"",
		".PHONY: all",
		"",
		"SMCONVFLAGS := -s -o $(SOUNDBANK) -V -b 5",
		"musics: $(SOUNDBANK).obj",
		"",
		"all: musics $(ROMNAME).sfc",
		"",
		"clean: cleanBuildRes cleanRom cleanGfx cleanAudio",
		"",
	])


## A minimal PVSnesLib program that plays the song in a loop.
static func main_c(prefix: String, title: String) -> String:
	var id := module_id(prefix + ".it")
	return "\n".join([
		"// %s: plays the song with SNESMod, PVSnesLib's sound driver." % title,
		"// Made with Chiptune Forge.",
		"#include <snes.h>",
		"",
		"#include \"res/soundbank.h\"",
		"",
		"extern char SOUNDBANK__;",
		"",
		"int main(void)",
		"{",
		"    spcBoot();",
		"    spcSetBank(&SOUNDBANK__);",
		"    spcLoad(%s);" % id,
		"",
		"    setMode(BG_MODE1, 0);",
		"    setScreenOn();",
		"",
		"    spcPlay(0);",
		"    while (1)",
		"    {",
		"        spcProcess();",
		"        WaitForVBlank();",
		"    }",
		"    return 0;",
		"}",
		"",
	])


## How to use the export, for the README inside the zip.
static func readme(prefix: String, snes: SnesSong) -> String:
	var ram := snes.ram_use()
	return "\n".join([
		"%s: music for the SNES, for PVSnesLib" % snes.title,
		"",
		"res/%s.it is an Impulse Tracker module written for SNESMod, PVSnesLib's" % prefix,
		"sound driver. Its echo settings are in the song message. Voice 8 is left",
		"free for sound effects.",
		"",
		"To build the example ROM, install PVSnesLib (4.7 or later), set",
		"PVSNESLIB_HOME, and run make here. It makes %s.sfc, which plays the song." % prefix,
		"",
		"In your own game, add the module to AUDIOFILES in your Makefile and play it:",
		"",
		"  spcBoot();",
		"  spcSetBank(&SOUNDBANK__);",
		"  spcLoad(%s);" % module_id(prefix + ".it"),
		"  spcPlay(0);",
		"",
		"and call spcProcess() once a frame.",
		"",
		"You can also open the module in a tracker such as OpenMPT or Schism Tracker",
		"to edit it. Trackers play it about 2%% faster than SNESMod, whose timer",
		"rounds the tempo.",
		"",
		"Audio RAM: samples %.1f KB, echo %d KB, about %.1f KB left for the patterns." % [int(ram["bytes"]) / 1024.0, int(ram["echo"]) / 1024, int(ram["free"]) / 1024.0],
		"",
	])
