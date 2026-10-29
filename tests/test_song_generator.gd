extends "res://tests/test_case.gd"

const GOLDEN := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _settings(vibe: String, style: String, seed_text: String) -> SongSettings:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return s


func test_golden_songs() -> void:
	for combo in GOLDEN:
		var song := SongGenerator.generate(_settings(combo[0], combo[1], combo[2]))
		check_golden("song_%s_%s_%s.chipsong" % combo, song.to_json() + "\n")


func test_same_seed_same_song() -> void:
	var a := SongGenerator.generate(_settings("mysterious", "shmup", "abc"))
	var b := SongGenerator.generate(_settings("mysterious", "shmup", "abc"))
	var c := SongGenerator.generate(_settings("mysterious", "shmup", "abd"))
	check_eq(a.to_json(), b.to_json(), "same seed")
	check(a.to_json() != c.to_json(), "different seed should change the song")


func test_json_round_trip() -> void:
	var song := SongGenerator.generate(_settings("heroic", "power_metal", "1"))
	var copy := ChipSong.from_json(song.to_json())
	check(copy != null, "parses")
	if copy:
		check(JSON.stringify(JSON.parse_string(copy.to_json())) == JSON.stringify(JSON.parse_string(song.to_json())), "round trip changed the song")
	check_eq(ChipSong.validate(song.data), "", "validates")


func test_long_songs_reach_their_length() -> void:
	for seconds in [300.0, 600.0, 900.0]:
		for tempo in [60, 0, 240]:
			for form in ["verse_chorus", "rondo", "aaba", "loop"]:
				var s := _settings("happy", "platformer", "long")
				s.length_seconds = seconds
				s.tempo = tempo
				s.form = form
				var song := SongGenerator.generate(s)
				var label := "%ds at %d BPM, %s" % [seconds, tempo, form]
				check_eq(ChipSong.validate(song.data), "", label)
				check_near(song.get_length_seconds(), seconds, seconds * 0.15, label + " length")


func test_constraints_across_many_songs() -> void:
	var catalog := Catalog.get_default()
	var vibes := catalog.vibes.keys()
	var styles := catalog.styles.keys()
	var rng := Pcg32.for_stream(99, "test:constraints")
	for i in 40:
		var s := _settings(rng.pick(vibes), rng.pick(styles), str(i))
		s.intensity = rng.range_float(0.0, 100.0)
		s.complexity = rng.range_float(0.0, 100.0)
		var song := SongGenerator.generate(s, catalog)
		var label := "%s + %s seed %d" % [s.vibes[0], s.style, i]
		check_eq(ChipSong.validate(song.data), "", label)
		check(song.get_bpm() >= 40 and song.get_bpm() <= 260, "%s tempo %s" % [label, song.get_bpm()])
		if song.data["meta"]["form"] != "jingle":
			check_near(song.get_length_seconds(), s.length_seconds, s.length_seconds * 0.4, label + " length")
		var loop_start := song.get_loop_start_step()
		check(loop_start >= 0 and loop_start < song.get_loop_end_step(), label + " loop points")
		var sections: Array = song.data["sections"]
		for section in sections:
			for pattern_id in section["patterns"]:
				if int(pattern_id) < 0:
					continue
				for note in song.data["patterns"][int(pattern_id)]["notes"]:
					check(int(note[0]) >= 0 and int(note[0]) < int(section["length"]), "%s note start" % label)
					check(int(note[1]) > 0, "%s note length" % label)
					check(int(note[2]) >= 0 and int(note[2]) <= 127, "%s pitch %d" % [label, int(note[2])])


func test_locked_layers_survive_regeneration() -> void:
	var s := _settings("happy", "platformer", "lock")
	var first := SongGenerator.generate(s)
	for layer in SongSettings.LAYERS:
		s.variations[layer] = 1
	var locked := PackedStringArray(["Lead", "Drums"])
	var second := SongGenerator.generate(s, null, first, locked)
	for channel in [GenContext.Channel.LEAD, GenContext.Channel.DRUMS, GenContext.Channel.NOISE]:
		check_eq(_channel_notes(second, channel), _channel_notes(first, channel), "locked channel %d" % channel)
	for channel in [GenContext.Channel.HARMONY, GenContext.Channel.ARP, GenContext.Channel.PAD, GenContext.Channel.BASS]:
		var before := _channel_notes(first, channel)
		if not _is_silent(first, channel):
			check(_channel_notes(second, channel) != before, "unlocked channel %d should change" % channel)


func test_adaptive_states() -> void:
	var song := SongGenerator.generate(_settings("tense", "action", "states"))
	var names := song.get_state_names()
	for state in ["Explore", "Tension", "Combat", "Boss"]:
		check(names.has(state), "has state %s" % state)


func _is_silent(song: ChipSong, channel: int) -> bool:
	for section in song.data["sections"]:
		if int(section["patterns"][channel]) >= 0:
			return false
	return true


func _channel_notes(song: ChipSong, channel: int) -> String:
	var parts := []
	for section in song.data["sections"]:
		var pattern_id := int(section["patterns"][channel])
		parts.append(song.data["patterns"][pattern_id]["notes"] if pattern_id >= 0 else [])
	return JSON.stringify(parts)
