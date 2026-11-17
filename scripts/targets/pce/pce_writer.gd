class_name PceWriter
extends RefCounted
## Writes [PceSong]s and [PceSfx] sounds as data for our C player
## (assets/pce/pce_player.c, for HuCC), and the files of an example
## project around it. The data format is described at the top of
## pce_player.c.

const PLAYER_PATH := "res://assets/pce/pce_player.c"
const NOTE_MAX_FRAMES := 255
const CMD_INSTRUMENT := 128
const CMD_VOLUME := 192
const CMD_ARP := 193
const CMD_OFF := 194
const CMD_HOLD := 195
const CMD_LOOP := 254
const CMD_END := 255
const HEADER := 42


## The song as player data.
static func song_bytes(pce: PceSong) -> PackedByteArray:
	var out := _Blob.new()
	out.begin("PCE", PceSong.CHANNEL_COUNT, pce.waves, pce.instruments, pce.arpeggios, HEADER)
	for c in PceSong.CHANNEL_COUNT:
		out.data[36 + c] = pce.balances[c]
	var loops := PackedInt32Array()
	for c in PceSong.CHANNEL_COUNT:
		out.set_word(12 + c * 2, out.data.size())
		loops.append(_stream(out, pce, c))
	for c in PceSong.CHANNEL_COUNT:
		out.set_word(24 + c * 2, loops[c])
	return out.finish()


## Sound effects as player data, one stream each.
static func sfx_bytes(sounds: Array) -> PackedByteArray:
	var waves: Array = []
	var names: Array = []
	var instruments: Array = []
	for sfx: PceSfx in sounds:
		var inst := sfx.instrument()
		var w := names.find(sfx.wave)
		if w < 0:
			names.append(sfx.wave)
			waves.append(PceSong.make_wave(sfx.wave))
			w = waves.size() - 1
		inst["wave"] = w
		instruments.append(inst)
	var out := _Blob.new()
	out.begin("PCS", sounds.size(), waves, instruments, [], 12 + sounds.size() * 2)
	for i in sounds.size():
		var sfx: PceSfx = sounds[i]
		out.set_word(12 + i * 2, out.data.size())
		out.data.append_array([CMD_INSTRUMENT + i, CMD_VOLUME, 15])
		var frames := mini(sfx.frame_count(), NOTE_MAX_FRAMES)
		out.data.append_array([sfx.note, maxi(frames, 1), CMD_END])
	return out.finish()


## Writes channel [param c]'s stream. Returns its loop offset (0 for none).
static func _stream(out: _Blob, pce: PceSong, c: int) -> int:
	var total := pce.total_frames()
	var loop_frame := pce.frames_before(pce.loop_start_row) if pce.looping and pce.loop_start_row < pce.row_count else -1
	# Segments [frame, kind, note dict]: what the channel does from that frame.
	var segments: Array = [[0, "off", {}]]
	var list: Array = pce.notes[c]
	for k in list.size():
		var n: Dictionary = list[k]
		var start := int(n["row"])
		var next_start := int(list[k + 1]["row"]) if k + 1 < list.size() else pce.row_count
		var end := mini(start + int(n["length"]), next_start)
		segments.append([pce.frames_before(start), "note", n])
		if end < next_start and end < pce.row_count:
			segments.append([pce.frames_before(end), "off", {}])
	if loop_frame > 0:
		for i in segments.size():
			var s: Array = segments[i]
			var until: int = segments[i + 1][0] if i + 1 < segments.size() else total
			if int(s[0]) < loop_frame and until > loop_frame:
				segments.insert(i + 1, [loop_frame, "hold" if s[1] == "note" else "off", {}])
				break
	# Drop segments that take no time (two events on one frame).
	var timed: Array = []
	for i in segments.size():
		var until: int = segments[i + 1][0] if i + 1 < segments.size() else total
		if until > int(segments[i][0]):
			timed.append([segments[i][0], segments[i][1], segments[i][2], until - int(segments[i][0])])
	var state := {"instrument": -1, "volume": -1, "arp": -2}
	var loop_offset := 0
	for seg in timed:
		if int(seg[0]) == loop_frame:
			loop_offset = out.data.size()
			state = {"instrument": -1, "volume": -1, "arp": -2}
		var frames: int = seg[3]
		var first := mini(frames, NOTE_MAX_FRAMES)
		match seg[1]:
			"note":
				var n: Dictionary = seg[2]
				var inst := int(n["instrument"])
				if inst != state["instrument"]:
					out.data.append(CMD_INSTRUMENT + inst)
					state["instrument"] = inst
				var vol := int(n.get("volume", 15))
				if vol != state["volume"]:
					out.data.append_array([CMD_VOLUME, vol])
					state["volume"] = vol
				var arp := int(n.get("arp", -1))
				if arp != state["arp"]:
					out.data.append_array([CMD_ARP, arp if arp >= 0 else 255])
					state["arp"] = arp
				out.data.append_array([clampi(int(n["note"]), 1, 127), first])
			"hold":
				out.data.append_array([CMD_HOLD, first])
			_:
				out.data.append_array([CMD_OFF, first])
		frames -= first
		while frames > 0:
			var more := mini(frames, NOTE_MAX_FRAMES)
			out.data.append_array([CMD_OFF if seg[1] == "off" else CMD_HOLD, more])
			frames -= more
	out.data.append(CMD_LOOP if loop_frame >= 0 else CMD_END)
	return loop_offset if loop_frame >= 0 else 0


## The player's source, with its frequency and volume tables filled in.
static func player_c() -> String:
	var text := FileAccess.get_file_as_string(PLAYER_PATH)
	var periods := PackedStringArray()
	for n in 128:
		periods.append(str(PceSong.note_period(n)))
	var volumes := PackedStringArray()
	for level in 16:
		volumes.append(str(PceSong.volume_of_level(level)))
	var rows := PackedStringArray()
	for i in range(0, 128, 16):
		rows.append(", ".join(periods.slice(i, i + 16)))
	text = text.replace("PCE_PERIOD_TABLE", ",\n\t".join(rows))
	text = text.replace("PCE_VOLUME_TABLE", ", ".join(volumes))
	return text


## A main.c that plays the song (and with [param sfx_count] sounds, plays
## each in turn every two seconds).
static func main_c(title: String, sfx_count := 0) -> String:
	var lines := PackedStringArray([
		"// %s: plays the song with Chiptune Forge's player." % title.replace("\n", " "),
		"// Made with Chiptune Forge. Build with HuCC: hucc main.c",
		"#include \"huc.h\"",
		"",
		"#incbin(pce_song, \"song.bin\");",
	])
	if sfx_count > 0:
		lines.append_array(["#incbin(pce_sfx, \"sfx.bin\");", "#define PCE_SFX"])
	lines.append_array([
		"#include \"pce_player.c\"",
		"",
		"main()",
		"{",
		"    unsigned int frames;",
		"    unsigned char next;",
		"    frames = 0;",
		"    next = 0;",
		"    pce_start();",
		"    for (;;) {",
		"        vsync();",
		"        pce_frame();",
	])
	if sfx_count > 0:
		lines.append_array([
			"        ++frames;",
			"        if (frames >= 120) {",
			"            frames = 0;",
			"            pce_sfx_play(next);",
			"            ++next;",
			"            if (next >= %d)" % sfx_count,
			"                next = 0;",
			"        }",
		])
	lines.append_array(["    }", "}"])
	return "\n".join(lines) + "\n"


static func makefile(rom_name: String) -> String:
	return "\n".join(PackedStringArray([
		"# Builds %s.pce with HuCC (https://github.com/pce-devel/huc)." % rom_name,
		"# Put HuCC's bin folder on your PATH and set PCE_INCLUDE to its include/hucc folder.",
		"HUCC ?= hucc",
		"",
		"%s.pce: main.c pce_player.c $(wildcard *.bin)" % rom_name,
		"\t$(HUCC) -O2 -fno-recursive main.c",
		"\tmv main.pce %s.pce" % rom_name,
		"",
		"clean:",
		"\trm -f *.pce *.s *.sym *.lst",
	])) + "\n"


## The README for a song's pce/ folder.
static func song_readme(rom_name: String, pce: PceSong) -> String:
	return "\n".join(PackedStringArray([
		"%s for the PC Engine / TurboGrafx-16" % pce.title,
		"",
		"song.bin is the song for Chiptune Forge's player, pce_player.c, which is",
		"MIT-licensed C for HuCC (https://github.com/pce-devel/huc). main.c plays",
		"the song; build it with make (HuCC's bin folder on your PATH), which",
		"makes %s.pce." % rom_name,
		"",
		"In your own program, include the song and the player, then call",
		"pce_start() once and pce_frame() once per frame, after vsync():",
		"",
		"  #incbin(pce_song, \"song.bin\");",
		"  #include \"pce_player.c\"",
		"",
		"The player uses all six channels. Sound effects from a Chiptune Forge",
		"sound kit play on channel 5 (the pad), which gets the music back when",
		"they end: see that kit's README.",
		"",
		"%.1f KB of song data. The data format is described in pce_player.c." % (song_bytes(pce).size() / 1024.0),
	])) + "\n"


## The README for a sound kit's pce/ folder.
static func sfx_readme(kit: String, sounds: Array) -> String:
	var lines := PackedStringArray([
		"%s: sound effects for the PC Engine / TurboGrafx-16" % kit,
		"",
		"sfx.bin holds the sounds for Chiptune Forge's player, pce_player.c (MIT,",
		"for HuCC). They play on channel 5, over a Chiptune Forge song, which gets",
		"the channel back when a sound ends. Include them as pce_sfx and define",
		"PCE_SFX before the player:",
		"",
		"  #incbin(pce_song, \"song.bin\");",
		"  #incbin(pce_sfx, \"sfx.bin\");",
		"  #define PCE_SFX",
		"  #include \"pce_player.c\"",
		"",
		"then play one by its number:",
		"",
		"  pce_sfx_play(0);",
		"",
		"Sounds:",
	])
	for i in sounds.size():
		var sfx: PceSfx = sounds[i]
		lines.append("  %d  %s  (%.2f s)" % [i, sfx.name, sfx.frame_count() / PceSong.FRAME_HZ])
	return "\n".join(lines) + "\n"


## Player data built up with the header written first.
class _Blob:
	extends RefCounted

	var data := PackedByteArray()

	func begin(magic: String, streams: int, waves: Array, instruments: Array, arps: Array, header: int) -> void:
		data = magic.to_ascii_buffer()
		data.append(1)
		data.append(streams)
		data.append(waves.size())
		data.resize(header)
		data.fill(0)
		var m := magic.to_ascii_buffer()
		for i in 3:
			data[i] = m[i]
		data[3] = 1
		data[4] = streams
		data[5] = waves.size()
		set_word(6, data.size())
		for w in waves:
			for v in w:
				data.append(clampi(int(v), 0, 31))
		var envs := {}
		var records := PackedByteArray()
		for inst: Dictionary in instruments:
			var flags := 1 if bool(inst.get("noise", false)) else 0
			records.append_array([int(inst.get("wave", 0)), flags, 0, 0, 0, 0, 0, 0])
		var inst_at := data.size()
		set_word(8, inst_at)
		data.append_array(records)
		var arp_at := data.size()
		set_word(10, arp_at)
		data.resize(data.size() + arps.size() * 2)
		for i in instruments.size():
			var inst: Dictionary = instruments[i]
			for k in 3:
				var key: String = ["volume", "arp", "pitch"][k]
				var at := envelope(envs, inst.get(key, []), int(inst.get(key + "_loop", -1)))
				data[inst_at + i * 8 + 2 + k * 2] = at & 0xFF
				data[inst_at + i * 8 + 3 + k * 2] = at >> 8
		for i in arps.size():
			var arp: Dictionary = arps[i]
			set_word(arp_at + i * 2, envelope(envs, arp.get("values", []), int(arp.get("loop", -1))))

	## The offset of an envelope, written the first time it is needed (0 for
	## an empty one).
	func envelope(envs: Dictionary, values: Array, loop: int) -> int:
		if values.is_empty():
			return 0
		var bytes := PackedByteArray([mini(values.size(), 255), loop if loop >= 0 and loop < mini(values.size(), 255) else 255])
		for i in mini(values.size(), 255):
			bytes.append(clampi(int(values[i]), -128, 127) & 0xFF)
		var key := bytes.hex_encode()
		if not envs.has(key):
			envs[key] = data.size()
			data.append_array(bytes)
		return envs[key]

	func set_word(at: int, value: int) -> void:
		data[at] = value & 0xFF
		data[at + 1] = (value >> 8) & 0xFF

	func finish() -> PackedByteArray:
		assert(data.size() <= 0xFFFF, "the player's data must fit in 64 KB")
		return data
