extends "res://tests/test_case.gd"


func _song(vibe := "happy", style := "platformer", seed_text := "42") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return SongGenerator.generate(s)


func test_note_table_matches_famistudio() -> void:
	# Spot checks against FamiStudio's NTSC note table.
	check_eq(NesSong.note_period(1), 3419)
	check_eq(NesSong.note_period(49), 213)
	check_eq(NesSong.note_period(58), 126)
	check_eq(NesSong.note_period(96), 13)
	check_eq(NesSong.note_name(1), "C0")
	check_eq(NesSong.note_name(49), "C4")
	check_eq(NesSong.note_name(59), "A#4")
	check_eq(NesSong.mix_volume(15, 15), 15)
	check_eq(NesSong.mix_volume(1, 1), 1)
	check_eq(NesSong.mix_volume(2, 11), 1)
	check_eq(NesSong.mix_volume(2, 12), 2)
	check_eq(NesSong.mix_volume(0, 15), 0)


func test_groove_matches_tempo() -> void:
	for bpm in [72.0, 100.0, 120.0, 130.0, 150.0, 175.0]:
		var t := NesSong.choose_groove(bpm, 4)
		var groove: PackedInt32Array = t["groove"]
		check_near(float(t["bpm"]), bpm, bpm * 0.025, "tempo at %d BPM" % int(bpm))
		check([1, 2, 4].has(groove.size()), "groove divides a bar")
		var low := 99
		var high := 0
		for f in groove:
			low = mini(low, f)
			high = maxi(high, f)
		check(high - low <= 1, "groove values differ by at most one frame")


func test_arranged_notes_fit_the_chip() -> void:
	var nes := NesArranger.arrange(_song())
	check(nes.row_count > 0, "has rows")
	check(nes.note_count() > 50, "plays plenty of notes (%d)" % nes.note_count())
	for c in 4:
		var last := -1
		for n: Dictionary in nes.notes[c]:
			var note := int(n["note"])
			check(int(n["row"]) > last, "one note per row, in order")
			last = int(n["row"])
			check(int(n["length"]) >= 1, "length")
			check(int(n["instrument"]) >= 0 and int(n["instrument"]) < nes.instruments.size(), "instrument")
			check(int(n["volume"]) >= 1 and int(n["volume"]) <= 15, "volume")
			if c == NesSong.NOISE:
				check(note >= 16 and note <= 31, "noise note in its block")
			else:
				check(note >= NesSong.LOWEST_TONAL_NOTE and note <= NesSong.LAST_NOTE, "note %d on channel %d" % [note, c])
				check(NesSong.note_period(note) <= 0x7FF, "period fits the timer")
	for inst: Dictionary in nes.instruments:
		for env in ["volume", "duty"]:
			for v in inst.get(env, []):
				check(int(v) >= 0 and int(v) <= 15, "%s value" % env)
		check((inst.get("volume", [15]) as Array).size() <= NesSong.MAX_ENVELOPE, "envelope length")
	check(nes.pattern_chunks().size() <= NesSong.MAX_PATTERNS, "fits in one song")
	check(not nes.report.is_empty(), "has a report")


func test_engine_plays_and_loops() -> void:
	var nes := NesArranger.arrange(_song())
	var seq := NesSequencer.new(nes, 22050)
	var loops := 0
	var peak := 0.0
	var seconds := nes.frames_before(nes.row_count) / NesApu.FRAME_HZ + 2.0
	for i in int(seconds * 22050 / 2048):
		var frames := seq.render(2048)
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
	var nes := NesArranger.arrange(song)
	var seq := NesSequencer.new(nes, 22050, song.data["channels"].size())
	for c in song.data["channels"].size():
		seq.set_channel_muted(c, true)
	seq.seek_step(0)
	var peak := 0.0
	for i in 20:
		for f in seq.render(2048):
			peak = maxf(peak, absf(f.x))
	check(peak < 0.02, "silent when every part is muted (peak %s)" % peak)


func test_envelopes_restart_loop_and_hold() -> void:
	var nes := NesSong.new()
	nes.groove = PackedInt32Array([4])
	nes.row_count = 4
	nes.looping = false
	nes.section_rows = [{"name": "A", "row": 0, "length": 4}]
	nes.instruments = [{"name": "T", "volume": [15, 10, 5], "duty": [2], "pitch": [0, 1, -1], "pitch_loop": 1}]
	nes.notes[0] = [{"row": 0, "length": 1, "note": 49, "instrument": 0, "volume": 15, "arp": -1}, {"row": 2, "length": 2, "note": 49, "instrument": 0, "volume": 15, "arp": -1}]
	var apu := NesApu.new(22050.0)
	var player := NesPlayer.new(nes, apu)
	var volumes: Array = []
	var periods: Array = []
	for f in 16:
		player.tick()
		volumes.append(apu.read(NesApu.PULSE1_VOL) & 0x0F)
		periods.append(apu.pulse_period(0))
	# Row 0: 15, 10, 5, then holds 5. Row 1: stopped. Row 2: restarts.
	check_eq(volumes.slice(0, 4), [15, 10, 5, 5], "envelope plays then holds")
	check_eq(volumes.slice(4, 8), [0, 0, 0, 0], "note stops at its duration")
	check_eq(volumes.slice(8, 11), [15, 10, 5], "envelope restarts on the next note")
	check_eq(periods.slice(0, 4), [213, 214, 212, 214], "pitch envelope loops")
	check_eq(apu.read(NesApu.PULSE1_VOL) >> 6, 2, "duty from the duty envelope")


func test_famistudio_text_is_stable() -> void:
	var nes := NesArranger.arrange(_song())
	var text := FamiStudioWriter.song_project(nes, nes.title, "Chiptune Forge test")
	check(text.begins_with("Project TempoMode=\"FamiStudio\""), "project line first")
	check(not text.contains("Version="), "no version, so any FamiStudio reads it")
	for channel in NesSong.FAMISTUDIO_CHANNELS:
		check(text.contains("Channel Type=\"%s\"" % channel), "has " + channel)
	check(text.contains("Groove=\"%d\"" % nes.groove[0]) or text.contains("Groove=\"%d-" % nes.groove[0]), "writes the groove")
	check_golden("nes_song_happy_platformer.txt", text)


func test_sfx_conversion() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := NesSfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check_eq(coin.channel, NesSong.PULSE2)
	check(coin.frame_count() > 1 and coin.frame_count() <= NesSfx.MAX_FRAMES, "coin frames")
	check_eq(coin.volume[coin.frame_count() - 1], 0, "ends silent")
	check_eq(coin.pitch[0], 0, "pitch starts on the note")
	var boom := NesSfx.from_sfx(SfxGenerator.make_sfx(presets["explosion"], 1), "boom")
	check_eq(boom.channel, NesSong.NOISE)
	var peak := 0.0
	for s in coin.render(22050):
		peak = maxf(peak, absf(s))
	check(peak > 0.1, "coin makes sound (peak %s)" % peak)
	var text := FamiStudioWriter.sfx_project([coin, boom], "kit")
	check(text.contains("Song Name=\"coin\"") and text.contains("Song Name=\"boom\""), "one song per sound")
	check(text.contains("Instrument Name=\"coin\""), "one instrument per sound")


func test_export_jobs() -> void:
	var nes := NesArranger.arrange(_song())
	var job := ExportJob.for_nes_song(nes, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	check(job.files.has("nes/tune.txt"), "FamiStudio project")
	check(job.files.has("nes/README.txt"), "how to use it")
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	check(job.files.has("midi/tune.mid"), "midi")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_nes_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	check(kit.files.has("audio/coin.wav"), "sound wav")
	check(kit.files.has("nes/my_kit.txt"), "kit project")
