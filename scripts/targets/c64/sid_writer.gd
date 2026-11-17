class_name SidWriter
extends RefCounted
## Writes Commodore 64 songs and sound effects: PSID files (.sid) that any
## SID player and most C64 music routines load, data for our 6502 player
## (assets/c64/sid_player.s), and an example program for ca65.
##
## The data is the SID's registers frame by frame, in [RegStream]'s format.
## [SidPlayer] sets the registers, so recording it gives the data.

const PLAYER_SOURCE := "res://assets/c64/sid_player.s"
const PLAYER_BINARY := "res://assets/c64/sid_player.bin"
const PLAYER_CONFIG := "res://assets/c64/sid_player.cfg"
const LOAD_ADDRESS := 0x1000
## Where the player keeps the song's address.
const SONG_POINTER := 12
const REGS := SidChip.REGISTER_COUNT
## The registers a sound effect sets: voice 2's.
const SFX_REGS: PackedInt32Array = [7, 8, 9, 10, 11, 12, 13]


static func record_song(song: SidSong) -> Dictionary:
	var player := SidPlayer.new(song, SidChip.new(8000.0))
	var total := song.frames_before(song.row_count)
	var frames: Array[PackedInt32Array] = []
	for f in total:
		player.tick()
		frames.append(player.regs.duplicate())
	return {"frames": frames, "loop_frame": song.frames_before(song.loop_start_row) if song.looping else -1}


static func record_sfx(sfx: SidSfx) -> Array[PackedInt32Array]:
	var player := sfx.make_player(SidChip.new(8000.0))
	var frames: Array[PackedInt32Array] = []
	for f in sfx.frame_count():
		player.tick()
		frames.append(player.regs.duplicate())
	return frames


## Player data for a song.
static func song_bytes(song: SidSong) -> PackedByteArray:
	var rec := record_song(song)
	var out := PackedByteArray("SIF".to_ascii_buffer())
	out.append(1)
	out.append_array([0, 0])
	var stream := RegStream.encode(rec["frames"], int(rec["loop_frame"]), out.size(), PackedInt32Array(range(REGS)))
	out.append_array(stream["bytes"])
	if int(rec["loop_frame"]) >= 0:
		out.encode_u16(4, int(stream["loop_at"]))
		out.append(RegStream.LOOP)
	else:
		out.append(RegStream.END)
	return out


## Player data for a set of sound effects.
static func sfx_bytes(sounds: Array) -> PackedByteArray:
	var out := PackedByteArray("SIS".to_ascii_buffer())
	out.append(1)
	out.append(sounds.size())
	out.resize(5 + sounds.size() * 2)
	for i in sounds.size():
		out.encode_u16(5 + i * 2, out.size())
		var stream := RegStream.encode(record_sfx(sounds[i]), -1, out.size(), SFX_REGS)
		out.append_array(stream["bytes"])
		out.append(RegStream.END)
	return out


static func decode_song(data: PackedByteArray, count: int) -> Array[PackedInt32Array]:
	var state := RegStream.Reader.new(data, 6, data.decode_u16(4), REGS)
	var out: Array[PackedInt32Array] = []
	for f in count:
		state.step()
		out.append(state.regs.duplicate())
	return out


static func decode_sfx(data: PackedByteArray, index: int) -> Array[PackedInt32Array]:
	var state := RegStream.Reader.new(data, data.decode_u16(5 + index * 2), 0, REGS)
	var out: Array[PackedInt32Array] = []
	while true:
		state.step()
		if not state.on:
			break
		out.append(state.regs.duplicate())
	return out


static func player_binary() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(PLAYER_BINARY)


static func player_source() -> String:
	return FileAccess.get_file_as_string(PLAYER_SOURCE)


static func player_config() -> String:
	return FileAccess.get_file_as_string(PLAYER_CONFIG)


## A PSID file: the player at $1000 with the song right after it. Init is
## $1000 and play $1003, called 50 times a second.
static func psid_bytes(song: SidSong, data := PackedByteArray()) -> PackedByteArray:
	if data.is_empty():
		data = song_bytes(song)
	var player := player_binary()
	var song_at := LOAD_ADDRESS + player.size()
	player.encode_u16(SONG_POINTER, song_at)
	var header := PackedByteArray()
	header.resize(0x7C)
	header.fill(0)
	var magic := "PSID".to_ascii_buffer()
	for i in 4:
		header[i] = magic[i]
	_be16(header, 0x04, 2)
	_be16(header, 0x06, 0x7C)
	_be16(header, 0x08, 0)
	_be16(header, 0x0A, LOAD_ADDRESS)
	_be16(header, 0x0C, LOAD_ADDRESS + 3)
	_be16(header, 0x0E, 1)
	_be16(header, 0x10, 1)
	_text(header, 0x16, song.title)
	_text(header, 0x36, "Chiptune Forge")
	_text(header, 0x56, "Made with Chiptune Forge")
	# PAL, 6581.
	_be16(header, 0x76, 0x0014)
	var out := header
	out.append_array([LOAD_ADDRESS & 0xFF, LOAD_ADDRESS >> 8])
	out.append_array(player)
	out.append_array(data)
	assert(LOAD_ADDRESS + player.size() + data.size() <= 0xA000, "the song must end before BASIC's ROM")
	return out


static func _be16(buf: PackedByteArray, at: int, value: int) -> void:
	buf[at] = (value >> 8) & 0xFF
	buf[at + 1] = value & 0xFF


static func _text(buf: PackedByteArray, at: int, text: String) -> void:
	var bytes := text.to_ascii_buffer()
	for i in mini(bytes.size(), 31):
		buf[at + i] = bytes[i]


## The example program: a .prg that plays the song (and its sound effects
## every two seconds, if there are any).
static func example_source(title: String, sfx_count := 0) -> String:
	var lines := PackedStringArray([
		"; %s for the Commodore 64: a program that plays the song%s." % [title, " and its sound effects" if sfx_count > 0 else ""],
		"; Build with ca65 (cc65): see the Makefile.",
		"",
		".segment \"LOADADDR\"",
		"\t.word $0801",
		"",
		".segment \"CODE\"",
		"\t; 10 SYS 2061",
		"\t.word basic_end, 10",
		"\t.byte $9e, \"2061\", 0",
		"basic_end:",
		"\t.word 0",
		"start:",
		"\tsei",
		"\tlda #<song",
		"\tsta $100c",
		"\tlda #>song",
		"\tsta $100d",
		"\tjsr $1000",
	])
	if sfx_count > 0:
		lines.append_array([
			"\tlda #<sounds",
			"\tldx #>sounds",
			"\tjsr $1006",
		])
	lines.append_array([
		"loop:",
		"\t; Wait for the bottom of the screen, once a frame.",
		"wait_top:",
		"\tlda $d012",
		"\tcmp #250",
		"\tbne wait_top",
		"\tjsr $1003",
		"wait_line:",
		"\tlda $d012",
		"\tcmp #250",
		"\tbeq wait_line",
	])
	if sfx_count > 0:
		lines.append_array([
			"\t; Every two seconds, the next sound effect.",
			"\tinc frames",
			"\tlda frames",
			"\tcmp #100",
			"\tbne loop",
			"\tlda #0",
			"\tsta frames",
			"\tlda next",
			"\tjsr $1009",
			"\tinc next",
			"\tlda next",
			"\tcmp #%d" % sfx_count,
			"\tbne loop",
			"\tlda #0",
			"\tsta next",
		])
	lines.append("\tjmp loop")
	if sfx_count > 0:
		lines.append_array(["frames:\t.byte 0", "next:\t.byte 0"])
	lines.append_array([
		"",
		".segment \"PLAYER\"",
		"\t.incbin \"sid_player.bin\"",
		"song:",
		"\t.incbin \"song.bin\"",
	])
	if sfx_count > 0:
		lines.append_array(["sounds:", "\t.incbin \"sfx.bin\""])
	return "\n".join(lines) + "\n"


static func example_config() -> String:
	return "\n".join(PackedStringArray([
		"# ld65 configuration for main.s: BASIC start at $0801, the player at $1000.",
		"MEMORY {",
		"    LOADADDR: start = $07FF, size = 2, file = %O;",
		"    MAIN: start = $0801, size = $07FF, file = %O, fill = yes;",
		"    PLAYER: start = $1000, size = $9000, file = %O;",
		"}",
		"SEGMENTS {",
		"    LOADADDR: load = LOADADDR, type = ro;",
		"    CODE: load = MAIN, type = rw;",
		"    PLAYER: load = PLAYER, type = rw;",
		"}",
	])) + "\n"


static func makefile(name: String) -> String:
	return "\n".join(PackedStringArray([
		"# Builds %s.prg with ca65 and ld65 (cc65, https://cc65.github.io/)," % name,
		"# and sid_player.bin from its source.",
		"CA65 ?= ca65",
		"LD65 ?= ld65",
		"",
		"%s.prg: main.s main.cfg sid_player.bin $(wildcard *.bin)" % name,
		"\t$(CA65) main.s -o main.o",
		"\t$(LD65) -C main.cfg main.o -o %s.prg" % name,
		"",
		"player: sid_player.s sid_player.cfg",
		"\t$(CA65) sid_player.s -o sid_player.o",
		"\t$(LD65) -C sid_player.cfg sid_player.o -o sid_player.bin",
		"",
		"clean:",
		"\trm -f *.o *.prg",
	])) + "\n"


static func song_readme(name: String, sid: SidSong) -> String:
	return "\n".join(PackedStringArray([
		"%s for the Commodore 64 (SID)" % sid.title,
		"",
		"%s.sid is a PSID file: play it in any SID player (sidplayfp, VICE's" % name,
		"VSID, ...) or load it in your game like other SID music, with the player",
		"at $1000: init at $1000, then call $1003 once per frame (PAL, 50 Hz).",
		"",
		"song.bin is the song alone for Chiptune Forge's player, sid_player.s",
		"(MIT-licensed 6502 assembly for ca65; sid_player.bin is it assembled at",
		"$1000). Put the song's address at $100C/$100D before calling $1000.",
		"main.s is an example program that does this; run make (with cc65",
		"installed) to build %s.prg." % name,
		"",
		"Voice 1 plays the lead, voice 2 the accompaniment and the drums, voice 3",
		"the bass. Sound effects from a Chiptune Forge sound kit play on voice 2:",
		"see that kit's README. The player uses zero page $FB and $FC.",
		"",
		"%.1f KB of song data. The data format is described in sid_player.s." % (song_bytes(sid).size() / 1024.0),
	])) + "\n"


static func sfx_readme(kit: String, sounds: Array) -> String:
	var lines := PackedStringArray([
		"%s: sound effects for the Commodore 64 (SID)" % kit,
		"",
		"sfx.bin holds the sounds for Chiptune Forge's player, sid_player.s (MIT,",
		"6502; sid_player.bin is it assembled at $1000). They play on voice 2 over",
		"a Chiptune Forge song, which gets the voice back when a sound ends. After",
		"starting the song ($1000), tell the player where the sounds are:",
		"",
		"  lda #<sounds",
		"  ldx #>sounds",
		"  jsr $1006",
		"",
		"then play one by its number:",
		"",
		"  lda #0",
		"  jsr $1009",
		"",
		"Sounds:",
	])
	for i in sounds.size():
		var sfx: SidSfx = sounds[i]
		lines.append("  %d  %s  (%.2f s)" % [i, sfx.name, sfx.frame_count() / SidSong.FRAME_HZ])
	return "\n".join(lines) + "\n"
