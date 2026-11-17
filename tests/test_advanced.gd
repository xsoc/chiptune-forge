extends "res://tests/test_case.gd"
## The Advanced controls: swing, humanise, layer volumes and instrument swaps.


func _settings() -> SongSettings:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "platformer"
	s.length_seconds = 20.0
	s.seed_text = "11"
	return s


func _velocities(song: ChipSong) -> Array:
	var out: Array = []
	for pattern in song.data["patterns"]:
		for note in pattern["notes"]:
			out.append(note[3])
	return out


func test_defaults_change_nothing() -> void:
	var s := _settings()
	check(not s.to_dict().has("swing") and not s.to_dict().has("humanise"), "defaults are left out of saved settings")
	var a := SongGenerator.generate(s).to_json()
	var b := SongGenerator.generate(SongSettings.from_dict(s.to_dict())).to_json()
	check_eq(a, b)


func test_swing_override() -> void:
	var s := _settings()
	s.swing = 60.0
	check_near(float(SongGenerator.generate(s).data["timing"]["swing"]), 0.6, 0.001)
	s.swing = 0.0
	check_near(float(SongGenerator.generate(s).data["timing"]["swing"]), 0.0, 0.001)


func test_humanise_is_deterministic_and_changes_velocities() -> void:
	var s := _settings()
	var plain := SongGenerator.generate(s)
	s.humanise = 80.0
	var a := SongGenerator.generate(s)
	var b := SongGenerator.generate(s)
	check_eq(a.to_json(), b.to_json(), "same seed, same song")
	check(_velocities(a) != _velocities(plain), "velocities wander")
	for v in _velocities(a):
		check(v >= 1 and v <= 127, "velocity in range")


func test_instrument_swap() -> void:
	var s := _settings()
	s.instrument_swaps = {"Lead": "saw", "Bass": "pulse12"}
	var song := SongGenerator.generate(s)
	var lead: Dictionary = song.data["instruments"][GenContext.Channel.LEAD]
	var bass: Dictionary = song.data["instruments"][GenContext.Channel.BASS]
	check_eq(lead["wave"], "saw")
	check_eq(bass["wave"], "pulse")
	check_eq(bass["duty"], 0.125)


func test_layer_volume_reaches_consoles() -> void:
	var s := _settings()
	s.layer_volumes = {"Lead": 50.0, "Pad": 0.0}
	var song := SongGenerator.generate(s)
	check_eq(song.data["channels"][GenContext.Channel.LEAD]["volume"], 0.5, "modern plays the channel volume")
	var chip := SynthEngines.chip_song(song)
	check_eq(chip.data["channels"][GenContext.Channel.LEAD]["volume"], 1.0, "consoles get it in the notes")
	for section in chip.data["sections"]:
		check_eq(int(section["patterns"][GenContext.Channel.PAD]), -1, "a silent layer is dropped")
	var plain := SynthEngines.chip_song(SongGenerator.generate(_settings()))
	var lead_plain: Array = plain.data["patterns"][plain.data["sections"][1]["patterns"][GenContext.Channel.LEAD]]["notes"]
	var lead_half: Array = chip.data["patterns"][chip.data["sections"][1]["patterns"][GenContext.Channel.LEAD]]["notes"]
	check_eq(lead_half[0][3], clampi(roundi(lead_plain[0][3] * 0.5), 1, 127), "velocity halved")
	check(GbArranger.arrange(chip) != null, "arranges")


func test_settings_round_trip_and_clamp() -> void:
	var s := SongSettings.from_dict({"swing": 250, "humanise": 30, "layer_volumes": {"Lead": 200, "Nope": 10}, "instrument_swaps": {"Drums": "saw", "Pad": "sine", "Arp": "kazoo"}})
	check_eq(s.swing, 100.0)
	check_eq(s.humanise, 30.0)
	check_eq(s.layer_volumes, {"Lead": 150.0})
	check_eq(s.instrument_swaps, {"Pad": "sine"})
