extends Control
## Music mode, Advanced screen: write or change a song from single notes up.
##
## A piano roll edits one part of one section; the bar tools copy, paste,
## move and quantize bars or selected notes; the song panel adds, copies,
## repeats, reorders and resizes sections and sets the loop and tempo. Live
## playing comes from the on-screen keys, the computer keyboard or a MIDI
## keyboard, and can be recorded into the part while the song plays, or
## entered note by note at the cursor (step input).
##
## Every change goes through [method AppState.edit_song], so it can be
## undone, is kept when the song is saved, plays through the song's synth
## and exports to every target (whose arrangers fit it to the chip).

const LENGTHS := [[1, "1 step"], [2, "2 steps"], [4, "1 beat"], [8, "2 beats"], [16, "1 bar"]]
const GRIDS := [[1, "Grid: step"], [2, "Grid: 2 steps"], [4, "Grid: beat"]]
const TOP_PITCH := 108
const BOTTOM_PITCH := 21
const PHONE_WIDTH := 600.0
## Notes played within this many seconds of each other go in together with
## step input (a chord), on parts that play chords.
const CHORD_WINDOW := 0.08
const AUDITION_KEY := 1000

var _pos := 0
var _clip: Array = []
var _clip_span := 0
var _clip_drums := false
var _recorder: MidiRecorder
var _record_part := ""
var _count_in_left := 0.0
var _count_in_beats := 0
var _last_click_beat := -1
var _last_step_note := -1000.0
var _held_live: Dictionary = {}
var _compact := false
var _loading := false
## Selection to restore after an edit: "step:row" keys.
var _keep_selection: Dictionary = {}


func _ready() -> void:
	for layer in SongSettings.LAYERS:
		%PartPick.add_item(layer)
	for l in LENGTHS:
		%LengthPick.add_item(l[1])
	for g in GRIDS:
		%GridPick.add_item(g[1])
	%RecordMode.add_item("Add to notes")
	%RecordMode.add_item("Replace notes")
	%LengthPick.select(2)
	%GridPick.select(0)
	%Metronome.button_pressed = true
	%Help.text = "Tap with Draw to add notes, or play the keys. A part you edit is locked, so Regenerate keeps it; generating a new song replaces your edits (Undo brings them back)."

	%PartPick.item_selected.connect(func(_i: int) -> void: _on_part_changed())
	%LengthPick.item_selected.connect(func(i: int) -> void: %PianoRoll.draw_length = LENGTHS[i][0])
	%PianoRoll.draw_length = LENGTHS[2][0]
	var tools := ButtonGroup.new()
	for pair in [[%DrawTool, PianoRoll.Tool.DRAW], [%SelectTool, PianoRoll.Tool.SELECT], [%EraseTool, PianoRoll.Tool.ERASE]]:
		pair[0].button_group = tools
		pair[0].pressed.connect(func() -> void: %PianoRoll.tool = pair[1])
	%DrawTool.button_pressed = true
	%ZoomIn.pressed.connect(func() -> void: %PianoRoll.set_zoom(%PianoRoll.cell.x * 1.25))
	%ZoomOut.pressed.connect(func() -> void: %PianoRoll.set_zoom(%PianoRoll.cell.x / 1.25))
	%MakeUnique.pressed.connect(_on_make_unique)
	%Undo.pressed.connect(func() -> void: AppState.undo_edit())
	%Redo.pressed.connect(func() -> void: AppState.redo_edit())
	%PlaySection.pressed.connect(_play_section)
	%LoopSection.toggled.connect(func(_on: bool) -> void: _sync_loop(true))

	for pair in [[%SongToggle, %SongPanel], [%BarsToggle, %BarsPanel], [%LiveToggle, %LivePanel]]:
		pair[0].toggled.connect(func(on: bool) -> void: pair[1].visible = on)

	%AddSection.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		SongEdit.add_section(song, _pos + 1, _section_bars(song)), _pos + 1))
	%RepeatSection.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		SongEdit.repeat_section(song, _pos), _pos + 1))
	%CopySection.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		SongEdit.copy_section(song, _pos), _pos + 1))
	%RemoveSection.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		SongEdit.remove_at(song, _pos), maxi(_pos - 1, 0)))
	%MoveEarlier.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		SongEdit.move(song, _pos, -1), maxi(_pos - 1, 0)))
	%MoveLater.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		SongEdit.move(song, _pos, 1), _pos + 1))
	%SectionName.text_submitted.connect(func(text: String) -> void: _rename(text))
	%SectionName.focus_exited.connect(func() -> void: _rename(%SectionName.text))
	%Bars.value_changed.connect(_on_bars_changed)
	%LoopFrom.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		var loop := SongEdit.loop_positions(song)
		SongEdit.set_loop(song, _pos, maxi(loop.y, _pos)), _pos))
	%LoopTo.pressed.connect(func() -> void: _edit_structure(func(song: ChipSong) -> void:
		var loop := SongEdit.loop_positions(song)
		SongEdit.set_loop(song, mini(loop.x, _pos), _pos), _pos))
	%Tempo.value_changed.connect(func(v: float) -> void:
		if not _loading and AppState.song and absf(v - AppState.song.get_bpm()) >= 1.0:
			AppState.edit_song("", func(song: ChipSong) -> void: SongEdit.set_tempo(song, v)))
	%Swing.value_changed.connect(func(v: float) -> void:
		if not _loading and AppState.song:
			AppState.edit_song("", func(song: ChipSong) -> void: SongEdit.set_swing(song, v / 100.0)))
	%NewSong.pressed.connect(_on_new_song)

	%CopyBars.pressed.connect(_copy)
	%PasteBars.pressed.connect(_paste)
	%DuplicateBars.pressed.connect(_duplicate)
	%ClearBars.pressed.connect(_clear)
	%OctaveDown.pressed.connect(_transpose.bind(-12))
	%SemitoneDown.pressed.connect(_transpose.bind(-1))
	%SemitoneUp.pressed.connect(_transpose.bind(1))
	%OctaveUp.pressed.connect(_transpose.bind(12))
	%Quantize.pressed.connect(_quantize)
	%VelocityToggle.toggled.connect(func(on: bool) -> void: %PianoRoll.show_velocity = on)
	%VelocityToggle.button_pressed = true

	%PianoRoll.notes_edited.connect(_on_notes_edited)
	%PianoRoll.row_pressed.connect(_on_row_pressed)
	%PianoRoll.row_released.connect(func(_row: int) -> void: %LiveSynth.note_off(AUDITION_KEY))
	%PianoRoll.range_changed.connect(func(_a: int, _b: int) -> void: _sync_buttons())
	%PianoRoll.selection_changed.connect(func(_n: int) -> void: _sync_buttons())

	%Keys.key_down.connect(func(pitch: int) -> void: _live_on(pitch, 100))
	%Keys.key_up.connect(_live_off)
	%LiveInput.note_on.connect(_live_on)
	%LiveInput.note_off.connect(_live_off)
	%LiveInput.devices_changed.connect(_show_devices)
	%KeysDown.pressed.connect(_shift_keys.bind(-12))
	%KeysUp.pressed.connect(_shift_keys.bind(12))
	%Midi.pressed.connect(_on_midi_pressed)
	%Record.toggled.connect(_on_record_toggled)
	%FitTimer.timeout.connect(_update_fit)

	AppState.song_changed.connect(_on_song_changed)
	AppState.target_changed.connect(func(_t: String) -> void: _queue_fit())
	AudioService.playback_stopped.connect(func() -> void:
		if %Record.button_pressed and _count_in_beats <= 0:
			%Record.button_pressed = false)
	visibility_changed.connect(_on_visibility_changed)
	%LiveInput.enabled = is_visible_in_tree()
	resized.connect(_apply_layout)
	_apply_layout()
	if AppState.song:
		_on_song_changed(AppState.song)


func _on_visibility_changed() -> void:
	%LiveInput.enabled = is_visible_in_tree()
	if is_visible_in_tree():
		_sync_loop(false)
		_queue_fit()
	else:
		if %Record.button_pressed:
			%Record.button_pressed = false
		%LiveInput.release_keys()
		%LiveSynth.all_off()
		AudioService.loop_steps = Vector2i(-1, -1)


## Phone: start with only the roll and part row; wider: everything.
func _apply_layout() -> void:
	var compact := size.x > 0.0 and size.x < PHONE_WIDTH
	if compact == _compact and is_node_ready() and %SongToggle.button_pressed != %SongPanel.visible:
		return
	_compact = compact
	%SongToggle.button_pressed = not compact
	%BarsToggle.button_pressed = not compact
	%LiveToggle.button_pressed = true
	%SongPanel.visible = not compact
	%BarsPanel.visible = not compact
	%PianoRoll.cell = Vector2(26, 22) if compact else Vector2(22, 18)
	%Keys.custom_minimum_size.y = 120 if compact else 96
	$Scroll/Margin/Stack/TopRow/Title.visible = not compact
	%Help.visible = not compact
	%PianoRoll.custom_minimum_size.y = 360 if compact else 220
	%PlaySection.text = "Play" if compact else "Play section"
	%LoopSection.text = "Loop" if compact else "Loop section"


func set_playhead(step: float) -> void:
	%PianoRoll.playhead_step = _step_in_section(step)
	_highlight_playing(step)


func _process(delta: float) -> void:
	if _count_in_beats > 0:
		_count_in_left -= delta
		if _count_in_left <= 0.0:
			_count_in_beats -= 1
			if _count_in_beats > 0:
				%LiveSynth.click(_count_in_beats % AppState.song.get_beats_per_bar() == 0)
				_count_in_left += _beat_seconds()
			else:
				_start_recording_playback()
		return
	if not AudioService.is_playing() or AppState.song == null:
		_last_click_beat = -1
		return
	var step := _audible_step()
	if _recorder:
		_recorder.mark(step)
	if %Metronome.button_pressed and (_recorder != null or %LiveToggle.button_pressed):
		var spb := AppState.song.get_steps_per_beat()
		var beat := int(floorf(step / spb))
		if beat != _last_click_beat and step >= 0.0:
			if _last_click_beat >= 0 and (_recorder != null or not _held_live.is_empty() or %Record.button_pressed):
				%LiveSynth.click(beat % AppState.song.get_beats_per_bar() == 0)
			_last_click_beat = beat


# Song and view ---------------------------------------------------------------

func _on_song_changed(song: ChipSong) -> void:
	_loading = true
	var order: Array = song.data["order"]
	_pos = clampi(_pos, 0, maxi(order.size() - 1, 0))
	%Tempo.value = song.get_bpm()
	%Swing.value = float(song.data["timing"].get("swing", 0.0)) * 100.0
	_build_order(song)
	_loading = false
	_refresh()
	_sync_loop(false)
	_queue_fit()


func _build_order(song: ChipSong) -> void:
	for child in %Order.get_children():
		child.queue_free()
	var loop := SongEdit.loop_positions(song)
	var bar := SongEdit.bar_steps(song)
	var order: Array = song.data["order"]
	var group := ButtonGroup.new()
	for pos in order.size():
		var section: Dictionary = song.data["sections"][int(order[pos])]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = &"Chip"
		b.custom_minimum_size = Vector2(56, 40)
		var looped: bool = song.data["timing"].get("loop", true) and pos >= loop.x and pos <= loop.y
		b.text = "%s  %d" % [section["name"], int(section["length"]) / bar]
		b.tooltip_text = "Section %s, %d bars%s" % [section["name"], int(section["length"]) / bar, ", in the loop" if looped else ""]
		if looped:
			b.self_modulate = Color(1.0, 0.92, 0.75)
		b.button_pressed = pos == _pos
		b.pressed.connect(_select_pos.bind(pos))
		%Order.add_child(b)


func _select_pos(pos: int) -> void:
	_pos = pos
	%PianoRoll.set_range(-1, -1)
	_refresh()
	_sync_loop(false)


func _section() -> int:
	var order: Array = AppState.song.data["order"]
	return int(order[clampi(_pos, 0, order.size() - 1)])


func _section_bars(song: ChipSong) -> int:
	return maxi(int(song.data["sections"][_section()]["length"]) / SongEdit.bar_steps(song), 1)


func _part() -> String:
	return SongSettings.LAYERS[maxi(%PartPick.selected, 0)]


func _is_drums() -> bool:
	return _part() == "Drums"


func _channel() -> int:
	return int(SongGenerator.LAYER_CHANNELS[_part()][0])


func _channels() -> Array:
	return SongGenerator.LAYER_CHANNELS[_part()]


func _on_part_changed() -> void:
	%PianoRoll.clear_selection()
	_refresh()
	_centre_on_notes()
	%LiveSynth.all_off()


func _rows() -> Array:
	var rows: Array = []
	if _is_drums():
		for instrument in PatternEdit.DRUM_ROWS:
			rows.append({"label": PatternEdit.DRUM_NAMES[instrument], "black": false, "marked": false})
		return rows
	for pitch in range(TOP_PITCH, BOTTOM_PITCH - 1, -1):
		rows.append({"label": PatternEdit.note_name(pitch), "black": [1, 3, 6, 8, 10].has(pitch % 12), "marked": pitch % 12 == 0})
	return rows


func _row_of(note: Array) -> int:
	if _is_drums():
		return PatternEdit.DRUM_ROWS.find(int(note[4]) if note.size() > 4 else DrumWriter.TOM)
	return TOP_PITCH - int(note[2])


func _refresh() -> void:
	var song: ChipSong = AppState.song
	if song == null:
		return
	var section := _section()
	var info: Dictionary = song.data["sections"][section]
	var notes: Array = []
	for c in _channels():
		for n in PatternEdit.notes_at(song, section, int(c)):
			var row := _row_of(n)
			if row >= 0 and row < _rows().size():
				notes.append({"step": int(n[0]), "len": int(n[1]), "row": row, "vel": int(n[3]) if n.size() > 3 else 100, "src": n})
	var ghosts: Array = []
	if not _is_drums():
		for layer in ["Lead", "Harmony", "Arp", "Pad", "Bass"]:
			if layer == _part():
				continue
			for n in PatternEdit.notes_at(song, section, int(SongGenerator.LAYER_CHANNELS[layer][0])):
				ghosts.append({"step": int(n[0]), "len": int(n[1]), "row": TOP_PITCH - int(n[2])})
	var colour: Color = SongView.LANE_COLOURS[_channel() % SongView.LANE_COLOURS.size()]
	var timing: Dictionary = song.data["timing"]
	var roll: PianoRoll = %PianoRoll
	var first_time := roll.rows.is_empty() or roll.rows.size() != _rows().size()
	roll.ghost_notes = ghosts
	roll.set_view(_rows(), int(info["length"]), int(timing["steps_per_beat"]), int(timing["beats_per_bar"]), notes, colour)
	if not _keep_selection.is_empty():
		for i in notes.size():
			if _keep_selection.has("%d:%d" % [notes[i]["step"], notes[i]["row"]]):
				roll.selected[i] = true
		_keep_selection.clear()
		roll.queue_redraw()
	if first_time:
		_centre_on_notes()
	%Keys.pads = _drum_pads() if _is_drums() else []
	%Keys.colour = colour
	%KeysDown.disabled = _is_drums()
	%KeysUp.disabled = _is_drums()
	%SectionName.text = str(info["name"])
	_loading = true
	%Bars.value = int(info["length"]) / SongEdit.bar_steps(song)
	_loading = false
	var others := 0
	for c in _channels():
		others = maxi(others, PatternEdit.sharing(song, section, int(c)) - 1)
	%Shared.text = "Also in %d other section%s" % [others, "" if others == 1 else "s"] if others > 0 else ""
	%Shared.visible = others > 0
	%MakeUnique.visible = others > 0
	_sync_buttons()


func _sync_buttons() -> void:
	var song: ChipSong = AppState.song
	var roll: PianoRoll = %PianoRoll
	%Undo.disabled = not AppState.can_undo()
	%Redo.disabled = not AppState.can_redo()
	var count: int = song.data["order"].size() if song else 0
	%RemoveSection.disabled = count <= 1
	%MoveEarlier.disabled = _pos <= 0
	%MoveLater.disabled = _pos >= count - 1
	var has_target := not roll.selected.is_empty() or roll.range_from >= 0
	%PasteBars.disabled = _clip.is_empty()
	%DuplicateBars.disabled = not has_target
	for b in [%OctaveDown, %SemitoneDown, %SemitoneUp, %OctaveUp]:
		b.disabled = _is_drums()
	if not roll.selected.is_empty():
		%BarsLabel.text = "%d note%s:" % [roll.selected.size(), "" if roll.selected.size() == 1 else "s"]
	elif roll.range_from >= 0:
		var bar := roll.steps_per_beat * roll.beats_per_bar
		var a := roll.range_from / bar + 1
		var b := roll.range_to / bar
		%BarsLabel.text = "Bar %d:" % a if a == b else "Bars %d-%d:" % [a, b]
	else:
		%BarsLabel.text = "Whole section:"


func _centre_on_notes() -> void:
	var roll: PianoRoll = %PianoRoll
	if _is_drums():
		roll.centre_on_row(0)
		return
	var low := PatternEdit.default_low_pitch(AppState.song, _channel())
	roll.centre_on_row(TOP_PITCH - (low + 12))


func _drum_pads() -> Array:
	var pads: Array = []
	for instrument in [DrumWriter.KICK, DrumWriter.SNARE, DrumWriter.HAT, DrumWriter.OPEN_HAT, DrumWriter.TOM, DrumWriter.RIDE, DrumWriter.CRASH]:
		pads.append({"label": PatternEdit.DRUM_NAMES[instrument], "pitch": PatternEdit.DRUM_MIDI[instrument]})
	return pads


## The step within the section shown, or -1 when another one is playing.
func _step_in_section(step: float) -> float:
	var song: ChipSong = AppState.song
	if song == null or step < 0.0:
		return -1.0
	var at := SongEdit.locate(song, int(step))
	if at.x < 0 or int(song.data["order"][at.x]) != _section():
		return -1.0
	return at.y + (step - floorf(step))


func _highlight_playing(step: float) -> void:
	var song: ChipSong = AppState.song
	if song == null:
		return
	var at := SongEdit.locate(song, int(step)) if step >= 0.0 else Vector2i(-1, -1)
	var i := 0
	for child in %Order.get_children():
		if child is Button and not child.is_queued_for_deletion():
			child.modulate = Color(1.3, 1.3, 1.3) if i == at.x else Color.WHITE
			i += 1


# Notes -----------------------------------------------------------------------

## Writes the roll's notes back into the song.
func _on_notes_edited(list: Array) -> void:
	var song: ChipSong = AppState.song
	if song == null:
		return
	var section := _section()
	var by_channel := {}
	for c in _channels():
		by_channel[int(c)] = []
	for n in list:
		var src: Array = n["src"]
		var note: Array = src.duplicate(true) if src.size() >= 4 else [0, 1, 60, 100]
		note[0] = int(n["step"])
		note[1] = int(n["len"])
		note[3] = int(n["vel"])
		var channel := _channel()
		if _is_drums():
			var instrument: int = PatternEdit.DRUM_ROWS[int(n["row"])]
			channel = PatternEdit.drum_channel(instrument)
			note[2] = int(DrumWriter.PITCH[instrument])
			note[1] = 1
			if note.size() < 5:
				note.append(instrument)
			else:
				note[4] = instrument
		else:
			note[2] = TOP_PITCH - int(n["row"])
		by_channel[channel].append(note)
	_keep_selection.clear()
	for i in %PianoRoll.selected:
		if i < list.size():
			_keep_selection["%d:%d" % [list[i]["step"], list[i]["row"]]] = true
	AppState.edit_song(_part(), func(s: ChipSong) -> void:
		for c in by_channel:
			PatternEdit.set_notes(s, section, c, by_channel[c]))


func _on_row_pressed(row: int) -> void:
	_audition(row)


func _audition(row: int) -> void:
	var song: ChipSong = AppState.song
	if song == null:
		return
	if _is_drums():
		var instrument: int = PatternEdit.DRUM_ROWS[row]
		%LiveSynth.note_on(-1, float(DrumWriter.PITCH[instrument]), _instrument(instrument), 0.8, 0.25)
	else:
		%LiveSynth.note_on(AUDITION_KEY, float(TOP_PITCH - row), _instrument(int(song.data["channels"][_channel()]["instrument"])), 0.8)


func _instrument(index: int) -> Dictionary:
	var instruments: Array = AppState.song.data.get("instruments", [])
	return instruments[index] if index >= 0 and index < instruments.size() else {}


func _on_make_unique() -> void:
	var section := _section()
	var channels := _channels()
	AppState.edit_song(_part(), func(song: ChipSong) -> void:
		for c in channels:
			SongEdit.make_unique(song, section, int(c)))


# Bar tools -------------------------------------------------------------------

## The steps the bar tools work on: the picked bars, else the whole section.
func _span() -> Vector2i:
	var roll: PianoRoll = %PianoRoll
	if roll.range_from >= 0:
		return Vector2i(roll.range_from, roll.range_to)
	return Vector2i(0, roll.steps)


func _copy() -> void:
	var song: ChipSong = AppState.song
	var roll: PianoRoll = %PianoRoll
	if not roll.selected.is_empty():
		# Copy just the selected notes, from the beat the first one is in.
		var first := roll.steps
		var last := 0
		for i in roll.selected:
			first = mini(first, int(roll.notes[i]["step"]))
			last = maxi(last, int(roll.notes[i]["step"]) + int(roll.notes[i]["len"]))
		var beat := roll.steps_per_beat
		first = first / beat * beat
		_clip = []
		var sel: Array = roll.selected.keys()
		sel.sort()
		for i in sel:
			var src: Array = roll.notes[i]["src"]
			if src.is_empty():
				continue
			var note: Array = src.duplicate(true)
			note[0] = int(note[0]) - first
			var channel := PatternEdit.drum_channel(int(note[4])) if _is_drums() and note.size() > 4 else _channel()
			_clip.append([channel, note])
		_clip_span = int(ceilf(float(last - first) / beat)) * beat
	else:
		var span := _span()
		_clip = SongEdit.copy_steps(song, _section(), _channels(), span.x, span.y)
		_clip_span = span.y - span.x
	_clip_drums = _is_drums()
	_sync_buttons()


func _paste_at(at: int) -> void:
	if _clip.is_empty():
		return
	var clip: Array = _clip.duplicate(true)
	if _clip_drums != _is_drums():
		return
	if not _is_drums():
		for entry in clip:
			entry[0] = _channel()
	var section := _section()
	var span := _clip_span
	AppState.edit_song(_part(), func(song: ChipSong) -> void:
		SongEdit.paste_steps(song, section, clip, at, span))


func _paste() -> void:
	var roll: PianoRoll = %PianoRoll
	_paste_at(roll.range_from if roll.range_from >= 0 else roll.cursor_step)


func _duplicate() -> void:
	var roll: PianoRoll = %PianoRoll
	var keep_clip := _clip.duplicate(true)
	var keep_span := _clip_span
	var keep_drums := _clip_drums
	_copy()
	var at := 0
	if not roll.selected.is_empty():
		var first := roll.steps
		for i in roll.selected:
			first = mini(first, int(roll.notes[i]["step"]))
		at = first / roll.steps_per_beat * roll.steps_per_beat + _clip_span
	else:
		at = _span().y
	var from := _span()
	var range_moves := roll.range_from >= 0
	_paste_at(at)
	if range_moves and at < roll.steps:
		roll.set_range(at, mini(at + (from.y - from.x), roll.steps))
	_clip = keep_clip
	_clip_span = keep_span
	_clip_drums = keep_drums
	_sync_buttons()


func _clear() -> void:
	var roll: PianoRoll = %PianoRoll
	if not roll.selected.is_empty():
		roll.delete_notes(roll.selected.keys())
		return
	var span := _span()
	var section := _section()
	var channels := _channels()
	AppState.edit_song(_part(), func(song: ChipSong) -> void:
		SongEdit.clear_steps(song, section, channels, span.x, span.y))


func _transpose(semitones: int) -> void:
	if _is_drums():
		return
	var roll: PianoRoll = %PianoRoll
	if not roll.selected.is_empty():
		var rows := roll.rows.size()
		roll.change_notes(roll.selected.keys(), func(n: Dictionary) -> void:
			n["row"] = clampi(int(n["row"]) - semitones, 0, rows - 1))
		return
	var span := _span()
	var section := _section()
	var channel := _channel()
	AppState.edit_song(_part(), func(song: ChipSong) -> void:
		SongEdit.transpose_steps(song, section, channel, span.x, span.y, semitones))


func _grid() -> int:
	return GRIDS[maxi(%GridPick.selected, 0)][0]


func _quantize() -> void:
	var roll: PianoRoll = %PianoRoll
	var grid := _grid()
	if not roll.selected.is_empty():
		var steps := roll.steps
		roll.change_notes(roll.selected.keys(), func(n: Dictionary) -> void:
			n["step"] = clampi(int(roundf(float(n["step"]) / grid)) * grid, 0, steps - 1)
			n["len"] = maxi(int(roundf(float(n["len"]) / grid)) * grid, grid))
		return
	var span := _span()
	var section := _section()
	var channels := _channels()
	AppState.edit_song(_part(), func(song: ChipSong) -> void:
		for c in channels:
			SongEdit.quantize_steps(song, section, int(c), span.x, span.y, grid))


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is SpinBox:
		return
	if not (event.ctrl_pressed or event.meta_pressed):
		if event.keycode == KEY_SPACE:
			_play_section()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_Z:
			if event.shift_pressed:
				AppState.redo_edit()
			else:
				AppState.undo_edit()
		KEY_Y:
			AppState.redo_edit()
		KEY_C:
			_copy()
		KEY_V:
			_paste()
		KEY_D:
			_duplicate()
		_:
			return
	get_viewport().set_input_as_handled()


# Sections --------------------------------------------------------------------

## Changes the song's sections with [param change] and then shows order
## position [param select].
func _edit_structure(change: Callable, select: int) -> void:
	if AppState.song == null:
		return
	_pos = select
	AppState.edit_song("*", change)


func _rename(text: String) -> void:
	if _loading or AppState.song == null:
		return
	var section := _section()
	if text.strip_edges() == "" or text.strip_edges() == str(AppState.song.data["sections"][section]["name"]):
		return
	AppState.edit_song("", func(song: ChipSong) -> void: SongEdit.rename_section(song, section, text))


func _on_bars_changed(value: float) -> void:
	if _loading or AppState.song == null:
		return
	var section := _section()
	if int(value) == _section_bars(AppState.song):
		return
	AppState.edit_song("*", func(song: ChipSong) -> void: SongEdit.set_section_bars(song, section, int(value)))


func _on_new_song() -> void:
	if AppState.song == null:
		return
	_pos = 0
	%PartPick.select(0)
	AppState.edit_song("*", func(song: ChipSong) -> void:
		song.data = SongEdit.blank_song(song, 4).data)


func _section_range() -> Vector2i:
	var song: ChipSong = AppState.song
	var start := SongEdit.order_starts(song)[_pos]
	return Vector2i(start, start + int(song.data["sections"][_section()]["length"]))


func _sync_loop(restart: bool) -> void:
	if AppState.song == null:
		return
	var range := _section_range() if %LoopSection.button_pressed and is_visible_in_tree() else Vector2i(-1, -1)
	if range == AudioService.loop_steps:
		return
	AudioService.loop_steps = range
	if restart and AudioService.is_playing():
		var step := clampf(AudioService.music.get_position() / AppState.song.get_step_seconds(), 0.0, AppState.song.get_length_steps())
		if range.x >= 0 and (step < range.x or step >= range.y):
			step = range.x
		AudioService.play_song(AppState.song, step)


func _play_section() -> void:
	if AppState.song == null:
		return
	if AudioService.is_playing():
		AudioService.stop_song()
		return
	_sync_loop(false)
	AudioService.play_song(AppState.song, _section_range().x)


# Live playing and recording --------------------------------------------------

func _shift_keys(by: int) -> void:
	%Keys.base_pitch = clampi(%Keys.base_pitch + by, 12, 96)
	%LiveInput.base_pitch = %Keys.base_pitch


func _live_on(pitch: int, velocity: int) -> void:
	var song: ChipSong = AppState.song
	if song == null:
		return
	_held_live[pitch] = true
	%Keys.lit[pitch] = true
	%Keys.queue_redraw()
	if _is_drums():
		var instrument := PatternEdit.drum_for_midi(pitch)
		%LiveSynth.note_on(pitch, float(DrumWriter.PITCH[instrument]), _instrument(instrument), velocity / 127.0, 0.3)
	else:
		%LiveSynth.note_on(pitch, float(pitch), _instrument(int(song.data["channels"][_channel()]["instrument"])), velocity / 127.0)
	var row := PatternEdit.DRUM_ROWS.find(PatternEdit.drum_for_midi(pitch)) if _is_drums() else TOP_PITCH - pitch
	%PianoRoll.lit_rows[row] = true
	%PianoRoll.queue_redraw()
	if _recorder:
		_recorder.note_on(pitch, velocity, _audible_step())
	elif %StepInput.button_pressed and not AudioService.is_playing() and _count_in_beats <= 0:
		_step_input(pitch, velocity)


func _live_off(pitch: int) -> void:
	_held_live.erase(pitch)
	%Keys.lit.erase(pitch)
	%Keys.queue_redraw()
	%LiveSynth.note_off(pitch)
	var row := PatternEdit.DRUM_ROWS.find(PatternEdit.drum_for_midi(pitch)) if _is_drums() else TOP_PITCH - pitch
	%PianoRoll.lit_rows.erase(row)
	%PianoRoll.queue_redraw()
	if _recorder:
		_recorder.note_off(pitch, _audible_step())


## Step input: the note goes in at the cursor, which then moves on by the
## note length. Notes played together make a chord on parts that allow it.
func _step_input(pitch: int, velocity: int) -> void:
	var roll: PianoRoll = %PianoRoll
	var now := Time.get_ticks_msec() / 1000.0
	var chord := now - _last_step_note < CHORD_WINDOW and (_is_drums() or not PatternEdit.is_mono(AppState.song, _channel()))
	_last_step_note = now
	var length: int = LENGTHS[maxi(%LengthPick.selected, 0)][0]
	var at := roll.cursor_step
	if chord:
		at = maxi(at - length, 0)
	var section := _section()
	var channel := _channel()
	var note: Array
	if _is_drums():
		var instrument := PatternEdit.drum_for_midi(pitch)
		channel = PatternEdit.drum_channel(instrument)
		note = [at, 1, int(DrumWriter.PITCH[instrument]), velocity, instrument]
	else:
		note = [at, length, pitch, velocity]
	if not chord:
		roll.cursor_step = mini(at + length, roll.steps - 1) if at + length < roll.steps else 0
	AppState.edit_song(_part(), func(song: ChipSong) -> void:
		var notes := PatternEdit.notes_at(song, section, channel)
		notes.append(note)
		PatternEdit.set_notes(song, section, channel, notes))


func _beat_seconds() -> float:
	return 60.0 / AppState.song.get_bpm()


## The step being heard now: the player renders a little ahead of the
## speakers, so recorded notes land where they were heard.
func _audible_step() -> float:
	var song: ChipSong = AppState.song
	var music: ChipMusicPlayer = AudioService.music
	var latency := (maxf(music.buffer_length, 0.25) if OS.has_feature("web") else music.buffer_length) + AudioServer.get_output_latency()
	var seconds := music.get_position() - latency
	var step := seconds / song.get_step_seconds()
	var view: ChipSong = music.song if music.song else song
	var loop_start := float(view.get_loop_start_step())
	var loop_end := float(view.get_loop_end_step())
	if step < loop_start and music.get_position() / song.get_step_seconds() >= loop_start and _recorder and not _recorder.covered.is_empty():
		# Just looped: what is heard is still the end of the loop.
		step += loop_end - loop_start
	return maxf(step, 0.0)


func _on_record_toggled(on: bool) -> void:
	var song: ChipSong = AppState.song
	if song == null:
		return
	if on:
		_record_part = _part()
		if %CountIn.button_pressed and not AudioService.is_playing():
			_count_in_beats = song.get_beats_per_bar() + 1
			_count_in_left = 0.0
		else:
			_start_recording_playback()
		return
	# Stopping.
	_count_in_beats = 0
	if _recorder == null:
		return
	var recorder := _recorder
	_recorder = null
	recorder.finish(_audible_step() if AudioService.is_playing() else float(song.get_length_steps()))
	if AudioService.is_playing():
		AudioService.stop_song()
	if recorder.notes.is_empty():
		return
	var channel := -1 if _record_part == "Drums" else int(SongGenerator.LAYER_CHANNELS[_record_part][0])
	var grid := _grid()
	var replace: bool = %RecordMode.selected == 1
	AppState.edit_song(_record_part, func(s: ChipSong) -> void:
		recorder.commit(s, channel, grid, replace))


func _start_recording_playback() -> void:
	_count_in_beats = 0
	_recorder = MidiRecorder.new(AppState.song)
	for pitch in _held_live:
		_recorder.note_on(pitch, 100, 0.0)
	if not AudioService.is_playing():
		_sync_loop(false)
		AudioService.play_song(AppState.song, _section_range().x)


func _on_midi_pressed() -> void:
	if %LiveInput.midi_open:
		%LiveInput.close_midi()
	else:
		%LiveInput.open_midi()
		# Browsers fill the list in once the user allows MIDI.
		get_tree().create_timer(1.5).timeout.connect(func() -> void: _show_devices(%LiveInput.devices()))


func _show_devices(names: PackedStringArray) -> void:
	%Midi.text = "Disconnect MIDI" if %LiveInput.midi_open else "Connect MIDI"
	if not %LiveInput.midi_open:
		%MidiStatus.text = ""
	elif names.is_empty():
		%MidiStatus.text = "No MIDI devices found" if not OS.has_feature("mobile") else "MIDI is not available on phones: use the keys"
	else:
		%MidiStatus.text = ", ".join(names)


# Target fit ------------------------------------------------------------------

func _queue_fit() -> void:
	if is_node_ready() and is_visible_in_tree():
		%FitTimer.start()


## Says whether the song fits the target's channels, from the export report.
func _update_fit() -> void:
	var song: ChipSong = AppState.song
	if song == null or not is_visible_in_tree():
		return
	var report: Array[String] = TargetReport.lines(AppState.target, true, song, AppState.get_arranged_song(), {}, AppState.pc_card)
	var text := "[b]%s:[/b] " % _target_name()
	var shown: Array[String] = []
	for line in report:
		if line.strip_edges() != "" and shown.size() < 2:
			shown.append(line.strip_edges())
	text += "\n".join(shown)
	var crowded := _crowded_parts(song)
	if not crowded.is_empty():
		text += "\n[color=#f0a050]More notes at once than the channel plays:[/color] %s. The last ones cut off." % ", ".join(crowded)
	%Fit.text = text


func _target_name() -> String:
	var chip: Variant = AppState.catalog.chips.get(AppState.target) if AppState.catalog else null
	return str(chip.display_name) if chip else AppState.target.capitalize()


## Parts with more overlapping notes than their channel's polyphony.
static func _crowded_parts(song: ChipSong) -> PackedStringArray:
	var out := PackedStringArray()
	var channels: Array = song.data["channels"]
	for c in channels.size():
		var poly := int(channels[c].get("polyphony", 1))
		if poly <= 1:
			continue
		var worst := 0
		for s in song.data["sections"].size():
			var counts := {}
			for n in PatternEdit.notes_at(song, s, c):
				for step in range(int(n[0]), int(n[0]) + int(n[1])):
					counts[step] = int(counts.get(step, 0)) + 1
			for v in counts.values():
				worst = maxi(worst, int(v))
		if worst > poly:
			out.append("%s (%d of %d)" % [str(channels[c].get("name", c)), worst, poly])
	return out
