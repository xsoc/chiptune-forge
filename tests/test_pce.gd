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


func _states(psg: PcePsg) -> Array:
	var out: Array = []
	for c in 6:
		var s := psg.channel_state(c)
		# A silent channel's frequency and noise don't matter.
		if (int(s["control"]) & 0x1F) == 0:
			s["period"] = 0
			s["noise"] = 0
		out.append(s)
	return out


func test_periods_and_volumes() -> void:
	check_eq(PceSong.note_period(69), 254, "A4 = 3579545 / (32 x 440)")
	check_eq(PceSong.note_period(57), 508, "an octave down doubles it")
	check_eq(PceSong.note_period(0), 4095, "held at 12 bits")
	check_eq(PceSong.volume_of_level(15), 31, "full")
	check_eq(PceSong.volume_of_level(0), 0, "silent")
	check_eq(PceSong.volume_of_level(12), 27, "6 dB down is 4 steps of 1.5 dB")


func test_psg_plays_waves_and_noise() -> void:
	var psg := PcePsg.new(44100.0)
	psg.write(PcePsg.MAIN_BALANCE, 0xFF)
	psg.write(PcePsg.SELECT, 0)
	psg.write(PcePsg.CONTROL, PcePsg.DDA)
	psg.write(PcePsg.CONTROL, 0)
	for v in PceSong.make_wave("square"):
		psg.write(PcePsg.WAVE, v)
	psg.write(PcePsg.BALANCE, 0xFF)
	psg.write(PcePsg.FREQ_LO, 254)
	psg.write(PcePsg.FREQ_HI, 0)
	psg.write(PcePsg.CONTROL, PcePsg.ON | 31)
	var out := PackedFloat32Array()
	out.resize(44100)
	psg.render(out, 0, 44100)
	var crossings := 0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
	check(absi(crossings - 880) < 20, "a square at 440 Hz (%d crossings)" % crossings)
	var loud := _peak(out)
	check(loud > 0.1, "loud")
	psg.write(PcePsg.CONTROL, PcePsg.ON | 11)
	psg.render(out, 22050, 22050)
	var quiet := _peak(out.slice(33000))
	check(absf(quiet / loud - 0.0316) < 0.01, "20 steps down is 30 dB quieter (%f)" % (quiet / loud))
	# Noise only works on channels 5 and 6.
	psg.write(PcePsg.CONTROL, 0)
	psg.write(PcePsg.SELECT, 4)
	psg.write(PcePsg.BALANCE, 0xFF)
	psg.write(PcePsg.NOISE, 0x80 | 28)
	psg.write(PcePsg.CONTROL, PcePsg.ON | 31)
	psg.render(out, 0, 44100)
	check(_peak(out) > 0.1, "noise plays")


func test_arranged_parts_fit() -> void:
	var pce := PceArranger.arrange(_song())
	check_eq(pce.notes.size(), 6, "six channels")
	for c in 6:
		check(not (pce.notes[c] as Array).is_empty(), "%s has notes" % PceSong.PCE_CHANNEL_NAMES[c])
	for c in 5:
		for n in pce.notes[c]:
			check(int(n["note"]) >= PceSong.LOWEST_NOTE and int(n["note"]) <= PceSong.HIGHEST_NOTE, "in range")
	for n in pce.notes[PceSong.DRUMS]:
		var inst: Dictionary = pce.instruments[int(n["instrument"])]
		if inst.get("noise", false):
			check(int(n["note"]) >= 1 and int(n["note"]) <= 31, "noise frequency")
	check(pce.instruments.size() <= 64, "instruments fit the player")
	check(not pce.report.is_empty(), "report")


func test_exported_data_plays_like_the_preview() -> void:
	for entry in [["happy", "platformer", "42"], ["boss_fight", "metal", "boss"]]:
		var pce := PceArranger.arrange(_song(entry[0], entry[1], entry[2]))
		var data := PceWriter.song_bytes(pce)
		check(data.size() < 0xFFFF, "fits")
		var a := PcePsg.new(44100.0)
		var b := PcePsg.new(44100.0)
		var player := PcePlayer.new(pce, a)
		var driver := PceDriver.new(b, data)
		driver.start()
		player.start(0)
		var frames := pce.total_frames() + pce.frames_before(pce.row_count / 2) + 10
		var mismatches := 0
		var first := -1
		for f in frames:
			player.tick()
			driver.frame()
			if _states(a) != _states(b):
				mismatches += 1
				if first < 0:
					first = f
		check_eq(mismatches, 0, "%s: the C player's data matches the preview on every frame, through the loop (first mismatch at frame %d)" % [entry[0], first])


func test_sequencer_plays_and_loops() -> void:
	var pce := PceArranger.arrange(_song())
	var seq := PceSequencer.new(pce, 22050)
	seq.seek_step(0)
	var out := seq.render(22050 * 3)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v.x))
	check(peak > 0.1, "audible (%f)" % peak)


func test_sfx() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := PceSfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check(not coin.noise, "coin is tonal")
	check(_peak(coin.render(22050)) > 0.05, "coin plays")
	var boom := PceSfx.from_sfx(SfxGenerator.make_sfx(presets["explosion"], 1), "explosion")
	check(boom.noise, "explosion is noise")
	check(_peak(boom.render(22050)) > 0.05, "explosion plays")
	# The C player plays the sounds as the preview does.
	var data := PceWriter.sfx_bytes([coin, boom])
	for i in 2:
		var sfx: PceSfx = [coin, boom][i]
		var a := PcePsg.new(22050.0)
		var b := PcePsg.new(22050.0)
		var player := PcePlayer.new(sfx.to_song(), a)
		player.channel_mask = 1 << PceSfx.VOICE
		var empty := PceSong.new()
		empty.row_count = 1
		empty.groove = PackedInt32Array([200])
		var driver := PceDriver.new(b, PceWriter.song_bytes(empty), data)
		driver.start()
		driver.sfx_play(i)
		var same := true
		for f in sfx.frame_count():
			player.tick()
			driver.frame()
			if a.channel_state(PceSfx.VOICE) != b.channel_state(PceSfx.VOICE):
				same = false
		check(same, "%s: the C player plays it as the preview does" % sfx.name)


func test_export_jobs() -> void:
	var pce := PceArranger.arrange(_song())
	var job := ExportJob.for_pce_song(pce, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	for path in ["pce/song.bin", "pce/pce_player.c", "pce/main.c", "pce/Makefile", "pce/README.txt", "midi/tune.mid", "README.txt"]:
		check(job.files.has(path), path)
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	var player := (job.files["pce/pce_player.c"] as PackedByteArray).get_string_from_utf8()
	check(player.contains("const int pce_period[] = {\n\t4095,") and not player.contains("PCE_PERIOD_TABLE"), "frequency table filled in")
	check(player.contains("MIT License"), "the player is MIT")
	check((job.files["pce/main.c"] as PackedByteArray).get_string_from_utf8().contains("#incbin(pce_song, \"song.bin\");"), "example program includes the song")
	check((job.files["pce/Makefile"] as PackedByteArray).get_string_from_utf8().contains("tune.pce"), "Makefile names the ROM")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_pce_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	for path in ["audio/coin.wav", "pce/sfx.bin", "pce/pce_player.c", "pce/README.txt", "README.txt"]:
		check(kit.files.has(path), path)
	check((kit.files["pce/README.txt"] as PackedByteArray).get_string_from_utf8().contains("pce_sfx_play(0);"), "how to play a sound")
