extends "res://tests/test_case.gd"

const LAYERS_SCREEN := preload("res://scenes/screens/layers_screen.tscn")


func _settings(seed_text := "7") -> SongSettings:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "platformer"
	s.seed_text = seed_text
	return s


func _song() -> ChipSong:
	return SongGenerator.generate(_settings())


func test_toggle_adds_and_removes() -> void:
	var song := _song()
	var lead := GenContext.Channel.LEAD
	check(PatternEdit.toggle(song, 0, lead, 3, 30, 2), "added")
	var notes := PatternEdit.notes_at(song, 0, lead)
	var at := PatternEdit.find_note(notes, 4, 30)
	check(at >= 0, "the note covers its second step")
	if at >= 0:
		check_eq(notes[at].slice(0, 4), [3, 2, 30, 100], "note as written")
	check(not PatternEdit.toggle(song, 0, lead, 4, 30), "tapping the note removes it")
	check(PatternEdit.find_note(PatternEdit.notes_at(song, 0, lead), 3, 30) < 0, "removed")
	check(song.validate(song.data) == "", "still a valid song")


func test_one_note_at_a_time_cuts_overlaps() -> void:
	var song := _song()
	var bass := GenContext.Channel.BASS
	PatternEdit.toggle(song, 0, bass, 0, 40, 8)
	PatternEdit.toggle(song, 0, bass, 4, 43, 2)
	var notes := PatternEdit.notes_at(song, 0, bass)
	for n in notes:
		var start := int(n[0])
		check(start + int(n[1]) <= 4 or start >= 4, "nothing else sounds into the new note: %s" % [n])
	var first := PatternEdit.find_note(notes, 0, 40)
	check(first >= 0 and int(notes[first][1]) == 4, "the earlier note is cut short")


func test_silent_slot_gets_a_pattern() -> void:
	var song := _song()
	var ids: Array = song.data["sections"][0]["patterns"]
	ids[GenContext.Channel.HARMONY] = -1
	var count: int = song.data["patterns"].size()
	PatternEdit.toggle(song, 0, GenContext.Channel.HARMONY, 0, 60, 4)
	check_eq(song.data["patterns"].size(), count + 1, "a new pattern")
	check_eq(PatternEdit.notes_at(song, 0, GenContext.Channel.HARMONY).size(), 1, "with the note")


func test_drums_go_to_their_channels() -> void:
	var song := _song()
	var section: int = song.data["sections"].size() - 1
	var kick_was := PatternEdit.find_note(PatternEdit.notes_at(song, section, GenContext.Channel.DRUMS), 1, 0, DrumWriter.KICK) >= 0
	PatternEdit.toggle(song, section, 0, 1, 0, 4, DrumWriter.KICK)
	var kick_now := PatternEdit.find_note(PatternEdit.notes_at(song, section, GenContext.Channel.DRUMS), 1, 0, DrumWriter.KICK) >= 0
	check(kick_now != kick_was, "the kick is on the drum channel")
	var hat_was := PatternEdit.find_note(PatternEdit.notes_at(song, section, GenContext.Channel.NOISE), 1, 0, DrumWriter.HAT) >= 0
	PatternEdit.toggle(song, section, 0, 1, 0, 4, DrumWriter.HAT)
	var notes := PatternEdit.notes_at(song, section, GenContext.Channel.NOISE)
	var at := PatternEdit.find_note(notes, 1, 0, DrumWriter.HAT)
	check((at >= 0) != hat_was, "the hat is on the noise channel")
	if at >= 0:
		check_eq(notes[at], [1, 1, DrumWriter.PITCH[DrumWriter.HAT], 100, DrumWriter.HAT], "a drum hit as the generator writes it")


func test_edits_lock_the_layer_survive_regeneration_and_undo() -> void:
	var state: Node = Engine.get_main_loop().root.get_node("AppState")
	var old_settings: SongSettings = state.settings
	var old_song: ChipSong = state.song
	var old_locks: PackedStringArray = state.locked_layers.duplicate()
	state.settings = _settings("99")
	state.locked_layers = PackedStringArray()
	state.generate()
	check(not state.can_undo(), "nothing to undo after generating")
	var original: String = state.song.to_json()
	state.edit_song("Lead", func(song: ChipSong) -> void:
		PatternEdit.toggle(song, 0, GenContext.Channel.LEAD, 0, 30, 1))
	check(state.locked_layers.has("Lead"), "editing locks the layer")
	check(state.can_undo(), "can undo")
	var edited := PatternEdit.notes_at(state.song, 0, GenContext.Channel.LEAD)
	state.undo_edit()
	check_eq(state.song.to_json(), original, "undo restores the notes")
	state.edit_song("Lead", func(song: ChipSong) -> void:
		PatternEdit.toggle(song, 0, GenContext.Channel.LEAD, 0, 30, 1))
	state.regenerate_unlocked()
	check_eq(PatternEdit.notes_at(state.song, 0, GenContext.Channel.LEAD), edited, "regenerating keeps the edited part")
	state.settings = old_settings
	state.song = old_song
	state.locked_layers = old_locks


func test_editor_on_the_layers_screen() -> void:
	var state: Node = Engine.get_main_loop().root.get_node("AppState")
	var old_settings: SongSettings = state.settings
	var old_song: ChipSong = state.song
	var old_locks: PackedStringArray = state.locked_layers.duplicate()
	state.settings = _settings("5")
	state.locked_layers = PackedStringArray()
	state.generate()
	var screen: Control = LAYERS_SCREEN.instantiate()
	Engine.get_main_loop().root.add_child(screen)
	if not screen.is_node_ready():
		screen._ready()
	var grid: PatternGrid = screen.get_node("%PatternGrid")
	var sections: Array = state.song.data["sections"]
	check_eq(screen.get_node("%SectionPick").item_count, sections.size(), "one entry per section")
	check_eq(grid.row_labels.size(), 24, "two octaves of the lead")
	check_eq(grid.steps, int(sections[0]["length"]), "a column per step")
	var lead_count := PatternEdit.notes_at(state.song, 0, GenContext.Channel.LEAD).size()
	grid.cell_pressed.emit(0, 0)
	check(PatternEdit.notes_at(state.song, 0, GenContext.Channel.LEAD).size() != lead_count, "a tap edits the lead")
	check(not screen.get_node("%Undo").disabled, "Undo is available")
	screen.get_node("%PartPick").select(SongSettings.LAYERS.find("Drums"))
	screen.get_node("%PartPick").item_selected.emit(SongSettings.LAYERS.find("Drums"))
	check_eq(grid.row_labels, PackedStringArray(["Crash", "Ride", "Open hat", "Hat", "Snare", "Tom", "Kick"]), "drum rows")
	check(screen.get_node("%OctaveUp").disabled, "no octaves for drums")
	screen.get_node("%Undo").pressed.emit()
	check(not state.can_undo(), "undone")
	screen.free()
	state.settings = old_settings
	state.song = old_song
	state.locked_layers = old_locks


## Edited notes cannot be made again from the settings, so the library keeps
## the song, and it still arranges for every target after a trip through
## JSON (where every number becomes a float).
func test_library_keeps_edited_notes() -> void:
	var state: Node = Engine.get_main_loop().root.get_node("AppState")
	var old_settings: SongSettings = state.settings
	var old_song: ChipSong = state.song
	var old_locks: PackedStringArray = state.locked_layers.duplicate()
	var old_library: Array = state.library.duplicate(true)
	state.settings = _settings("12")
	state.generate()
	state.save_song_to_library()
	check(not state.library[0].has("song"), "an unedited song is kept as its settings")
	state.edit_song("Bass", func(song: ChipSong) -> void:
		PatternEdit.toggle(song, 0, GenContext.Channel.BASS, 2, 33, 2))
	var edited: String = state.song.to_json()
	state.save_song_to_library()
	check(state.library[0].has("song"), "an edited song is kept whole")
	state.library = JSON.parse_string(JSON.stringify(state.library))
	state.generate()
	state.open_library_entry(0)
	check_eq(JSON.stringify(JSON.parse_string(state.song.to_json())), JSON.stringify(JSON.parse_string(edited)), "the edited notes come back")
	for arrange in [GbArranger.arrange.bind(state.song, {}), NesArranger.arrange.bind(state.song), SmsArranger.arrange.bind(state.song),
			MdArranger.arrange.bind(state.song), SnesArranger.arrange.bind(state.song), PceArranger.arrange.bind(state.song),
			AyArranger.arrange.bind(state.song), SidArranger.arrange.bind(state.song), GbaArranger.arrange.bind(state.song)]:
		check(arrange.call() != null, "arranges")
	var frames := ChipSongSequencer.new(state.song).render(44100)
	var peak := 0.0
	for f in frames:
		peak = maxf(peak, absf(f.x))
	check(peak > 0.01, "plays")
	state.library = old_library
	state._save_library()
	state.settings = old_settings
	state.song = old_song
	state.locked_layers = old_locks
