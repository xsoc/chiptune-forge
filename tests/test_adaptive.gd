extends "res://tests/test_case.gd"
## Adaptive states, transition rules and stingers.


func _song(settings: SongSettings = null) -> ChipSong:
	var s := settings if settings else SongSettings.new()
	if settings == null:
		s.vibes.assign(["heroic"])
		s.style = "platformer"
		s.length_seconds = 20.0
		s.seed_text = "5"
	return SongGenerator.generate(s)


func test_song_has_rules_and_stingers() -> void:
	var song := _song()
	check_eq(song.data["transitions"], SongGenerator.TRANSITIONS)
	var names: Array = []
	for stinger in song.data["stingers"]:
		names.append(stinger["name"])
		check(int(stinger["length"]) > 0)
		for note in stinger["notes"]:
			check(int(note[1]) + int(note[2]) <= int(stinger["length"]), "%s note inside its length" % stinger["name"])
			check(int(note[3]) >= 0 and int(note[3]) <= 127)
	check_eq(names, Array(SongGenerator.STINGERS))


func test_rule_matching() -> void:
	var player := ChipMusicPlayer.new()
	player.song = _song()
	check_eq(player.transition_for("Explore", "Combat")["how"], "stinger", "any to Combat")
	check_eq(player.transition_for("Combat", "Explore")["when"], "bar")
	check_eq(player.transition_for("Explore", "Tension")["when"], "beat", "falls back to any to any")
	player.song.data["transitions"].append({"from": "Tension", "to": "Combat", "when": "now", "how": "cut"})
	check_eq(player.transition_for("Tension", "Combat")["how"], "cut", "an exact route wins")
	player.song.data["transitions"] = []
	check_eq(player.transition_for("A", "B"), {"when": "beat", "how": "crossfade"})
	player.free()


func test_stinger_song_plays() -> void:
	var player := ChipMusicPlayer.new()
	player.song = _song()
	var stinger := player.stinger_song("rise")
	check(stinger != null)
	check_eq(stinger.data["order"], [0])
	var seq := ChipSongSequencer.new(stinger, 22050)
	seq.looping = false
	var frames := seq.render_all(1, 0.2)
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f.x))
	check(peak > 0.05, "makes sound")
	check(player.stinger_song("nope") == null)
	check_eq(player.get_stinger_names(), SongGenerator.STINGERS)
	player.free()


func test_state_change_without_playback_lands_at_once() -> void:
	var player := ChipMusicPlayer.new()
	player.song = _song()
	var landed: Array = []
	player.state_changed.connect(func(name: String) -> void: landed.append(name))
	player.set_state("Combat")
	check_eq(player.get_current_state(), "Combat")
	check_eq(landed, ["Combat"])
	player.free()


func test_custom_states_survive_regenerating() -> void:
	var s := SongSettings.new()
	s.vibes.assign(["calm"])
	s.style = "rpg_town" if Catalog.get_default().get_style("rpg_town") else "platformer"
	s.length_seconds = 20.0
	s.states = SongSettings.clean_states([{"name": "Stealth", "min_intensity": 1.5, "levels": {"Drums": "off", "Lead": "bogus"}}, {"name": "stealth"}])
	s.transitions = SongSettings.clean_transitions([{"to": "Stealth", "when": "phrase", "how": "stinger", "stinger": "zzz"}, {"from": "x"}])
	check_eq(s.states.size(), 1, "duplicates dropped")
	check_eq(s.states[0]["min_intensity"], 1.0)
	check_eq(s.states[0]["levels"]["Drums"], "off")
	check_eq(s.states[0]["levels"]["Lead"], "full")
	check_eq(s.transitions, [{"from": "*", "to": "Stealth", "when": "phrase", "how": "stinger", "stinger": "rise"}])
	var song := SongGenerator.generate(SongSettings.from_dict(s.to_dict()))
	check_eq(song.data["states"][0]["name"], "Stealth")
	check_eq(song.data["transitions"][0]["to"], "Stealth")
