class_name PsgWriter
extends RefCounted
## Writes Master System songs and sound effects as PSGlib data (.psg), as C
## arrays for devkitSMS, and as VGM files.
##
## PSGlib (sverx, github.com/sverx/PSGlib, also part of devkitSMS) plays a
## stream of SN76489 port writes, one frame at a time:[br]
## - a byte with bit 7 set is a latch byte, written to the chip as it is;[br]
## - a byte from $40 to $7F is a data byte for the last latched register;[br]
## - $38 to $3F wait 1 to 8 frames; $01 marks the loop point; $00 ends.[br]
## [SmsPlayer] writes exactly these bytes, so recording it gives the data.
## The data is uncompressed, which PSGlib plays as it is; PSGlib's psgcomp
## tool can compress it.

const END := 0x00
const LOOP_MARKER := 0x01
const WAIT := 0x38


## A chip stand-in that keeps the bytes written to it.
class Recorder:
	extends RefCounted

	var bytes := PackedByteArray()
	var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])

	func write(value: int) -> void:
		bytes.append(value & 0xFF)

	func reset() -> void:
		pass


## Plays [param song] once through and returns {frames: one PackedByteArray
## of port writes per frame, loop_frame: the frame the loop starts on, or
## -1}. At the loop point every register is written again, so the loop
## sounds the same however the song ended.
static func record(song: SmsSong, channel_mask := 0x0F) -> Dictionary:
	var rec := Recorder.new()
	var player := SmsPlayer.new(song, rec)
	player.channel_mask = channel_mask
	var total := song.frames_before(song.row_count)
	var loop_frame := song.frames_before(song.loop_start_row) if song.looping else -1
	var frames: Array[PackedByteArray] = []
	for f in total:
		if f == loop_frame:
			player.invalidate()
		rec.bytes = PackedByteArray()
		player.tick()
		frames.append(rec.bytes)
	return {"frames": frames, "loop_frame": loop_frame}


## PSGlib data for a song.
static func song_bytes(song: SmsSong) -> PackedByteArray:
	return encode(record(song))


## PSGlib data for a sound effect: it writes only its own channel.
static func sfx_bytes(sfx: SmsSfx) -> PackedByteArray:
	return encode(record(sfx.to_song(), 1 << sfx.channel))


## Encodes recorded frames as PSGlib data.
static func encode(recorded: Dictionary) -> PackedByteArray:
	var frames: Array = recorded["frames"]
	var loop_frame := int(recorded["loop_frame"])
	var out := PackedByteArray()
	var wait := 0
	for f in frames.size():
		var bytes: PackedByteArray = frames[f]
		if f == loop_frame:
			wait = _flush_wait(out, wait)
			out.append(LOOP_MARKER)
		if not bytes.is_empty():
			wait = _flush_wait(out, wait)
			out.append_array(bytes)
		wait += 1
	_flush_wait(out, wait)
	out.append(END)
	return out


static func _flush_wait(out: PackedByteArray, frames: int) -> int:
	while frames > 8:
		out.append(WAIT + 7)
		frames -= 8
	if frames > 0:
		out.append(WAIT + frames - 1)
	return 0


## The same frames as a VGM 1.50 file for the SN76489 (NTSC), which VGM
## players, Furnace and DefleMask open, and from which PSGlib's own vgm2psg
## makes the same PSGlib data.
static func vgm_bytes(recorded: Dictionary) -> PackedByteArray:
	var frames: Array = recorded["frames"]
	var loop_frame := int(recorded["loop_frame"])
	var data := PackedByteArray()
	var loop_offset := -1
	for f in frames.size():
		if f == loop_frame:
			loop_offset = data.size()
		for b in frames[f]:
			data.append(0x50)
			data.append(b)
		data.append(0x62)
	data.append(0x66)
	var header := PackedByteArray()
	header.resize(0x100)
	header.fill(0)
	header.encode_u32(0x00, 0x206D6756)
	header.encode_u32(0x04, 0x100 + data.size() - 4)
	header.encode_u32(0x08, 0x150)
	header.encode_u32(0x0C, int(SmsPsg.CLOCK))
	var samples_per_frame := 735
	header.encode_u32(0x18, frames.size() * samples_per_frame)
	if loop_offset >= 0:
		header.encode_u32(0x1C, 0x100 + loop_offset - 0x1C)
		header.encode_u32(0x20, (frames.size() - loop_frame) * samples_per_frame)
	header.encode_u32(0x24, 60)
	header.encode_u16(0x28, 0x0009)
	header[0x2A] = 16
	header.encode_u32(0x34, 0x100 - 0x34)
	header.append_array(data)
	return header


## A C symbol for a name: lower case letters, digits and underscores.
static func symbol(name: String) -> String:
	var out := ""
	for ch in name.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	if out == "" or (out[0] >= "0" and out[0] <= "9"):
		out = "s_" + out
	return out


## A C source file holding [param blobs] ({symbol: PackedByteArray}) as
## const arrays, in devkitSMS's folder2c style.
static func c_source(blobs: Dictionary, header_name: String, comment: String) -> String:
	var lines: PackedStringArray = ["/* %s */" % comment, "#include \"%s\"" % header_name, ""]
	for sym in blobs:
		var bytes: PackedByteArray = blobs[sym]
		lines.append("const unsigned char %s[%d] = {" % [sym, bytes.size()])
		var row: PackedStringArray = []
		for i in bytes.size():
			row.append("0x%02x" % bytes[i])
			if row.size() == 16 or i == bytes.size() - 1:
				lines.append("  " + ",".join(row) + ("," if i < bytes.size() - 1 else ""))
				row = []
		lines.append("};")
		lines.append("")
	return "\n".join(lines)


static func c_header(blobs: Dictionary, guard: String, comment: String) -> String:
	var lines: PackedStringArray = ["/* %s */" % comment, "#ifndef %s" % guard, "#define %s" % guard, ""]
	for sym in blobs:
		var size: int = (blobs[sym] as PackedByteArray).size()
		lines.append("#define %s_size %d" % [sym, size])
		lines.append("extern const unsigned char %s[%d];" % [sym, size])
		lines.append("")
	lines.append("#endif")
	return "\n".join(lines) + "\n"


## How to use the exported data, for the README inside the zip.
static func readme(kind: String, base: String, sounds: Array = []) -> String:
	var lines: PackedStringArray = []
	if kind == "sfx":
		lines.append_array([
			"%s: sound effects as PSGlib data, for the Master System and Game Gear" % base,
			"",
			"PSGlib plays SN76489 music and sound effects; it ships with devkitSMS",
			"(https://github.com/sverx/devkitSMS) and as Z80 assembly",
			"(https://github.com/sverx/PSGlib).",
			"",
			"Files:",
			"  *.psg       One PSGlib file per sound, for assembly (incbin) or assets2banks.",
			"  %s.c/.h  The same data as C arrays, for devkitSMS and SDCC." % base,
			"  *.vgm       Each sound as a VGM file, for VGM players and trackers.",
			"",
			"Play a sound over the music, on the channel it uses:",
			"",
		])
		for sfx: SmsSfx in sounds:
			lines.append("  PSGSFXPlay(%s_psg, %s);" % [symbol(sfx.name), sfx.psglib_channel()])
		lines.append_array([
			"",
			"and call PSGSFXFrame() once per frame, after PSGFrame(). PSGlib gives the",
			"channel back to the music when the sound ends.",
		])
	else:
		var sym := symbol(base) + "_psg"
		lines.append_array([
			"%s.psg: music as PSGlib data, for the Master System and Game Gear" % base,
			"",
			"PSGlib plays SN76489 music and sound effects; it ships with devkitSMS",
			"(https://github.com/sverx/devkitSMS) and as Z80 assembly",
			"(https://github.com/sverx/PSGlib).",
			"",
			"Files:",
			"  %s.psg    PSGlib data, for assembly (incbin) or devkitSMS's assets2banks." % base,
			"  %s_psg.c/.h  The same data as a C array, for devkitSMS and SDCC." % base,
			"  %s.vgm    The song as a VGM file, for VGM players, Furnace and DefleMask." % base,
			"",
			"With devkitSMS (C):",
			"",
			"  #include \"SMSlib.h\"",
			"  #include \"PSGlib.h\"",
			"  #include \"%s_psg.h\"" % base,
			"",
			"  PSGPlay(%s);            /* loops; PSGPlayNoRepeat plays once */" % sym,
			"  for (;;) {",
			"    SMS_waitForVBlank();",
			"    PSGFrame();",
			"    PSGSFXFrame();",
			"  }",
			"",
			"Link with PSGlib.rel (sdcc -mz80 ... PSGlib.rel). In assembly, incbin",
			"%s.psg and call PSGPlay with its address, then PSGFrame every frame." % base,
			"",
			"The data is uncompressed. PSGlib's psgcomp tool (in its tools folder)",
			"compresses it, usually to about half, and PSGlib plays both forms.",
			"A ROM bank holds 16 KB; for longer songs compress them, or build PSGlib",
			"with PSGLIB_MULTIBANK.",
		])
	lines.append_array([
		"",
		"PSGlib runs on NTSC timing (60 frames a second). On a PAL console the",
		"music plays about a sixth slower unless you skip a frame now and then.",
	])
	return "\n".join(lines) + "\n"
