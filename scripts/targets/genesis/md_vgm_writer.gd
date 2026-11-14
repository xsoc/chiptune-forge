class_name MdVgmWriter
extends RefCounted
## Writes Mega Drive songs as VGM files, the format SGDK's rescomp converts
## to XGM music (and that VGM players, Furnace and DefleMask open).
##
## [MdPlayer] writes the chips' registers once per frame; recording those
## writes with a stand-in for [MdSound] gives the VGM commands: 0x52 and
## 0x53 for the YM2612's two register banks, 0x50 for the SN76489, and a
## 1/60 s wait (0x62) after each frame. XGM's converter works on exactly
## this frame-by-frame form.

const CMD_PSG := 0x50
const CMD_YM_PORT0 := 0x52
const CMD_YM_PORT1 := 0x53
const CMD_WAIT_FRAME := 0x62
const CMD_END := 0x66
const SAMPLES_PER_FRAME := 735


## A chip stand-in that keeps the commands written to it.
class Recorder:
	extends RefCounted

	var bytes := PackedByteArray()
	var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

	func fm_write(port: int, reg: int, value: int) -> void:
		bytes.append(CMD_YM_PORT1 if port else CMD_YM_PORT0)
		bytes.append(reg & 0xFF)
		bytes.append(value & 0xFF)

	func psg_write(value: int) -> void:
		bytes.append(CMD_PSG)
		bytes.append(value & 0xFF)

	func reset() -> void:
		pass


## Plays [param song] once through and returns {frames: one PackedByteArray
## of VGM commands per frame, loop_frame: the frame the loop starts on, or
## -1}. At the loop point every register is written again, so the loop
## sounds the same however the song ended. Frame 0 also holds the setup
## writes made before the first note.
static func record(song: MdSong, channel_mask := 0x3FF) -> Dictionary:
	var rec := Recorder.new()
	var player := MdPlayer.new(song, rec)
	player.channel_mask = channel_mask
	# The constructor already wrote the setup with every channel; start again
	# with the mask in place.
	rec.bytes = PackedByteArray()
	player.start(0)
	var setup := rec.bytes
	var total := song.frames_before(song.row_count)
	var loop_frame := song.frames_before(song.loop_start_row) if song.looping else -1
	var frames: Array[PackedByteArray] = []
	for f in total:
		rec.bytes = PackedByteArray()
		if f == 0:
			rec.bytes.append_array(setup)
		if f == loop_frame and f > 0:
			player.invalidate()
		player.tick()
		frames.append(rec.bytes)
	return {"frames": frames, "loop_frame": loop_frame}


## A VGM 1.60 file of recorded frames, NTSC.
static func vgm_bytes(recorded: Dictionary, title := "", credit := "") -> PackedByteArray:
	var frames: Array = recorded["frames"]
	var loop_frame := int(recorded["loop_frame"])
	var data := PackedByteArray()
	var loop_offset := -1
	for f in frames.size():
		if f == loop_frame:
			loop_offset = data.size()
		data.append_array(frames[f])
		data.append(CMD_WAIT_FRAME)
	data.append(CMD_END)
	var header := PackedByteArray()
	header.resize(0x100)
	header.fill(0)
	header.encode_u32(0x00, 0x206D6756)
	header.encode_u32(0x08, 0x160)
	header.encode_u32(0x0C, int(SmsPsg.CLOCK))
	header.encode_u32(0x18, frames.size() * SAMPLES_PER_FRAME)
	if loop_offset >= 0:
		header.encode_u32(0x1C, 0x100 + loop_offset - 0x1C)
		header.encode_u32(0x20, (frames.size() - loop_frame) * SAMPLES_PER_FRAME)
	header.encode_u32(0x24, 60)
	header.encode_u16(0x28, 0x0009)
	header[0x2A] = 16
	header.encode_u32(0x2C, int(Ym2612.CLOCK))
	header.encode_u32(0x34, 0x100 - 0x34)
	header.append_array(data)
	var gd3 := gd3_tag(title, credit)
	if not gd3.is_empty():
		header.encode_u32(0x14, header.size() - 0x14)
		header.append_array(gd3)
	header.encode_u32(0x04, header.size() - 4)
	return header


## A GD3 tag (VGM's metadata block) with the track title, the system and a
## note, in UTF-16.
static func gd3_tag(title: String, note: String) -> PackedByteArray:
	if title == "" and note == "":
		return PackedByteArray()
	var strings := [title, "", "", "", "Sega Mega Drive / Genesis", "", "", "", "Chiptune Forge", "", "", note]
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


## The SGDK resource line for a song.
static func res_line(symbol: String, file: String) -> String:
	return "XGM %s \"%s\"" % [symbol, file]


## How to use the exported music, for the README inside the zip.
static func readme(base: String) -> String:
	var sym := PsgWriter.symbol(base)
	return "\n".join([
		"%s.vgm: music for the Mega Drive / Genesis, for SGDK" % base,
		"",
		"SGDK (https://github.com/Stephane-D/SGDK, MIT licence) converts VGM files to",
		"its XGM driver's format when it builds your game. The music uses FM 1 to 5",
		"and the PSG; FM 6 is left free for XGM's sampled sound effects.",
		"",
		"Files:",
		"  %s.vgm        The song (YM2612 + SN76489, NTSC, with its loop point)." % base,
		"  resources.res  The resource line for rescomp.",
		"  main.c         A minimal SGDK program that plays it.",
		"",
		"To try it, make an SGDK project with res/ and src/ folders, put %s.vgm and" % base,
		"resources.res in res/ and main.c in src/, and build as usual, for example:",
		"",
		"  docker run --rm -v \"$PWD\":/src ghcr.io/stephane-d/sgdk",
		"",
		"In your own game:",
		"",
		"  #include <genesis.h>",
		"  #include \"resources.h\"",
		"",
		"  XGM_startPlay(%s);      /* loops from the loop point */" % sym,
		"  XGM_stopPlay();",
		"",
		"%s.vgm also opens in VGM players, Furnace and DefleMask." % base,
		"",
		"Timing is NTSC (60 frames a second). On a PAL console XGM can keep the",
		"speed: call XGM_setForceDelayDMA or see SGDK's XGM documentation.",
	]) + "\n"


## A minimal SGDK program that shows the title and plays the song.
static func main_c(symbol: String, title: String) -> String:
	var shown := title.replace("\\", "/").replace("\"", "'").left(36)
	return "\n".join([
		"/* Plays %s with SGDK's XGM driver. Made with Chiptune Forge. */" % symbol,
		"#include <genesis.h>",
		"#include \"resources.h\"",
		"",
		"int main(bool hardReset)",
		"{",
		"    (void) hardReset;",
		"    VDP_drawText(\"%s\", 2, 2);" % shown,
		"    VDP_drawText(\"Made with Chiptune Forge\", 2, 4);",
		"    XGM_startPlay(%s);" % symbol,
		"    while (TRUE)",
		"    {",
		"        SYS_doVBlankProcess();",
		"    }",
		"    return 0;",
		"}",
	]) + "\n"
