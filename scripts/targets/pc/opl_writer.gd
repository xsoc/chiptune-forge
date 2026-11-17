class_name OplWriter
extends RefCounted
## Writes PC FM songs in the formats DOS-era engines and players read.
##
## [OplPlayer] writes the chip's registers once per 70 Hz frame; recording
## those writes gives each format:[br]
## - IMF (id Software's music format, type 1 at 700 Hz, as in Wolfenstein
##   3-D): register, value and a wait in 1/700 s ticks. OPL2 only.[br]
## - DRO 2.0 (DOSBox's raw OPL capture): register codes and value pairs
##   with millisecond waits, for one OPL2, two OPL2s or an OPL3. AdPlug and
##   most OPL players and trackers read it.[br]
## - VGM 1.51, with the YM3812 (one or two) or the YMF262.

const IMF_HZ := 700
const TICKS_PER_FRAME := 10
const VGM_SAMPLES_PER_FRAME := 630
const DRO_SHORT_DELAY := 0x7E
const DRO_LONG_DELAY := 0x7F


## A chip stand-in that keeps the register writes made to it.
class Recorder:
	extends RefCounted

	var writes: Array = []
	var channel_gain := PackedFloat32Array()

	func write(bank: int, reg: int, value: int) -> void:
		writes.append(PackedInt32Array([bank & 1, reg & 0xFF, value & 0xFF]))

	func reset() -> void:
		pass

	func set_gain(_channel: int, _gain: float) -> void:
		pass


## Plays [param song] once through and returns {frames: the writes of each
## frame, as [bank, register, value], loop_frame: the frame the loop
## starts on, or -1}. Frame 0 also holds the setup writes. At the loop point
## every register is written again, so the loop sounds the same however
## the song ended.
static func record(song: OplSong) -> Dictionary:
	var rec := Recorder.new()
	var player := OplPlayer.new(song, rec)
	var setup := rec.writes
	var total := song.frames_before(song.row_count)
	var loop_frame := song.frames_before(song.loop_start_row) if song.looping else -1
	var frames: Array = []
	for f in total:
		rec.writes = []
		if f == 0:
			rec.writes.append_array(setup)
		if f == loop_frame and f > 0:
			player.invalidate()
		player.tick()
		frames.append(rec.writes)
	# Silence at the end, so players that stop at the last write don't leave
	# notes hanging.
	var tail: Array = []
	var banks := 1 if song.chip == "opl2" else 2
	for bank in banks:
		for c in 9:
			tail.append(PackedInt32Array([bank, 0xB0 + c, 0]))
		if song.rhythm_on(bank):
			tail.append(PackedInt32Array([bank, 0xBD, 0x20]))
	return {"frames": frames, "loop_frame": loop_frame, "tail": tail}


## An IMF type 1 file: a 16-bit length, then 4-byte records of register,
## value and the wait after it in 1/700 s, and AdPlug's tag (title,
## composer, remarks). Only the first chip's writes. Saved as .wlf, the
## extension players read as 700 Hz.
static func imf_bytes(recorded: Dictionary, title := "") -> PackedByteArray:
	var data := PackedByteArray()
	# id's files open with an empty write.
	_imf_record(data, 0, 0, 0)
	var frames: Array = recorded["frames"]
	for f in frames.size():
		var writes: Array = frames[f]
		for w in writes:
			if int(w[0]) != 0:
				continue
			_imf_record(data, w[1], w[2], 0)
		# The frame's wait goes on its last record; an empty frame lengthens
		# the one before.
		var at := data.size() - 2
		data.encode_u16(at, data.decode_u16(at) + TICKS_PER_FRAME)
	for w in recorded.get("tail", []):
		if int(w[0]) == 0:
			_imf_record(data, w[1], w[2], 0)
	var out := PackedByteArray()
	out.resize(2)
	out.encode_u16(0, data.size())
	out.append_array(data)
	out.append(0x1A)
	for text in [title, "Chiptune Forge", "Made with Chiptune Forge"]:
		out.append_array(str(text).to_ascii_buffer())
		out.append(0)
	return out


static func _imf_record(data: PackedByteArray, reg: int, value: int, wait: int) -> void:
	var at := data.size()
	data.resize(at + 4)
	data[at] = reg
	data[at + 1] = value
	data.encode_u16(at + 2, wait)


## A DRO 2.0 file. [param chip] is "opl2", "dual_opl2" or "opl3".
static func dro_bytes(recorded: Dictionary, chip: String) -> PackedByteArray:
	var frames: Array = recorded["frames"]
	var all: Array = []
	for writes in frames:
		all.append_array(writes)
	all.append_array(recorded.get("tail", []))
	# The code map: every register written, in order of first use.
	var codemap := PackedByteArray()
	var code_of := {}
	for w in all:
		var reg := int(w[1])
		if not code_of.has(reg):
			code_of[reg] = codemap.size()
			codemap.append(reg)
	var data := PackedByteArray()
	var pairs := 0
	var ms_written := 0
	for f in frames.size():
		for w in frames[f]:
			data.append(int(code_of[int(w[1])]) | (0x80 if int(w[0]) else 0))
			data.append(int(w[2]))
			pairs += 1
		var ms_end := roundi((f + 1) * 1000.0 / OplSong.FRAME_HZ)
		var wait := ms_end - ms_written
		while wait > 0:
			if wait > 256:
				var longs := mini(wait / 256, 256)
				data.append(DRO_LONG_DELAY)
				data.append(longs - 1)
				wait -= longs * 256
			else:
				data.append(DRO_SHORT_DELAY)
				data.append(wait - 1)
				wait = 0
			pairs += 1
		ms_written = ms_end
	for w in recorded.get("tail", []):
		data.append(int(code_of[int(w[1])]) | (0x80 if int(w[0]) else 0))
		data.append(int(w[2]))
		pairs += 1
	var header := PackedByteArray("DBRAWOPL".to_ascii_buffer())
	header.resize(26)
	header.encode_u16(8, 2)
	header.encode_u16(10, 0)
	header.encode_u32(12, pairs)
	header.encode_u32(16, ms_written)
	header[20] = {"opl2": 0, "dual_opl2": 1, "opl3": 2}.get(chip, 0)
	header[21] = 0
	header[22] = 0
	header[23] = DRO_SHORT_DELAY
	header[24] = DRO_LONG_DELAY
	header[25] = codemap.size()
	header.append_array(codemap)
	header.append_array(data)
	return header


## A VGM 1.51 file of the recorded frames, with the loop.
static func vgm_bytes(recorded: Dictionary, chip: String, title := "", system := "IBM PC", credit := "") -> PackedByteArray:
	var frames: Array = recorded["frames"]
	var loop_frame := int(recorded["loop_frame"])
	var data := PackedByteArray()
	var loop_offset := -1
	for f in frames.size():
		if f == loop_frame:
			loop_offset = data.size()
		for w in frames[f]:
			var bank := int(w[0])
			var cmd := 0x5A
			if chip == "opl3":
				cmd = 0x5F if bank else 0x5E
			elif bank:
				cmd = 0xAA
			data.append(cmd)
			data.append(int(w[1]))
			data.append(int(w[2]))
		data.append(0x61)
		data.append(VGM_SAMPLES_PER_FRAME & 0xFF)
		data.append(VGM_SAMPLES_PER_FRAME >> 8)
	data.append(0x66)
	var header := PackedByteArray()
	header.resize(0x100)
	header.fill(0)
	header.encode_u32(0x00, 0x206D6756)
	header.encode_u32(0x08, 0x151)
	header.encode_u32(0x18, frames.size() * VGM_SAMPLES_PER_FRAME)
	if loop_offset >= 0:
		header.encode_u32(0x1C, 0x100 + loop_offset - 0x1C)
		header.encode_u32(0x20, (frames.size() - loop_frame) * VGM_SAMPLES_PER_FRAME)
	header.encode_u32(0x34, 0x100 - 0x34)
	match chip:
		"opl3":
			header.encode_u32(0x5C, 14318180)
		"dual_opl2":
			header.encode_u32(0x50, int(Opl.CLOCK) | 0x40000000)
		_:
			header.encode_u32(0x50, int(Opl.CLOCK))
	header.append_array(data)
	var tag := gd3(title, system, credit)
	if not tag.is_empty():
		header.encode_u32(0x14, header.size() - 0x14)
		header.append_array(tag)
	header.encode_u32(0x04, header.size() - 4)
	return header


static func gd3(title: String, system: String, note: String) -> PackedByteArray:
	if title == "" and note == "":
		return PackedByteArray()
	var strings := [title, "", "", "", system, "", "", "", "Chiptune Forge", "", "", note]
	var body := PackedByteArray()
	for s: String in strings:
		body.append_array(s.to_utf16_buffer())
		body.append_array(PackedByteArray([0, 0]))
	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, 0x20336447)
	out.encode_u32(4, 0x100)
	out.encode_u32(8, body.size())
	out.append_array(body)
	return out


## How to use an exported song, for the README inside the zip.
static func song_readme(prefix: String, opl: OplSong) -> String:
	var card := PcCards.name_of(opl.card)
	var lines: PackedStringArray = [
		"%s: music for the %s" % [prefix, card],
		"",
	]
	if opl.chip == "opl2":
		lines.append_array([
			"%s.wlf  IMF, type 1, at 700 Hz: the format of id Software's games" % prefix,
			"        (Wolfenstein 3-D and its engine's descendants). Each record is a",
			"        register, a value and a wait in 1/700 s, for ports 388h and 389h.",
			"        Players such as AdPlug read the .wlf extension as 700 Hz; rename it",
			"        to .imf for engines that expect that name.",
		])
	lines.append_array([
		"%s.dro  DOSBox Raw OPL 2.0: the register writes with their timing, for %s." % [prefix, {"opl2": "one OPL2", "dual_opl2": "two OPL2s (left and right)", "opl3": "an OPL3"}[opl.chip]],
		"        AdPlug, DOSBox's players and most OPL trackers open it.",
		"%s.vgm  VGM 1.51 for the %s, with the loop. VGM players," % [prefix, {"opl2": "YM3812", "dual_opl2": "two YM3812s", "opl3": "YMF262"}[opl.chip]],
		"        Furnace and DefleMask open it.",
		"",
		"The driver writes the chip 70 times a second. To play the song in your own",
		"DOS program, send each write to the card (index to 388h, data to 389h%s)" % (", or 38Ah/38Bh for the second bank" if opl.chip == "opl3" else (", 220h/221h and 222h/223h for the left and right chips" if opl.chip == "dual_opl2" else "")),
		"and wait between frames as the file says.",
		"",
		"Channels:",
	])
	for v in opl.layout:
		var where := "drum (rhythm mode)" if str(v["drum"]) != "" else "channel %d" % (int(v["ch"]) + 1)
		var bank := ""
		if opl.chip == "dual_opl2":
			bank = " on the %s chip" % ("right" if int(v["bank"]) else "left")
		elif opl.chip == "opl3" and int(v["bank"]) == 1:
			bank = " of the second bank"
		lines.append("  %-18s %s%s" % [v["name"], where, bank])
	lines.append("")
	lines.append("Arrangement:")
	for line in opl.report:
		lines.append("  " + line)
	return "\n".join(lines) + "\n"


## How to use exported sound effects, for the README inside the zip.
static func sfx_readme(kit: String, card: String, sounds: Array) -> String:
	var lines: PackedStringArray = ["%s: sound effects for the %s" % [kit, PcCards.name_of(card)], ""]
	if card == "adlib":
		lines.append_array([
			"The AdLib has no sample channel, so each sound is FM: a patch on OPL",
			"channel %d (the music's harmony channel, which it gets back afterwards)" % (PcSfx.OPL_CHANNEL + 1),
			"whose pitch and level follow the sound 70 times a second. Each comes as",
			"a DRO file and an IMF file at 700 Hz (.wlf), like the music.",
		])
	elif card == "sb16":
		lines.append_array([
			"Each sound is a 16-bit, 22,050 Hz mono WAV for the Sound Blaster 16's DAC.",
		])
	else:
		lines.append_array([
			"Each sound is a Creative Voice File (.voc): 8-bit unsigned samples at %s Hz," % ("11,025" if card == "sb" else "22,050"),
			"for the Sound Blaster's DAC, over the FM music. Creative's own drivers and",
			"most DOS sound libraries load .voc files directly.",
		])
	lines.append("")
	lines.append("Sounds:")
	for s: PcSfx in sounds:
		lines.append("  %-20s %.2f s" % [s.name, s.seconds()])
	return "\n".join(lines) + "\n"
