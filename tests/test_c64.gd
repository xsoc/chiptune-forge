extends "res://tests/test_case.gd"


func _song(vibe := "happy", style := "platformer", seed_text := "42") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return SongGenerator.generate(s)


func _peak(out: PackedFloat32Array) -> float:
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	return peak


func test_frequencies_and_envelopes() -> void:
	check_eq(SidSong.note_freq(69), 7493, "A4 = 440 x 2^24 / 985248")
	check_eq(SidSong.note_freq(57), 3746, "an octave down halves it")
	check_eq(SidSong.adsr_of([15]), PackedInt32Array([0x00, 0xF2]), "a held note holds")
	var drum := SidSong.adsr_of([15, 13, 11, 8, 6, 4, 2, 1, 0])
	check_eq(drum[1] >> 4, 0, "a drum dies away")
	check((drum[0] & 0x0F) > 0, "over some time")


func test_chip_plays_waves_and_envelopes() -> void:
	var chip := SidChip.new(44100.0)
	chip.write(0, 7493 & 0xFF)
	chip.write(1, 7493 >> 8)
	chip.write(2, 0)
	chip.write(3, 8)
	chip.write(5, 0x00)
	chip.write(6, 0xF0)
	chip.write(24, 15)
	chip.write(4, SidChip.PULSE | SidChip.GATE)
	var out := PackedFloat32Array()
	out.resize(44100)
	chip.render(out, 0, 44100)
	var crossings := 0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
	check(absi(crossings - 880) < 20, "a pulse at 440 Hz (%d crossings)" % crossings)
	check(_peak(out.slice(22050)) > 0.1, "loud")
	check_eq(chip.envelope_level(0), 255, "attack reaches the top and sustain 15 holds it")
	chip.write(6, 0xF0)
	chip.write(4, SidChip.PULSE)
	chip.render(out, 0, 4410)
	check(chip.envelope_level(0) < 10, "a fast release falls away in 0.1 s (%d)" % chip.envelope_level(0))
	chip.write(4, SidChip.NOISE | SidChip.GATE)
	chip.render(out, 0, 44100)
	check(_peak(out.slice(4410)) > 0.1, "noise plays")


func test_arranged_parts_fit() -> void:
	var sid := SidArranger.arrange(_song())
	check_eq(sid.notes.size(), 4, "four parts")
	for c in 4:
		check(not (sid.notes[c] as Array).is_empty(), "%s has notes" % SidSong.SID_CHANNEL_NAMES[c])
	for c in 3:
		for n in sid.notes[c]:
			check(int(n["note"]) >= SidSong.LOWEST_NOTE and int(n["note"]) <= SidSong.HIGHEST_NOTE, "in range")
	check(not sid.report.is_empty(), "report")
	check(sid.source.data["meta"]["target"] == "c64", "source")


func test_notes_restart_their_envelopes() -> void:
	var sid := SidArranger.arrange(_song())
	var player := SidPlayer.new(sid, SidChip.new(8000.0))
	var gate_offs := 0
	var noise := 0
	for f in 600:
		var before := player.regs[4]
		player.tick()
		if (before & 1) and not (player.regs[4] & 1):
			gate_offs += 1
		if player.regs[11] & SidChip.NOISE:
			noise += 1
	check(gate_offs > 10, "the lead's gate goes off between notes (%d)" % gate_offs)
	check(noise > 20, "the drums take voice 2 (%d frames)" % noise)


func test_exported_data_plays_like_the_preview() -> void:
	for entry in [["happy", "platformer", "42"], ["boss_fight", "metal", "boss"], ["calm", "rpg_town", "7"]]:
		var sid := SidArranger.arrange(_song(entry[0], entry[1], entry[2]))
		var rec := SidWriter.record_song(sid)
		var frames: Array = rec["frames"]
		var data := SidWriter.song_bytes(sid)
		var psid := SidWriter.psid_bytes(sid, data)
		check(psid.size() < 0x9000, "%s fits below BASIC (%d bytes for %d frames)" % [entry[0], data.size(), frames.size()])
		var count := frames.size() + frames.size() / 2
		var decoded := SidWriter.decode_song(data, count)
		var loop_frame := int(rec["loop_frame"])
		var first := -1
		for f in count:
			var want: PackedInt32Array = frames[f] if f < frames.size() else frames[loop_frame + (f - frames.size())]
			if want != decoded[f]:
				first = f
				break
		check_eq(first, -1, "%s: the 6502 player's data matches the preview on every frame, through the loop" % entry[0])


func test_psid_header() -> void:
	var sid := SidArranger.arrange(_song())
	var psid := SidWriter.psid_bytes(sid)
	check(psid.slice(0, 4).get_string_from_ascii() == "PSID", "magic")
	check_eq((psid[0x0A] << 8) | psid[0x0B], 0x1000, "init")
	check_eq((psid[0x0C] << 8) | psid[0x0D], 0x1003, "play")
	check_eq(psid[0x7C] | (psid[0x7D] << 8), 0x1000, "load address")
	var player := SidWriter.player_binary()
	var song_at := psid[0x7E + 12] | (psid[0x7E + 13] << 8)
	check_eq(song_at, 0x1000 + player.size(), "the player knows where the song is")
	check(psid.slice(0x7E + player.size(), 0x7E + player.size() + 3).get_string_from_ascii() == "SIF", "the song follows the player")


func test_sequencer_plays() -> void:
	var sid := SidArranger.arrange(_song())
	var seq := SidSequencer.new(sid, 22050)
	seq.seek_step(0)
	var out := seq.render(22050 * 3)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v.x))
	check(peak > 0.1, "audible (%f)" % peak)


func test_sfx() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := SidSfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check(not coin.noise, "coin is tonal")
	check(_peak(coin.render(22050)) > 0.05, "coin plays")
	var boom := SidSfx.from_sfx(SfxGenerator.make_sfx(presets["explosion"], 1), "explosion")
	check(boom.noise, "explosion is noise")
	check(_peak(boom.render(22050)) > 0.05, "explosion plays")
	var data := SidWriter.sfx_bytes([coin, boom])
	for i in 2:
		var sfx: SidSfx = [coin, boom][i]
		var want := SidWriter.record_sfx(sfx)
		var got := SidWriter.decode_sfx(data, i)
		check_eq(got.size(), want.size(), "%s: every frame" % sfx.name)
		var same := true
		for f in mini(got.size(), want.size()):
			for r in SidWriter.SFX_REGS:
				if got[f][r] != want[f][r]:
					same = false
		check(same, "%s: the 6502 player plays it as the preview does" % sfx.name)


func test_export_jobs() -> void:
	var sid := SidArranger.arrange(_song())
	var job := ExportJob.for_sid_song(sid, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	for path in ["c64/tune.sid", "c64/song.bin", "c64/sid_player.s", "c64/sid_player.bin", "c64/sid_player.cfg", "c64/main.s", "c64/main.cfg", "c64/Makefile", "c64/README.txt", "midi/tune.mid", "README.txt"]:
		check(job.files.has(path), path)
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	check((job.files["c64/sid_player.s"] as PackedByteArray).get_string_from_utf8().contains("MIT License"), "the player is MIT")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_sid_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	for path in ["audio/coin.wav", "c64/sfx.bin", "c64/sid_player.s", "c64/sid_player.bin", "c64/README.txt", "README.txt"]:
		check(kit.files.has(path), path)
	check((kit.files["c64/README.txt"] as PackedByteArray).get_string_from_utf8().contains("jsr $1009"), "how to play a sound")
