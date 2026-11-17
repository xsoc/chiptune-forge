class_name AyWriter
extends RefCounted
## Writes MSX and ZX Spectrum 128 songs and sound effects: data for our Z80
## player (assets/msx/ay_player.asm), example programs that build an MSX
## cartridge and a Spectrum tape with Pasmo, and VGM files.
##
## The data is the chip's registers frame by frame: each frame writes the
## registers that changed, and stretches that repeat earlier ones play them
## again with a call command (the format is described in ay_player.asm).
## [AyPlayer] sets the registers, so recording it gives the data.

const PLAYER_PATH := "res://assets/msx/ay_player.asm"
const REGS := AyPlayer.PLAYED_REGISTERS
const WAIT := 0x80
const CALL := 0xC0
const LOOP := 0xFE
const END := 0xFF
const MAX_WAIT := 63
## The two machines and their chip clocks.
const MACHINES := {"msx": AyPsg.CLOCK_MSX, "zx": AyPsg.CLOCK_ZX}


## Plays [param song] once through. Returns {frames: the registers after
## each frame, loop_frame: the frame the loop starts on, or -1}.
static func record_song(song: AySong, clock := AyPsg.CLOCK_MSX) -> Dictionary:
	var player := AyPlayer.new(song, AyPsg.new(8000.0, clock))
	player.clock = clock
	player.start(0)
	var total := song.frames_before(song.row_count)
	var frames: Array[PackedInt32Array] = []
	for f in total:
		player.tick()
		frames.append(player.regs.duplicate())
	return {"frames": frames, "loop_frame": song.frames_before(song.loop_start_row) if song.looping else -1}


## The registers after each frame of a sound effect.
static func record_sfx(sfx: AySfx, clock := AyPsg.CLOCK_MSX) -> Array[PackedInt32Array]:
	var player := sfx.make_player(AyPsg.new(8000.0, clock))
	player.clock = clock
	player.start(0)
	var frames: Array[PackedInt32Array] = []
	for f in sfx.frame_count():
		player.tick()
		frames.append(player.regs.duplicate())
	return frames


## Player data for a song.
static func song_bytes(song: AySong, clock := AyPsg.CLOCK_MSX) -> PackedByteArray:
	var rec := record_song(song, clock)
	var out := PackedByteArray("AYF".to_ascii_buffer())
	out.append(1)
	out.append_array([0, 0])
	var stream := encode(rec["frames"], int(rec["loop_frame"]), out.size())
	out.append_array(stream["bytes"])
	if int(rec["loop_frame"]) >= 0:
		out.encode_u16(4, int(stream["loop_at"]))
		out.append(LOOP)
	else:
		out.append(END)
	assert(out.size() <= 0xFFFF, "the player's data must fit in 64 KB")
	return out


## Player data for a set of sound effects.
static func sfx_bytes(sounds: Array, clock := AyPsg.CLOCK_MSX) -> PackedByteArray:
	var out := PackedByteArray("AYS".to_ascii_buffer())
	out.append(1)
	out.append(sounds.size())
	out.resize(5 + sounds.size() * 2)
	for i in sounds.size():
		out.encode_u16(5 + i * 2, out.size())
		var stream := encode(record_sfx(sounds[i], clock), -1, out.size())
		out.append_array(stream["bytes"])
		out.append(END)
	return out


## Encodes recorded frames as a stream that will sit at [param base] in the
## data. Returns {bytes, loop_at: where the loop frame starts, from the
## start of the data}.
static func encode(frames: Array, loop_frame: int, base: int) -> Dictionary:
	# One token per frame that writes registers (or starts the loop), with
	# the empty frames after it folded into its wait.
	var tokens: Array[PackedByteArray] = []
	var token_frame := PackedInt32Array()
	var prev := PackedInt32Array()
	for f in frames.size():
		var regs: PackedInt32Array = frames[f]
		var bytes := PackedByteArray()
		for r in REGS:
			if f == 0 or f == loop_frame or regs[r] != prev[r]:
				bytes.append(r)
				bytes.append(regs[r] & 0xFF)
		prev = regs
		var last := tokens.size() - 1
		if bytes.is_empty() and f != loop_frame and last >= 0:
			var t := tokens[last]
			var wait := t[t.size() - 1] & 0x3F
			if wait < MAX_WAIT:
				t[t.size() - 1] = WAIT | (wait + 1)
				tokens[last] = t
				continue
		bytes.append(WAIT)
		tokens.append(bytes)
		token_frame.append(f)
	var loop_token := token_frame.find(loop_frame) if loop_frame >= 0 else -1
	# Repeats of earlier stretches become calls. A call may only point at
	# tokens written out as they are, one after another, and never runs
	# across the loop point.
	var out := PackedByteArray()
	var literal_at := PackedInt32Array()
	literal_at.resize(tokens.size())
	literal_at.fill(-1)
	var seen := {}
	var loop_at := -1
	var i := 0
	while i < tokens.size():
		if i == loop_token:
			loop_at = base + out.size()
		var key := tokens[i].hex_encode()
		var best_len := 0
		var best_bytes := 0
		var best_from := -1
		var candidates: Array = seen.get(key, [])
		for k in range(candidates.size() - 1, maxi(candidates.size() - 64, 0) - 1, -1):
			var j: int = candidates[k]
			var n := 0
			var bytes := 0
			while i + n < tokens.size() and j + n < i:
				if n > 0 and i + n == loop_token:
					break
				if literal_at[j + n] < 0 or tokens[j + n] != tokens[i + n]:
					break
				if n > 0 and literal_at[j + n] != literal_at[j + n - 1] + tokens[j + n - 1].size():
					break
				bytes += tokens[i + n].size()
				n += 1
			if bytes > best_bytes:
				best_bytes = bytes
				best_len = n
				best_from = j
		if best_bytes > 6:
			var at := base + literal_at[best_from]
			out.append_array([CALL, at & 0xFF, at >> 8, best_bytes & 0xFF, best_bytes >> 8])
			i += best_len
			continue
		literal_at[i] = out.size()
		out.append_array(tokens[i])
		if not seen.has(key):
			seen[key] = []
		seen[key].append(i)
		i += 1
	return {"bytes": out, "loop_at": loop_at}


## Plays a song's data the way the Z80 player does, for [param count]
## frames. Returns the registers after each frame.
static func decode_song(data: PackedByteArray, count: int) -> Array[PackedInt32Array]:
	var state := _Stream.new(data, 6, data.decode_u16(4))
	var out: Array[PackedInt32Array] = []
	for f in count:
		state.step()
		out.append(state.regs.duplicate())
	return out


## Plays sound effect [param index] from sound data the way the Z80 player
## does. Returns the registers after each frame, until it ends.
static func decode_sfx(data: PackedByteArray, index: int) -> Array[PackedInt32Array]:
	var state := _Stream.new(data, data.decode_u16(5 + index * 2), 0)
	var out: Array[PackedInt32Array] = []
	while true:
		state.step()
		if not state.on:
			break
		out.append(state.regs.duplicate())
	return out


## A VGM file of the song for an AY-3-8910 at the MSX clock, at 50 frames a
## second.
static func vgm_bytes(song: AySong) -> PackedByteArray:
	var rec := record_song(song, AyPsg.CLOCK_MSX)
	var frames: Array = rec["frames"]
	var loop_frame := int(rec["loop_frame"])
	var data := PackedByteArray()
	var loop_offset := -1
	var prev := PackedInt32Array()
	for f in frames.size():
		if f == loop_frame:
			loop_offset = data.size()
		var regs: PackedInt32Array = frames[f]
		for r in REGS:
			if f == 0 or f == loop_frame or regs[r] != prev[r]:
				data.append_array([0xA0, r, regs[r] & 0xFF])
		prev = regs
		data.append(0x63)
	data.append(0x66)
	var samples_per_frame := 882
	var header := PackedByteArray()
	header.resize(0x100)
	header.fill(0)
	header.encode_u32(0x00, 0x206D6756)
	header.encode_u32(0x04, 0x100 + data.size() - 4)
	header.encode_u32(0x08, 0x151)
	header.encode_u32(0x18, frames.size() * samples_per_frame)
	if loop_offset >= 0:
		header.encode_u32(0x1C, 0x100 + loop_offset - 0x1C)
		header.encode_u32(0x20, (frames.size() - loop_frame) * samples_per_frame)
	header.encode_u32(0x24, 50)
	header.encode_u32(0x34, 0x100 - 0x34)
	header.encode_u32(0x74, int(AyPsg.CLOCK_MSX))
	header[0x78] = 0x00
	header.append_array(data)
	return header


static func player_asm() -> String:
	return FileAccess.get_file_as_string(PLAYER_PATH)


## The example MSX cartridge program.
static func msx_main(title: String, sfx_count := 0) -> String:
	var lines := PackedStringArray([
		"; %s for the MSX: a cartridge that plays the song%s." % [title, " and its sound effects" if sfx_count > 0 else ""],
		"; Build with Pasmo: pasmo msx_main.asm game.rom",
		"AY_MSX equ 1",
		"AY_ZX equ 0",
		"AY_RAM equ $E000",
		"frames equ $E040",
		"next equ $E041",
		"",
		"\torg $4000",
		"\tdb \"AB\"",
		"\tdw start",
		"\tds 12",
		"start:",
		"\tdi",
		"\tcall select_page2",
		"\tld hl,song",
		"\tcall ay_init",
	])
	lines.append_array(_example_loop(sfx_count, "ay_interrupt"))
	lines.append_array([
		"",
		"; Puts this cartridge's slot in page 2 too ($8000-$BFFF), for a song",
		"; longer than 16 KB.",
		"select_page2:",
		"\tcall $0138\t\t; RSLREG",
		"\trrca",
		"\trrca",
		"\tand 3",
		"\tld c,a",
		"\tld b,0",
		"\tld hl,$FCC1\t\t; EXPTBL",
		"\tadd hl,bc",
		"\tld a,(hl)",
		"\tand $80",
		"\tor c",
		"\tld c,a",
		"\tinc hl",
		"\tinc hl",
		"\tinc hl",
		"\tinc hl",
		"\tld a,(hl)\t\t; SLTTBL",
		"\trrca",
		"\trrca",
		"\tand $0C",
		"\tor c",
		"\tld h,$80",
		"\tjp $0024\t\t; ENASLT",
		"",
		"\tinclude \"ay_player.asm\"",
		"song:",
		"\tincbin \"song_msx.bin\"",
	])
	if sfx_count > 0:
		lines.append_array(["sounds:", "\tincbin \"sfx_msx.bin\""])
	lines.append_array([
		"",
		"; Pad the cartridge to 16 or 32 KB.",
		"\tif $ <= $8000",
		"\tds $8000 - $",
		"\telse",
		"\tds $C000 - $",
		"\tendif",
	])
	return "\n".join(lines) + "\n"


## The example ZX Spectrum 128 program.
static func zx_main(title: String, sfx_count := 0) -> String:
	var lines := PackedStringArray([
		"; %s for the ZX Spectrum 128: a tape that plays the song%s." % [title, " and its sound effects" if sfx_count > 0 else ""],
		"; Build with Pasmo: pasmo --tapbas zx_main.asm game.tap",
		"AY_MSX equ 0",
		"AY_ZX equ 1",
		"AY_RAM equ $FE00",
		"frames equ $FE40",
		"next equ $FE41",
		"",
		"\torg $8000",
		"start:",
		"\tdi",
		"\tld hl,song",
		"\tcall ay_init",
	])
	lines.append_array(_example_loop(sfx_count, "ay_frame"))
	lines.append_array([
		"",
		"\tinclude \"ay_player.asm\"",
		"song:",
		"\tincbin \"song_zx.bin\"",
	])
	if sfx_count > 0:
		lines.append_array(["sounds:", "\tincbin \"sfx_zx.bin\""])
	lines.append("\tend start")
	return "\n".join(lines) + "\n"


static func _example_loop(sfx_count: int, frame_call: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if sfx_count > 0:
		lines.append_array([
			"\tld hl,sounds",
			"\tcall ay_sfx_init",
			"\txor a",
			"\tld (frames),a",
			"\tld (next),a",
		])
	lines.append_array([
		"loop:",
		"\tei",
		"\thalt",
		"\tcall %s" % frame_call,
	])
	if sfx_count > 0:
		lines.append_array([
			"\t; Every two seconds, the next sound effect.",
			"\tld a,(frames)",
			"\tinc a",
			"\tld (frames),a",
			"\tcp 100",
			"\tjr nz,loop",
			"\txor a",
			"\tld (frames),a",
			"\tld a,(next)",
			"\tcall ay_sfx_play",
			"\tld a,(next)",
			"\tinc a",
			"\tcp %d" % sfx_count,
			"\tjr nz,next_ok",
			"\txor a",
			"next_ok:",
			"\tld (next),a",
		])
	lines.append("\tjr loop")
	return lines


static func makefile(rom_name: String) -> String:
	return "\n".join(PackedStringArray([
		"# Builds %s.rom (MSX cartridge) and %s.tap (ZX Spectrum 128 tape)" % [rom_name, rom_name],
		"# with Pasmo (https://pasmo.speccy.org/, or your system's pasmo package).",
		"PASMO ?= pasmo",
		"",
		"all: %s.rom %s.tap" % [rom_name, rom_name],
		"",
		"%s.rom: msx_main.asm ay_player.asm $(wildcard *_msx.bin)" % rom_name,
		"\t$(PASMO) msx_main.asm %s.rom" % rom_name,
		"",
		"%s.tap: zx_main.asm ay_player.asm $(wildcard *_zx.bin)" % rom_name,
		"\t$(PASMO) --tapbas zx_main.asm %s.tap" % rom_name,
		"",
		"clean:",
		"\trm -f *.rom *.tap",
	])) + "\n"


## The README for a song's msx/ folder.
static func song_readme(rom_name: String, ay: AySong) -> String:
	return "\n".join(PackedStringArray([
		"%s for the MSX and ZX Spectrum 128 (AY-3-8910)" % ay.title,
		"",
		"song_msx.bin and song_zx.bin are the song for Chiptune Forge's player,",
		"ay_player.asm, which is MIT-licensed Z80 assembly (Pasmo syntax). The two",
		"differ only in their tone periods: the chips run at slightly different",
		"clocks. msx_main.asm builds an MSX cartridge and zx_main.asm a Spectrum",
		"128 tape that play the song; run make (with Pasmo installed) to get",
		"%s.rom and %s.tap." % [rom_name, rom_name],
		"",
		"In your own program, define AY_MSX and AY_ZX (1 for your machine, 0 for",
		"the other) and AY_RAM (64 bytes of RAM for the player), include",
		"ay_player.asm, then:",
		"",
		"  ld hl,song       ; the song data",
		"  call ay_init",
		"  ...and once per frame interrupt: call ay_interrupt",
		"",
		"The player runs at 50 frames a second; on a 60 Hz MSX ay_interrupt skips",
		"every sixth interrupt to keep the tempo. Channel A plays the lead, B the",
		"accompaniment and the drums, C the bass. Sound effects from a Chiptune",
		"Forge sound kit play on channel B: see that kit's README.",
		"",
		"song.vgm is the song as a VGM file, which most chiptune players play.",
		"",
		"%.1f KB of song data. The data format is described in ay_player.asm." % (song_bytes(ay).size() / 1024.0),
	])) + "\n"


## The README for a sound kit's msx/ folder.
static func sfx_readme(kit: String, sounds: Array) -> String:
	var lines := PackedStringArray([
		"%s: sound effects for the MSX and ZX Spectrum 128 (AY-3-8910)" % kit,
		"",
		"sfx_msx.bin and sfx_zx.bin hold the sounds for Chiptune Forge's player,",
		"ay_player.asm (MIT, Z80). They play on channel B over a Chiptune Forge",
		"song, which gets the channel back when a sound ends. After ay_init:",
		"",
		"  ld hl,sounds     ; the sound data",
		"  call ay_sfx_init",
		"",
		"then play one by its number:",
		"",
		"  ld a,0",
		"  call ay_sfx_play",
		"",
		"Sounds:",
	])
	for i in sounds.size():
		var sfx: AySfx = sounds[i]
		lines.append("  %d  %s  (%.2f s)" % [i, sfx.name, sfx.frame_count() / AySong.FRAME_HZ])
	return "\n".join(lines) + "\n"


## A stream as the Z80 player reads it.
class _Stream:
	extends RefCounted

	var data: PackedByteArray
	var pos := 0
	var wait := 0
	var ret := -1
	var end := 0
	var loop := 0
	var on := true
	var regs := PackedInt32Array()

	func _init(bytes: PackedByteArray, start: int, loop_at: int) -> void:
		data = bytes
		pos = start
		loop = loop_at
		regs.resize(REGS)
		regs[AyPsg.MIXER] = 0x3F

	func step() -> void:
		if not on:
			return
		if wait > 0:
			wait -= 1
			return
		while true:
			if ret >= 0 and pos == end:
				pos = ret
				ret = -1
			var b := data[pos]
			pos += 1
			if b < 0x80:
				regs[b] = data[pos]
				pos += 1
			elif b < CALL:
				wait = b & 0x3F
				return
			elif b == CALL:
				var at := data.decode_u16(pos)
				var length := data.decode_u16(pos + 2)
				ret = pos + 4
				pos = at
				end = at + length
			elif b == LOOP:
				pos = loop
			else:
				on = false
				return
