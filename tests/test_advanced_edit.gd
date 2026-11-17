extends "res://tests/test_case.gd"
## The Advanced screen's editing: sections, bars, notes, recording, and that
## edited songs still export to every target.

const LEAD := GenContext.Channel.LEAD
const BASS := GenContext.Channel.BASS
const PAD := GenContext.Channel.PAD


func _song(seed_text := "7") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "platformer"
	s.seed_text = seed_text
	return SongGenerator.generate(s)


func _valid(song: ChipSong, what: String) -> void:
	check_eq(ChipSong.validate(song.data), "", what + " is a valid song")
	var length := song.get_length_steps()
	check(song.get_loop_start_step() < song.get_loop_end_step(), what + ": loop has length")
	check(song.get_loop_end_step() <= length, what + ": loop ends inside the song")
	var starts := SongEdit.order_starts(song)
	var cues := {}
	for cue in song.get_cues():
		cues[str(cue["name"])] = int(cue["step"])
	var order: Array = song.data["order"]
	for pos in order.size():
		var section_name := str(song.data["sections"][int(order[pos])]["name"])
		check(cues.has("section:" + section_name), "%s: cue for %s" % [what, section_name])
	for s in song.data["sections"]:
		for id in s["patterns"]:
			check(int(id) < song.data["patterns"].size(), what + ": pattern index in range")
	check_eq(starts.size(), order.size(), what + ": a start per order entry")


func test_add_repeat_copy_remove_move_sections() -> void:
	var song := _song()
	var count: int = song.data["order"].size()
	var length := song.get_length_steps()
	var bar := SongEdit.bar_steps(song)
	var added := SongEdit.add_section(song, 1, 2)
	_valid(song, "after add")
	check_eq(int(song.data["order"][1]), added, "new section at position 1")
	check_eq(song.get_length_steps(), length + 2 * bar, "two bars longer")
	for id in song.data["sections"][added]["patterns"]:
		check_eq(int(id), -1, "the new section is silent")

	SongEdit.repeat_section(song, 2)
	_valid(song, "after repeat")
	check_eq(song.data["order"][2], song.data["order"][3], "repeat plays the same section again")

	var copied := SongEdit.copy_section(song, 2)
	_valid(song, "after copy")
	var source := int(song.data["order"][2])
	for c in song.data["channels"].size():
		var a := PatternEdit.pattern_id(song, source, c)
		var b := PatternEdit.pattern_id(song, copied, c)
		if a >= 0:
			check(a != b, "a copy has its own patterns")
			check_eq(PatternEdit.notes_at(song, copied, c), PatternEdit.notes_at(song, source, c), "with the same notes")
	PatternEdit.toggle(song, copied, LEAD, 0, 30, 1)
	check(PatternEdit.find_note(PatternEdit.notes_at(song, source, LEAD), 0, 30) < 0, "editing the copy leaves the original alone")

	var moved_entry: Variant = song.data["order"][1]
	var to := SongEdit.move(song, 1, 2)
	_valid(song, "after move")
	check_eq(to, 3, "moved two places")
	check_eq(song.data["order"][3], moved_entry, "the entry moved")

	var before: int = song.data["order"].size()
	SongEdit.remove_at(song, 3)
	_valid(song, "after remove")
	check_eq(song.data["order"].size(), before - 1, "one fewer entry")
	check(song.data["order"].size() >= count, "still at least as long as before")
	for s in song.data["order"]:
		check(int(s) < song.data["sections"].size(), "order indexes in range after compacting")


func test_last_section_stays() -> void:
	var song := SongEdit.blank_song(_song(), 2)
	SongEdit.remove_at(song, 0)
	check_eq(song.data["order"].size(), 1, "a song keeps one section")


func test_loop_follows_sections() -> void:
	var song := _song()
	var loop := SongEdit.loop_positions(song)
	SongEdit.add_section(song, 0, 1)
	var after := SongEdit.loop_positions(song)
	check_eq(after, loop + Vector2i(1, 1), "a section added before the loop moves it along")
	SongEdit.set_loop(song, 0, 0)
	check_eq(song.get_loop_start_step(), 0, "loop from the start")
	check_eq(song.get_loop_end_step(), SongEdit.bar_steps(song), "to the end of the first section")
	_valid(song, "after set_loop")


func test_rename_and_resize() -> void:
	var song := _song()
	var section := int(song.data["order"][0])
	SongEdit.rename_section(song, section, "Verse")
	check_eq(str(song.data["sections"][section]["name"]), "Verse", "renamed")
	_valid(song, "after rename")
	# A section that shares a pattern with another: shrinking copies it first.
	var order: Array = song.data["order"]
	var shared := -1
	var shared_channel := -1
	for s in song.data["sections"].size():
		for c in song.data["channels"].size():
			if PatternEdit.pattern_id(song, s, c) >= 0 and PatternEdit.sharing(song, s, c) > 1:
				shared = s
				shared_channel = c
				break
		if shared >= 0:
			break
	if shared < 0:
		SongEdit.repeat_section(song, 1)
		shared = int(order[1])
		var copy_id := SongEdit.copy_section(song, 1)
		song.data["sections"][copy_id]["patterns"] = (song.data["sections"][shared]["patterns"] as Array).duplicate()
		shared_channel = LEAD
	var other_notes: Array = []
	for s in song.data["sections"].size():
		if s != shared and PatternEdit.pattern_id(song, s, shared_channel) == PatternEdit.pattern_id(song, shared, shared_channel):
			other_notes = PatternEdit.notes_at(song, s, shared_channel)
			break
	SongEdit.set_section_bars(song, shared, 1)
	var bar := SongEdit.bar_steps(song)
	check_eq(int(song.data["sections"][shared]["length"]), bar, "one bar long")
	for c in song.data["channels"].size():
		for n in PatternEdit.notes_at(song, shared, c):
			check(int(n[0]) + int(n[1]) <= bar, "notes fit the shorter section")
	var still := false
	for s in song.data["sections"].size():
		if s != shared and PatternEdit.notes_at(song, s, shared_channel) == other_notes and not other_notes.is_empty():
			still = true
	check(still or other_notes.is_empty(), "the section that shared the pattern keeps all its notes")
	_valid(song, "after resize")


func test_set_notes_cleans_up() -> void:
	var song := _song()
	var steps := int(song.data["sections"][0]["length"])
	PatternEdit.set_notes(song, 0, BASS, [[0, 8, 40, 100], [4, 2, 43, 300], [4, 2, 45, 90], [-3, 1, 50, 100], [steps + 2, 1, 50, 100], [steps - 1, 9, 200, 0]])
	var notes := PatternEdit.notes_at(song, 0, BASS)
	check_eq(notes.size(), 3, "out-of-range notes dropped, one of two at the same step kept")
	check_eq(notes[0].slice(0, 4), [0, 4, 40, 100], "the first note is cut where the next begins")
	check_eq(notes[1].slice(0, 4), [4, 2, 45, 90], "the later of two notes at one step wins")
	check_eq(notes[2].slice(0, 4), [steps - 1, 1, 127, 1], "lengths, pitches and velocities clamped")
	PatternEdit.set_notes(song, 0, PAD, [[0, 4, 60, 100], [0, 4, 64, 100], [0, 4, 67, 100], [0, 4, 64, 80]])
	var pad := PatternEdit.notes_at(song, 0, PAD)
	check_eq(pad.size(), 3, "chords stay on a part that plays them; repeats merge")


func test_copy_paste_clear_transpose_quantize_bars() -> void:
	var song := _song()
	var section := SongEdit.add_section(song, 0, 4)
	var bar := SongEdit.bar_steps(song)
	PatternEdit.set_notes(song, section, LEAD, [[0, 2, 60, 100], [5, 3, 62, 100], [9, 1, 64, 100]])
	var clip := SongEdit.copy_steps(song, section, [LEAD], 0, bar)
	SongEdit.paste_steps(song, section, clip, bar * 2, bar)
	var notes := PatternEdit.notes_at(song, section, LEAD)
	check(PatternEdit.find_note(notes, bar * 2, 60) >= 0 and PatternEdit.find_note(notes, bar * 2 + 9, 64) >= 0, "the bar is pasted into bar 3")
	SongEdit.transpose_steps(song, section, LEAD, bar * 2, bar * 3, 12)
	notes = PatternEdit.notes_at(song, section, LEAD)
	check(PatternEdit.find_note(notes, bar * 2, 72) >= 0, "bar 3 is an octave up")
	check(PatternEdit.find_note(notes, 0, 60) >= 0, "bar 1 is not")
	SongEdit.quantize_steps(song, section, LEAD, 0, bar, 4)
	notes = PatternEdit.notes_at(song, section, LEAD)
	check(PatternEdit.find_note(notes, 4, 62) >= 0, "step 5 snaps to the beat at step 4")
	check(PatternEdit.find_note(notes, 8, 64) >= 0, "step 9 snaps to step 8")
	SongEdit.clear_steps(song, section, [LEAD], 0, bar)
	notes = PatternEdit.notes_at(song, section, LEAD)
	for n in notes:
		check(int(n[0]) >= bar, "bar 1 cleared")
	check_eq(notes.size(), 3, "bar 3 kept")


func test_blank_song() -> void:
	var from := _song()
	var song := SongEdit.blank_song(from, 4)
	_valid(song, "blank song")
	check_eq(song.data["sections"].size(), 1, "one section")
	check_eq(song.get_length_steps(), 4 * SongEdit.bar_steps(song), "four bars")
	check_eq(song.data["instruments"], from.data["instruments"], "same instruments")
	check(song.data["patterns"].is_empty(), "no notes")


func test_recorder_writes_into_sections() -> void:
	var song := _song()
	var starts := SongEdit.order_starts(song)
	var second := int(song.data["order"][1])
	var rec := MidiRecorder.new(song)
	var t := float(starts[1])
	rec.mark(t)
	rec.note_on(60, 90, t + 0.2)
	rec.mark(t + 1.0)
	rec.note_off(60, t + 1.8)
	rec.note_on(64, 100, t + 3.9)
	rec.mark(t + 5.0)
	rec.mark(t + 7.0)
	rec.finish(t + 6.1)
	var written := rec.commit(song, LEAD, 1, true)
	check_eq(written, 2, "two notes")
	var notes := PatternEdit.notes_at(song, second, LEAD)
	var a := PatternEdit.find_note(notes, 0, 60)
	var b := PatternEdit.find_note(notes, 4, 64)
	check(a >= 0 and b >= 0, "quantized to the nearest step in the second section")
	if a >= 0:
		check_eq(notes[a].slice(0, 4), [0, 2, 60, 90], "length and velocity kept")
	for n in notes:
		check(int(n[0]) > 7 or int(n[2]) in [60, 64], "replace clears what the take passed over: %s" % [n])


func test_recorder_adds_and_loops() -> void:
	var song := SongEdit.blank_song(_song(), 1)
	var bar := SongEdit.bar_steps(song)
	PatternEdit.set_notes(song, 0, PAD, [[0, 4, 48, 100]])
	var rec := MidiRecorder.new(song)
	rec.mark(0.0)
	rec.note_on(55, 100, 0.0)
	rec.mark(float(bar) - 0.5)
	# The song loops while the key is held.
	rec.mark(0.5)
	rec.note_off(55, 2.0)
	rec.commit(song, PAD, 4, false)
	var notes := PatternEdit.notes_at(song, 0, PAD)
	check(PatternEdit.find_note(notes, 0, 48) >= 0, "overdub keeps the old note")
	check(PatternEdit.find_note(notes, 0, 55) >= 0, "and adds the new one")


func test_recorder_drums_follow_general_midi() -> void:
	var song := SongEdit.blank_song(_song(), 1)
	var rec := MidiRecorder.new(song)
	rec.mark(0.0)
	rec.note_on(36, 120, 0.0)
	rec.note_off(36, 0.5)
	rec.note_on(38, 110, 4.0)
	rec.note_off(38, 4.5)
	rec.note_on(42, 80, 2.0)
	rec.note_off(42, 2.5)
	rec.commit(song, -1, 1, false)
	var kicks := PatternEdit.notes_at(song, 0, GenContext.Channel.DRUMS)
	var noise := PatternEdit.notes_at(song, 0, GenContext.Channel.NOISE)
	check(PatternEdit.find_note(kicks, 0, 0, DrumWriter.KICK) >= 0, "36 is the kick, on the drum channel")
	check(PatternEdit.find_note(noise, 4, 0, DrumWriter.SNARE) >= 0, "38 is the snare, on noise")
	check(PatternEdit.find_note(noise, 2, 0, DrumWriter.HAT) >= 0, "42 is the hat")


func test_piano_roll_draw_tool() -> void:
	var roll := PianoRoll.new()
	roll.size = Vector2(800, 400)
	var rows: Array = []
	for i in 24:
		rows.append({"label": str(i)})
	roll.set_view(rows, 16, 4, 4, [], Color.WHITE)
	roll.draw_length = 2
	var edits: Array = []
	roll.notes_edited.connect(func(list: Array) -> void: edits.append(list))
	var at := Vector2(PianoRoll.KEYS_WIDTH + roll.cell.x * 3.5, PianoRoll.RULER_HEIGHT + roll.cell.y * 5.5)
	_click(roll, at, true)
	_click(roll, at, false)
	check_eq(edits.size(), 1, "one edit for one tap")
	if edits.size() == 1:
		check_eq(edits[0].size(), 1, "with one note")
		check_eq([edits[0][0]["step"], edits[0][0]["len"], edits[0][0]["row"]], [3, 2, 5], "at the tapped cell, the chosen length")
	# Drag the note two steps right and one row down.
	var motion := InputEventMouseMotion.new()
	_click(roll, at, true)
	motion.position = at + Vector2(roll.cell.x * 2.0, roll.cell.y)
	roll._gui_input(motion)
	_click(roll, motion.position, false)
	check_eq(edits.size(), 2, "the move is one edit")
	if edits.size() == 2:
		check_eq([edits[1][0]["step"], edits[1][0]["row"]], [5, 6], "moved")
	# A tap on the note removes it.
	_click(roll, motion.position, true)
	_click(roll, motion.position, false)
	check(edits.size() == 3 and edits[2].is_empty(), "tapping a note removes it")
	roll.free()


func test_editing_undo_and_redo() -> void:
	var app: Node = load("res://autoload/app_state.gd").new()
	app.song = _song()
	var before: Array = PatternEdit.notes_at(app.song, 0, LEAD)
	app.edit_song("Lead", func(s: ChipSong) -> void: PatternEdit.set_notes(s, 0, LEAD, []))
	check(PatternEdit.notes_at(app.song, 0, LEAD).is_empty(), "edited")
	app.undo_edit()
	check_eq(PatternEdit.notes_at(app.song, 0, LEAD), before, "undone")
	check(app.can_redo(), "can redo")
	app.redo_edit()
	check(PatternEdit.notes_at(app.song, 0, LEAD).is_empty(), "redone")
	app.edit_song("*", func(s: ChipSong) -> void: SongEdit.add_section(s, 0, 1))
	check(not app.can_redo(), "a new edit clears redo")
	for layer in SongSettings.LAYERS:
		check(app.locked_layers.has(layer), "a change to the sections locks %s" % layer)
	app.free()


func test_hand_made_song_exports_to_every_target() -> void:
	# A song written from scratch: one blank section, a copied section, notes
	# from the editor and a recorded take, including chords and drums.
	var song := SongEdit.blank_song(_song("31"), 2)
	var bar := SongEdit.bar_steps(song)
	PatternEdit.set_notes(song, 0, LEAD, [[0, 4, 72, 100], [4, 4, 74, 90], [8, 8, 76, 110], [bar, 16, 79, 100]])
	PatternEdit.set_notes(song, 0, PAD, [[0, bar, 60, 80], [0, bar, 64, 80], [0, bar, 67, 80]])
	PatternEdit.set_notes(song, 0, BASS, [[0, 4, 36, 100], [8, 4, 43, 100]])
	var rec := MidiRecorder.new(song)
	for s in bar * 2:
		rec.mark(float(s))
		if s % 4 == 0:
			rec.note_on(36 if s % 8 == 0 else 38, 110, float(s))
			rec.note_off(36 if s % 8 == 0 else 38, float(s) + 0.5)
		if s % 2 == 0:
			rec.note_on(42, 70, float(s))
			rec.note_off(42, float(s) + 0.4)
	rec.commit(song, -1, 1, false)
	SongEdit.copy_section(song, 0)
	SongEdit.transpose_steps(song, int(song.data["order"][1]), LEAD, 0, bar * 2, 5)
	SongEdit.set_loop(song, 0, 1)
	_valid(song, "hand-made song")
	for target in ExportJob.TARGETS:
		var arranged: Variant = ExportJob.arrange(target, song)
		check(target == "modern" or arranged != null, "%s arranges the song" % target)
		var job := ExportJob.for_target_song(target, song, {"prefix": "tune", "console": true, "wav": false, "godot": true, "plugin": false}, arranged)
		job.run()
		check(job.files.size() > 0, "%s writes files" % target)
		check(job.status == "" or not job.status.begins_with("error"), "%s: %s" % [target, job.status])


func _click(roll: PianoRoll, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = at
	roll._gui_input(e)
