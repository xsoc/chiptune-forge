extends "res://tests/test_case.gd"


func _settings(engine := "chip") -> SongSettings:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "synthwave"
	s.length_seconds = 20.0
	s.seed_text = "engines"
	s.engine = engine
	return s


func _render(song: ChipSong, seconds := 2.0) -> PackedFloat32Array:
	var seq := ChipSongSequencer.new(song, 22050)
	var frames := int(22050 * seconds)
	var buffer := seq.render(frames)
	var mono := PackedFloat32Array()
	mono.resize(frames)
	for i in frames:
		mono[i] = buffer[i].x
	return mono


## The classic engine leaves songs exactly as they were, settings included.
func test_chip_is_unchanged() -> void:
	var s := _settings()
	check(not s.to_dict().has("engine"), "chip is not written to settings")
	var song := SongGenerator.generate(s)
	for inst in song.data["instruments"]:
		check(not inst.has("engine"), "%s has no engine" % inst["name"])
	check(SynthEngines.chip_song(song) == song, "chip_song of a chip song is the song")


## Every engine changes only the instruments, never the notes.
func test_engines_keep_notes() -> void:
	var plain := SongGenerator.generate(_settings())
	for engine in SynthEngines.ENGINES:
		var song := SongGenerator.generate(_settings(engine))
		check_eq(JSON.stringify(song.data["sections"]), JSON.stringify(plain.data["sections"]), "%s keeps the notes" % engine)
		check_eq(JSON.stringify(SynthEngines.chip_song(song).data["instruments"]), JSON.stringify(plain.data["instruments"]), "%s gives the chip instruments back" % engine)


## Applying an engine twice, or switching between engines, ends the same.
func test_apply_is_repeatable() -> void:
	var plain: Array = SongGenerator.generate(_settings()).data["instruments"]
	var fm := SynthEngines.apply(plain, "fm")
	var sampled := SynthEngines.apply(fm, "sampled")
	check_eq(JSON.stringify(sampled), JSON.stringify(SynthEngines.apply(plain, "sampled")), "fm then sampled is sampled")
	check_eq(JSON.stringify(SynthEngines.apply(sampled, "chip")), JSON.stringify(plain), "back to chip")
	# A round trip through JSON, as a saved song makes, changes nothing.
	var saved: Array = JSON.parse_string(JSON.stringify(sampled))
	check_eq(JSON.stringify(SynthEngines.apply(saved, "chip")), JSON.stringify(plain), "saved song back to chip")


func test_layer_engines() -> void:
	var s := _settings("analog")
	s.layer_engines = {"Pad": "sampled", "Lead": "chip"}
	var engines := SynthEngines.song_engines(SongGenerator.generate(s))
	check_eq(engines["Lead"], "chip", "lead kept chip")
	check_eq(engines["Pad"], "sampled", "pad sampled")
	check_eq(engines["Bass"], "analog", "bass follows the song")
	check_eq(engines["Drums"], "chip", "drums change only when sampled")
	check_eq(SongSettings.from_dict(s.to_dict()).layer_engines, s.layer_engines, "layer engines saved")


func test_auto_uses_style() -> void:
	var catalog := Catalog.get_default()
	check_eq(SynthEngines.resolve("auto", catalog.get_style("synthwave")), "analog", "synthwave is analog")
	for id in catalog.styles:
		check(SynthEngines.style_engine(catalog.styles[id]) in SynthEngines.ENGINES, "%s has an engine" % id)


## Each engine makes sound, the same every time, without clipping.
func test_engines_render() -> void:
	for engine in SynthEngines.ENGINES:
		var song := SongGenerator.generate(_settings(engine))
		var a := _render(song)
		var b := _render(song)
		var peak := 0.0
		var energy := 0.0
		for v in a:
			peak = maxf(peak, absf(v))
			energy += v * v
		check(energy > 1.0, "%s is audible" % engine)
		check(peak <= 1.0, "%s does not clip (peak %.2f)" % [engine, peak])
		check(a == b, "%s renders the same twice" % engine)


func test_tables_and_samples() -> void:
	for bank in ChipEngines.BANKS:
		var frames := ChipEngines.bank(bank)
		check_eq(frames.size(), ChipEngines.FRAMES, "%s frames" % bank)
		check_eq(frames[0].size(), ChipEngines.TABLE_SIZE, "%s table size" % bank)
	for name in ChipEngines.SAMPLES:
		var data := ChipEngines.sample(name)
		check(data.size() > 1000, "%s has length" % name)
		var peak := 0.0
		for v in data:
			peak = maxf(peak, absf(v))
		check(absf(peak - 1.0) < 0.001, "%s is normalised" % name)
	# Integer noise: the same numbers on every platform.
	check_eq(snappedf(ChipEngines.sample("snare")[100], 0.000001), snappedf(ChipEngines.sample("snare")[100], 0.000001), "stable")


## Console targets arrange the chip instruments, whatever the engine.
func test_consoles_ignore_engines() -> void:
	var plain := SongGenerator.generate(_settings())
	var sampled := SongGenerator.generate(_settings("sampled"))
	var a: NesSong = ExportJob.arrange("nes", plain)
	var b: NesSong = ExportJob.arrange("nes", sampled)
	check_eq(FamiStudioWriter.song_project(b, "t"), FamiStudioWriter.song_project(a, "t"), "NES arrangement unchanged")
