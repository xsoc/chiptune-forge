extends "res://tests/test_case.gd"
## Custom structures, and locking and regenerating sections.


func _settings() -> SongSettings:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "platformer"
	s.length_seconds = 40.0
	s.seed_text = "21"
	return s


func _names(song: ChipSong) -> Array:
	var out: Array = []
	for index in song.data["order"]:
		out.append(song.data["sections"][int(index)]["name"])
	return out


func _section_notes(song: ChipSong, section_name: String) -> String:
	for section in song.data["sections"]:
		if section["name"] == section_name:
			var notes: Array = []
			for id in section["patterns"]:
				notes.append(song.data["patterns"][int(id)]["notes"] if int(id) >= 0 else [])
			return JSON.stringify(notes)
	return ""


func test_custom_form_follows_the_letters() -> void:
	var s := _settings()
	s.form = "custom"
	s.custom_form = ["I", "A", "B", "A", "C", "O"]
	var song := SongGenerator.generate(s)
	check_eq(_names(song), ["Intro", "A", "B", "A", "C", "Outro"])
	check(song.data["cues"].any(func(c: Dictionary) -> bool: return c["name"] == "section:C"))
	check_eq(SongGenerator.generate(SongSettings.from_dict(s.to_dict())).to_json(), song.to_json(), "round trip")


func test_custom_form_is_cleaned() -> void:
	check_eq(SongSettings.clean_custom_form(["I", "Z", "O"]), ["I", "A", "O"], "needs a main section")
	check_eq(SongSettings.clean_custom_form("nope"), ["A"])


func test_regenerate_one_section() -> void:
	var s := _settings()
	s.form = "custom"
	s.custom_form = ["I", "A", "B", "A", "O"]
	var before := SongGenerator.generate(s)
	s.section_variations = {"B": 1}
	var keep := PackedStringArray(["Intro", "A", "Outro"])
	var after := SongGenerator.generate(s, null, before, PackedStringArray(), keep)
	check(_section_notes(after, "B") != _section_notes(before, "B"), "B changed")
	for name in keep:
		check_eq(_section_notes(after, name), _section_notes(before, name), "%s kept" % name)
	check_eq(after.data["meta"]["key"], before.data["meta"]["key"], "same key")


func test_locked_section_survives_new_variations() -> void:
	var s := _settings()
	var before := SongGenerator.generate(s)
	var first := str(before.data["sections"][int(before.data["order"][1])]["name"])
	for layer in SongSettings.LAYERS:
		s.variations[layer] = 3
	var after := SongGenerator.generate(s, null, before, PackedStringArray(), PackedStringArray([first]))
	check_eq(_section_notes(after, first), _section_notes(before, first), "locked section kept")
	var changed := false
	for section in after.data["sections"]:
		if section["name"] != first and _section_notes(after, section["name"]) != _section_notes(before, section["name"]):
			changed = true
	check(changed, "the others changed")


func test_locks_round_trip_in_settings() -> void:
	var s := _settings()
	s.locks = {"layers": ["Lead"], "sections": ["A"]}
	var back := SongSettings.from_dict(s.to_dict())
	check_eq(back.locks, {"layers": ["Lead"], "sections": ["A"]})
	check(not _settings().to_dict().has("locks"))


func test_open_project_restores_song_and_locks() -> void:
	var s := _settings()
	s.locks = {"layers": ["Bass"]}
	var song := SongGenerator.generate(s)
	var text := ProjectFile.for_song(song, s, "modern")
	var parsed := ProjectFile.parse(text)
	check_eq(parsed["kind"], "song")
	check_eq(parsed["settings"].locks, {"layers": ["Bass"]})
	check_eq(parsed["song"].data["patterns"].size(), song.data["patterns"].size())
	check_eq(str(parsed["song"].data["meta"]["key"]), str(song.data["meta"]["key"]))


func test_app_structure_edits() -> void:
	var state: Node = Engine.get_main_loop().root.get_node("AppState")
	var old_settings: SongSettings = state.settings
	var old_song: ChipSong = state.song
	var old_layers: PackedStringArray = state.locked_layers.duplicate()
	var old_sections: PackedStringArray = state.locked_sections.duplicate()
	state.settings = _settings()
	state.locked_layers = PackedStringArray()
	state.locked_sections = PackedStringArray()
	state.generate()
	var letters: Array = state.structure_letters()
	check_eq(letters, ["I", "A", "B", "A", "B", "A", "O"])
	state.set_section_locked("A", true)
	var a_before := _section_notes(state.song, "A")
	state.edit_structure(func(l: Array) -> void: l.insert(2, "A"))
	check_eq(_names(state.song), ["Intro", "A", "A", "B", "A", "B", "A", "Outro"])
	check_eq(state.settings.form, "custom")
	check_eq(state.settings.locks, {"sections": ["A"]})
	var b_before := _section_notes(state.song, "B")
	var a_mid := _section_notes(state.song, "A")
	state.regenerate_section("B")
	check(_section_notes(state.song, "B") != b_before, "B regenerated")
	check_eq(_section_notes(state.song, "A"), a_mid, "A stays")
	check(a_before != "", "A existed")
	state.settings = old_settings
	state.song = old_song
	state.locked_layers = old_layers
	state.locked_sections = old_sections
