extends "res://tests/test_case.gd"


func _song(vibe := "happy", style := "platformer", seed_text := "42") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return SongGenerator.generate(s)


func _peak(out: PackedFloat32Array, from := 0, to := -1) -> float:
	var peak := 0.0
	for i in range(from, out.size() if to < 0 else to):
		peak = maxf(peak, absf(out[i]))
	return peak


func _crossings(out: PackedFloat32Array, from := 0) -> int:
	var count := 0
	for i in range(from + 1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			count += 1
	return count


func test_brr_round_trip() -> void:
	var pcm := PackedInt32Array()
	for i in 256:
		pcm.append(roundi(sin(TAU * i / 64.0) * 12000.0))
	var encoded := SnesBrr.encode(pcm, 0, 256)
	var data: PackedByteArray = encoded["data"]
	check_eq(data.size(), 16 * SnesBrr.BLOCK_BYTES, "16 blocks of 9 bytes")
	check_eq((data[0] >> 2) & 3, 0, "first block uses filter 0")
	check(data[data.size() - 9] & SnesBrr.FLAG_END, "end flag on the last block")
	for b in 16:
		check(data[b * 9] & SnesBrr.FLAG_LOOP, "loop flag on every block of a looped sample")
	var decoded := SnesBrr.decode(data, encoded["loop"], 1)
	var out: PackedInt32Array = decoded["pcm"]
	check_eq(out.size(), 512, "the sample, then the loop once more")
	check_eq(int(decoded["loop"]), 256, "loop starts after the first pass")
	# The first block must use filter 0, which is coarse; after it the
	# filters predict the wave closely.
	var error := 0
	for i in range(16, 256):
		error += absi(out[i] - pcm[i])
	check(error / 240 < 150, "decodes close to the original (mean error %d)" % (error / 240))
	var once := SnesBrr.encode(PackedInt32Array([1000, 2000, 3000]))
	check_eq((once["data"] as PackedByteArray).size(), 9, "a short one-shot pads to one block")
	check_eq(once["data"][0] & 3, SnesBrr.FLAG_END, "end without loop")


func test_stored_samples_match_the_encoder() -> void:
	# The full check runs in CI (tools/snes_samples.gd --check); these are
	# the quick ones.
	for name in ["pulse12", "square", "saw", "triangle", "bass_triangle", "hat"]:
		var stored := FileAccess.get_file_as_bytes(SnesSamples.BRR_DIR + name + ".brr")
		check_eq(stored, SnesSamples.encode(name)["data"], "%s.brr matches a fresh encoding" % name)
	for name in SnesSamples.RECIPES:
		var sample := SnesSamples.get_sample(name)
		check_eq(int(sample["loop_start"]) % 16, 0, "%s loop starts on a block" % name)
		check_eq(int(sample["loop_length"]) % 16, 0, "%s loop is whole blocks" % name)
		check(FileAccess.file_exists(SnesSamples.BRR_DIR + name + ".brr"), "%s.brr stored" % name)


func test_pitch_table() -> void:
	# A sample at 8363 Hz plays at that rate at note 60: 8363/32000 of 4096.
	check_eq(SnesSong.dsp_pitch(60 * 64), 1070, "C-5 at 8363 Hz")
	check_eq(SnesSong.dsp_pitch(72 * 64), 2141, "an octave up doubles it")
	check_eq(SnesSamples.pitch_base("square"), 1, "32-sample cycle at middle C: 8372 Hz")
	check_eq(SnesSamples.pitch_base("bass_square"), 769, "64-sample cycle: an octave up")
	var hz := SnesSong.dsp_pitch(69 * 64 + SnesSamples.pitch_base("square")) / 4096.0 * 32000.0 / 32.0
	check_near(hz, 440.0, 1.0, "A4 on a 32-sample wave")


func test_tempo() -> void:
	check_near(SnesSong.tick_hz(150), 8000.0 / 136.0, 0.0001, "SNESMod's timer")
	for bpm in [80.0, 100.0, 120.0, 128.0, 140.0, 174.0]:
		var t := SnesSong.choose_tempo(bpm, 4)
		check_near(float(t["bpm"]), bpm, bpm * 0.005, "%d BPM fits" % int(bpm))
		check(int(t["tempo"]) >= 32 and int(t["tempo"]) <= 255, "tempo in range")


func _player_song() -> SnesSong:
	var snes := SnesSong.new()
	snes.set_tempo(150, 4)
	snes.row_count = 8
	snes.looping = false
	snes.section_rows = [{"name": "A", "row": 0, "length": 8}]
	snes.samples = PackedStringArray(["square"])
	snes.instruments = [{"name": "Lead", "sample": 0, "fadeout": 0, "env": {"nodes": [[0, 64], [4, 32], [6, 0]], "sustain": 1}}]
	snes.notes[0] = [{"row": 0, "length": 3, "note": 69, "instrument": 0, "volume": 64, "arp": -1}]
	return snes


func test_envelope_nodes() -> void:
	var nodes := SnesPlayer.envelope_nodes({"env": {"nodes": [[0, 64], [4, 32], [6, 0]], "sustain": 1}})
	# smconv rounds (dy * 256 + duration / 2) / duration toward zero.
	check_eq(nodes, [[64, 4, -2047], [32, 2, -4095], [0, 0, 0]], "smconv's durations and steps")


func test_player_follows_snesmod() -> void:
	var snes := _player_song()
	var rows := snes.rows()
	check_eq(int(rows[0][0]["note"]), 69, "note on row 0")
	check_eq(int(rows[0][0]["instrument"]), 1, "with its instrument")
	check_eq(int(rows[3][0]["note"]), SnesSong.NOTE_OFF, "note off where it ends")
	check(rows[3][0]["instrument"] == 0, "no instrument on the note off (it would restart the envelope)")
	var dsp := SnesDsp.new(32000.0)
	var player := SnesPlayer.new(snes, dsp)
	var gains: Array = []
	for t in 24:
		player.tick()
		gains.append(dsp.read(SnesDsp.V_GAIN))
	# Envelope 64 then down 8 a tick to the sustain level, 32.
	check_eq(gains[0], 126, "full volume on the first tick")
	check_eq(gains[4], 62, "sustain level (half, after SNESMod's rounding)")
	check_eq(gains[8], 62, "held while the note is on")
	check(gains[13] > 0 and gains[13] < 62, "falls after the note off (%d)" % gains[13])
	check_eq(gains[16], 0x9C, "silent volume becomes a fast fade")
	check_eq(dsp.read(SnesDsp.V_PITCHL) | (dsp.read(SnesDsp.V_PITCHH) << 8), SnesSong.dsp_pitch(69 * 64 + SnesSamples.pitch_base("square")), "pitch through SNESMod's table")
	check_eq(dsp.read(SnesDsp.V_VOLL), 63, "centre panning, left")
	check_eq(dsp.read(SnesDsp.V_VOLR), 64, "centre panning, right")


func test_arpeggio_and_vibrato() -> void:
	var snes := _player_song()
	snes.arpeggios = [{"name": "Arp 0-4-7", "values": [0, 4, 7], "loop": 0}]
	snes.notes[0][0]["arp"] = 0
	check_eq(snes.arp_param(0), 0x47, "J47")
	var rows := snes.rows()
	for r in 3:
		check_eq(int(rows[r][0]["command"]), SnesSong.CMD_ARPEGGIO, "J on every row of the note")
	var dsp := SnesDsp.new(32000.0)
	var player := SnesPlayer.new(snes, dsp)
	var base := SnesSamples.pitch_base("square")
	var pitches: Array = []
	for t in 5:
		player.tick()
		pitches.append(dsp.read(SnesDsp.V_PITCHL) | (dsp.read(SnesDsp.V_PITCHH) << 8))
	check_eq(pitches, [SnesSong.dsp_pitch(69 * 64 + base), SnesSong.dsp_pitch(73 * 64 + base), SnesSong.dsp_pitch(76 * 64 + base), SnesSong.dsp_pitch(69 * 64 + base), SnesSong.dsp_pitch(69 * 64 + base)], "note, +4, +7, note, and the next row starts over")
	var vib := _player_song()
	vib.instruments[0]["vibrato"] = {"delay": 1, "speed": 8, "depth": 4}
	var vrows := vib.rows()
	check_eq(vrows[0][0]["command"], 0, "no vibrato before its delay")
	check_eq(int(vrows[1][0]["command"]), SnesSong.CMD_VIBRATO, "vibrato from the delay")
	check_eq(int(vrows[1][0]["param"]), 0x84, "H84")


func test_dsp_plays_pitch_and_echo() -> void:
	var dsp := SnesDsp.new(32000.0)
	dsp.set_source(0, SnesSamples.decoded("square"))
	dsp.write(SnesDsp.MVOLL, 127)
	dsp.write(SnesDsp.V_VOLL, 127)
	dsp.write(SnesDsp.V_VOLR, 127)
	var pitch := SnesSong.dsp_pitch(69 * 64 + SnesSamples.pitch_base("square"))
	dsp.write(SnesDsp.V_PITCHL, pitch & 0xFF)
	dsp.write(SnesDsp.V_PITCHH, pitch >> 8)
	dsp.write(SnesDsp.V_GAIN, 127)
	dsp.write(SnesDsp.V_SRCN, 0)
	dsp.write(SnesDsp.KON, 1)
	var out := PackedFloat32Array()
	out.resize(16000)
	dsp.render(out, 0, out.size())
	check_near(float(_crossings(out, 100)), 440.0, 6.0, "A4 for half a second: about 440 sign changes")
	check(_peak(out) > 0.2, "loud (%s)" % _peak(out))
	# A one-shot sample stops at its end; echo repeats it later.
	var echo := SnesDsp.new(32000.0)
	echo.set_source(0, SnesSamples.decoded("hat"))
	echo.write(SnesDsp.MVOLL, 127)
	echo.write(SnesDsp.EVOLL, 100)
	echo.write(SnesDsp.EDL, 4)
	echo.write(SnesDsp.EON, 1)
	echo.write(SnesDsp.FIR, 127)
	echo.write(SnesDsp.FLG, 0)
	echo.write(SnesDsp.V_VOLL, 127)
	echo.write(SnesDsp.V_VOLR, 127)
	echo.write(SnesDsp.V_PITCHH, 0x10)
	echo.write(SnesDsp.V_GAIN, 127)
	echo.write(SnesDsp.KON, 1)
	var e := PackedFloat32Array()
	e.resize(6000)
	echo.render(e, 0, e.size())
	check(_peak(e, 0, 1000) > 0.05, "the hat plays")
	check(_peak(e, 1000, 2040) < 0.01, "then stops (%s)" % _peak(e, 1000, 2040))
	check(_peak(e, 2048, 3000) > 0.02, "and comes back 64 ms later as echo (%s)" % _peak(e, 2048, 3000))


func test_arranged_parts_fit() -> void:
	var song := _song()
	var snes := SnesArranger.arrange(song)
	check(snes.row_count > 0, "has rows")
	check_eq(snes.notes.size(), SnesSong.CHANNEL_COUNT, "eight channels")
	check_near(snes.get_bpm(), song.get_bpm(), song.get_bpm() * 0.01, "keeps the tempo")
	check((snes.notes[SnesSong.SFX_CHANNEL] as Array).is_empty(), "voice 8 left free for sound effects")
	for c in [SnesSong.LEAD, SnesSong.BASS, SnesSong.PAD1, SnesSong.DRUMS]:
		check(not (snes.notes[c] as Array).is_empty(), "%s plays" % SnesSong.SNES_CHANNEL_NAMES[c])
	for c in SnesSong.CHANNEL_COUNT:
		var last := -1
		for n: Dictionary in snes.notes[c]:
			check(int(n["row"]) > last, "one note per row, in order")
			last = int(n["row"])
			check(int(n["volume"]) >= 1 and int(n["volume"]) <= 64, "volume")
			check(int(n["note"]) <= snes.highest_note(int(n["instrument"])), "note within the sample's range")
	var ram := snes.ram_use()
	check(int(ram["free"]) > 16000, "plenty of audio RAM left (%d)" % int(ram["free"]))
	check(int(snes.echo["edl"]) > 0, "echo on")
	check(snes.report[0].begins_with("Voice 1 plays the lead"), "report names the voices")
	check_eq(snes.source.data["meta"]["target"], "snes")


func test_engine_plays_and_loops() -> void:
	var snes := SnesArranger.arrange(_song())
	var seq := SnesSequencer.new(snes, 22050)
	var loops := 0
	var peak := 0.0
	var seconds := snes.frames_before(snes.row_count) / snes.frame_hz + 2.0
	for i in int(seconds * 22050 / 4096):
		var frames := seq.render(4096)
		for f in frames:
			peak = maxf(peak, absf(f.x))
		for e in seq.events:
			if e[0] == ChipSongSequencer.EventType.LOOPED:
				loops += 1
	check(peak > 0.1, "makes sound (peak %s)" % peak)
	check(peak <= 1.0, "no clipping past full scale")
	check_eq(loops, 1, "loops once")


func test_muted_channels_are_silent() -> void:
	var song := _song()
	var snes := SnesArranger.arrange(song)
	var seq := SnesSequencer.new(snes, 22050, song.data["channels"].size())
	for c in song.data["channels"].size():
		seq.set_channel_muted(c, true)
	seq.seek_step(0)
	var peak := 0.0
	for i in 10:
		for f in seq.render(2048):
			peak = maxf(peak, absf(f.x))
	check(peak < 0.02, "silent when every part is muted (peak %s)" % peak)


## Reads a module back: header fields, orders, and every pattern's cells.
func _read_it(it: PackedByteArray) -> Dictionary:
	var out := {}
	out["magic"] = it.slice(0, 4).get_string_from_ascii()
	var orders := it.decode_u16(0x20)
	var ins := it.decode_u16(0x22)
	var smp := it.decode_u16(0x24)
	var pats := it.decode_u16(0x26)
	out["flags"] = it.decode_u16(0x2C)
	out["speed"] = it[0x32]
	out["tempo"] = it[0x33]
	out["orders"] = Array(it.slice(0xC0, 0xC0 + orders))
	var message_length := it.decode_u16(0x36)
	out["message"] = it.slice(it.decode_u32(0x38), it.decode_u32(0x38) + message_length).get_string_from_ascii()
	var at := 0xC0 + orders
	out["instruments"] = ins
	var samples: Array = []
	for i in smp:
		var p := it.decode_u32(at + (ins + i) * 4)
		samples.append({"magic": it.slice(p, p + 4).get_string_from_ascii(), "flags": it[p + 0x12], "length": it.decode_u32(p + 0x30), "loop_start": it.decode_u32(p + 0x34), "loop_end": it.decode_u32(p + 0x38), "c5": it.decode_u32(p + 0x3C), "pointer": it.decode_u32(p + 0x48)})
	out["samples"] = samples
	var patterns: Array = []
	for i in pats:
		var p := it.decode_u32(at + (ins + smp + i) * 4)
		var length := it.decode_u16(p)
		var row_count := it.decode_u16(p + 2)
		var data := it.slice(p + 8, p + 8 + length)
		var rows: Array = []
		var k := 0
		var row := {}
		while k < data.size():
			var v := data[k]
			k += 1
			if v == 0:
				rows.append(row)
				row = {}
				continue
			var c := (v - 1) & 63
			var mask := data[k]
			k += 1
			var cell := {"note": -1, "instrument": 0, "volume": -1, "command": 0, "param": 0}
			if mask & 1:
				cell["note"] = data[k]
				k += 1
			if mask & 2:
				cell["instrument"] = data[k]
				k += 1
			if mask & 4:
				cell["volume"] = data[k]
				k += 1
			if mask & 8:
				cell["command"] = data[k]
				cell["param"] = data[k + 1]
				k += 2
			row[c] = cell
		patterns.append({"rows": rows, "count": row_count})
	out["patterns"] = patterns
	return out


func test_module_reads_back() -> void:
	var snes := SnesArranger.arrange(_song())
	var it := ItWriter.module_bytes(snes)
	var mod := _read_it(it)
	check_eq(mod["magic"], "IMPM")
	check(int(mod["flags"]) & 4, "instrument mode, as SNESMod needs")
	check_eq(int(mod["speed"]), snes.speed(), "initial speed")
	check_eq(int(mod["tempo"]), snes.tempo, "initial tempo")
	check_eq(int(mod["orders"].back()), 255, "orders end with 255")
	check((mod["patterns"] as Array).size() <= 64, "at most 64 patterns")
	check(String(mod["message"]).contains("[[SNESMOD]]") and String(mod["message"]).contains("edl %d" % int(snes.echo["edl"])), "echo commands in the message")
	check_eq(int(mod["instruments"]), snes.instruments.size(), "one instrument each")
	for s: Dictionary in mod["samples"]:
		check_eq(s["magic"], "IMPS")
		check(int(s["flags"]) & 2, "16-bit")
		check(int(s["pointer"]) + int(s["length"]) * 2 <= it.size(), "sample data inside the file")
		if int(s["flags"]) & 16:
			check_eq((int(s["loop_end"]) - int(s["loop_start"])) % 16, 0, "loop is whole BRR blocks")
	# Playing the orders gives back every row the player plays.
	var rows := snes.rows()
	var r := 0
	var mismatches := 0
	for o in mod["orders"]:
		if int(o) == 255:
			break
		for row: Dictionary in mod["patterns"][int(o)]["rows"]:
			for c in SnesSong.CHANNEL_COUNT:
				var want = rows[r][c]
				var got = row.get(c)
				if want == null:
					if got != null:
						mismatches += 1
				elif got == null or int(got["note"]) != int(want["note"]) or int(got["instrument"]) != int(want["instrument"]) or int(got["volume"]) != int(want["volume"]) or int(got["command"]) != int(want["command"]):
					mismatches += 1
			r += 1
	check_eq(r, snes.row_count, "orders cover the song")
	check_eq(mismatches, 0, "every cell round-trips")
	check_eq(ItWriter.module_id("song_happy_platformer.it"), "MOD_SONG_HAPPY_PLATFORMER", "smconv's module id")


func test_module_golden() -> void:
	var snes := SnesArranger.arrange(_song())
	var it := ItWriter.module_bytes(snes)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(it)
	var lines: PackedStringArray = ["size %d" % it.size(), "sha256 %s" % hash.finish().hex_encode(), "speed %d tempo %d" % [snes.speed(), snes.tempo], "samples " + ",".join(snes.samples), ""]
	var rows := snes.rows()
	for r in mini(32, rows.size()):
		var parts: PackedStringArray = []
		for c in SnesSong.CHANNEL_COUNT:
			var cell = rows[r][c]
			if cell == null:
				parts.append("...")
			else:
				parts.append("%d/%d/%d/%d.%02x" % [int(cell["note"]), int(cell["instrument"]), int(cell["volume"]), int(cell["command"]), int(cell["param"]) & 0xFF])
		lines.append("%d: %s" % [r, " ".join(parts)])
	check_golden("snes_song_happy_platformer.txt", "\n".join(lines) + "\n")


func test_sfx_conversion() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := SnesSfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check(coin.pcm.size() > 1000, "has samples")
	var brr := coin.brr_bytes()
	check_eq(brr.size(), int(ceil(coin.pcm.size() / 16.0)) * 9, "whole BRR blocks")
	check(brr[brr.size() - 9] & SnesBrr.FLAG_END, "ends")
	var played := coin.render(44100)
	check_near(float(played.size()), coin.pcm.size() * 44100.0 / SnesSfx.RATE, 2.0, "plays at 16 kHz")
	check(_peak(played) > 0.05, "makes sound")
	check(SnesSfx.data_asm([coin]).contains("sfx_coin: .incbin \"coin.brr\""), "assembly labels the sound")


func test_export_jobs() -> void:
	var snes := SnesArranger.arrange(_song())
	var job := ExportJob.for_snes_song(snes, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	for path in ["snes/res/tune.it", "snes/Makefile", "snes/main.c", "snes/README.txt", "midi/tune.mid", "README.txt"]:
		check(job.files.has(path), path)
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	check((job.files["snes/main.c"] as PackedByteArray).get_string_from_utf8().contains("spcLoad(MOD_TUNE);"), "example program loads the module")
	check((job.files["snes/Makefile"] as PackedByteArray).get_string_from_utf8().contains("AUDIOFILES := res/tune.it"), "Makefile converts the module")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_snes_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	for path in ["audio/coin.wav", "snes/coin.brr", "snes/data.asm", "snes/README.txt", "README.txt"]:
		check(kit.files.has(path), path)
	check((kit.files["snes/README.txt"] as PackedByteArray).get_string_from_utf8().contains("spcSetSoundEntry(15, 8, 4, &sfx_coin_end - &sfx_coin, &sfx_coin, &sounds[0]);"), "how to load the sound")
