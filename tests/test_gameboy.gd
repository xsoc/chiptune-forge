extends "res://tests/test_case.gd"


func _song(vibe := "happy", style := "platformer", seed_text := "42") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return SongGenerator.generate(s)


func test_timing_matches_tempo() -> void:
	for bpm in [72.0, 100.0, 120.0, 140.0, 175.0]:
		var t := GbSong.choose_timing(bpm, 4)
		check_near(float(t["bpm"]), bpm, bpm * 0.01, "tempo at %d BPM" % int(bpm))
		check(float(t["tick_hz"]) > 30.0 and float(t["tick_hz"]) < 140.0, "tick rate %s" % t["tick_hz"])
		check(int(t["tma"]) >= 0 and int(t["tma"]) <= 255, "TMA in range")
		check([0x04, 0x07].has(int(t["tac"])), "TAC is a timer mode")


func test_arranged_notes_fit_the_driver() -> void:
	var gb := GbArranger.arrange(_song())
	check_eq(gb.cells.size(), 4)
	check(gb.row_count > 0, "has rows")
	var notes := 0
	for c in 4:
		for row in gb.row_count:
			var cell := gb.get_cell(c, row)
			var note := cell[0]
			check(note == GbSong.NO_NOTE or (note >= 0 and note < GbSong.LAST_NOTE), "note %d on channel %d" % [note, c])
			check(cell[1] >= 0 and cell[1] <= 15, "instrument in range")
			if note != GbSong.NO_NOTE:
				notes += 1
	check(notes > 50, "plays plenty of notes (%d)" % notes)
	check(gb.data_size() < GbSong.BANK_BYTES, "fits in one ROM bank")
	check(not gb.report.is_empty(), "has a report")


func test_tracks_break_and_loop() -> void:
	var gb := GbArranger.arrange(_song())
	var tracks := gb.build_tracks()
	var patterns: Array = tracks["patterns"]
	var orders: Array = tracks["orders"]
	check_eq(orders.size(), 4)
	var count: int = orders[0].size()
	for c in 4:
		check_eq(orders[c].size(), count, "orders per channel")
	for p in patterns:
		check(p.size() % 4 == 0 and p.size() / 4 <= GbSong.PATTERN_ROWS, "pattern length")
	# The last order's pattern on one channel jumps back to the loop.
	var jumps := 0
	for c in 4:
		var rows: PackedInt32Array = patterns[orders[c][count - 1]]
		for r in rows.size() / 4:
			if rows[r * 4 + 2] == GbSong.FX_POSITION_JUMP:
				jumps += 1
				check_eq(rows[r * 4 + 3], int(tracks["loop_order"]) + 1, "jump target")
	check_eq(jumps, 1, "one position jump")


func test_driver_plays_and_loops() -> void:
	var gb := GbArranger.arrange(_song())
	var seq := GbSequencer.new(gb, 22050)
	var loops := 0
	var peak := 0.0
	var seconds := gb.row_count * gb.ticks_per_row / gb.tick_hz + 2.0
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
	var gb := GbArranger.arrange(song)
	var seq := GbSequencer.new(gb, 22050, song.data["channels"].size())
	for c in song.data["channels"].size():
		seq.set_channel_muted(c, true)
	seq.seek_step(0)
	var peak := 0.0
	for i in 20:
		for f in seq.render(2048):
			peak = maxf(peak, absf(f.x))
	check(peak < 0.02, "silent when every part is muted (peak %s)" % peak)


func test_sfx_channel_reservation() -> void:
	var free := GbArranger.arrange(_song(), {"sfx_channel": 3, "sfx_free": true})
	for row in free.row_count:
		check_eq(free.get_cell(3, row)[0], GbSong.NO_NOTE, "noise kept free")
		if free.get_cell(3, row)[0] != GbSong.NO_NOTE:
			break
	check(GbCWriter.song_header(free, "song_x").contains("#define SONG_X_SFX_CHANNEL HT_CH4"), "header marks the SFX channel")


func test_c_export_is_stable() -> void:
	var gb := GbArranger.arrange(_song())
	var symbol := GbCWriter.song_symbol("Happy Platformer!")
	check_eq(symbol, "song_happy_platformer")
	check_golden("gb_song_happy_platformer.c", GbCWriter.song_source(gb, symbol, "Chiptune Forge test"))
	var project := GbCWriter.song_project(gb, symbol, gb.title, "test")
	for path in ["src/main.c", "src/%s.c" % symbol, "src/%s.h" % symbol, "Makefile", "README.txt", "hUGEDriver/hUGEDriver.asm"]:
		check(project.has(path), "project has " + path)


func test_sfx_conversion() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := SfxGenerator.make_sfx(presets["coin"], 1)
	var gb_coin := GbSfx.from_sfx(coin, "coin")
	check_eq(gb_coin.channel, GbSfx.PULSE)
	check(gb_coin.frame_count() > 0 and gb_coin.frame_count() <= GbSfx.MAX_FRAMES, "coin frames")
	check(gb_coin.frames[0] & GbSfx.RETRIGGER != 0, "first frame triggers")
	var boom := GbSfx.from_sfx(SfxGenerator.make_sfx(presets["explosion"], 1), "boom")
	check_eq(boom.channel, GbSfx.NOISE)
	var samples := gb_coin.render(22050)
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	check(peak > 0.1, "coin makes sound")
	var header := GbCWriter.sfx_header([gb_coin, boom], "kit")
	check(header.contains("SFX_COIN") and header.contains("SFX_BOOM"), "header names the sounds")


func test_export_jobs() -> void:
	var gb := GbArranger.arrange(_song())
	var job := ExportJob.for_gameboy_song(gb, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	check(job.files.has("gameboy/src/song_tune.c"), "song data")
	check(job.files.has("gameboy/Makefile"), "makefile")
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	check(job.files.has("midi/tune.mid"), "midi")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_gameboy_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	check(kit.files.has("audio/coin.wav"), "sound wav")
	check(kit.files.has("gameboy/Makefile"), "kit makefile")
	check(str(kit.files.keys()).contains(".c"), "kit C source")
