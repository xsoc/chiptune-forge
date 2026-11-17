extends Control
## Music mode, Layers screen: lock and regenerate layers, edit their notes,
## and set the levels of each layer in each adaptive state.

const LAYER_ROW := preload("res://scenes/components/layer_row.tscn")
const LEVELS: PackedStringArray = ["off", "low", "mid", "full"]
const LEVEL_TEXT := {"off": "Off", "low": "Low", "mid": "Mid", "full": "Full"}
## New note lengths in steps, with their names.
const LENGTHS := [[1, "1 step"], [2, "2 steps"], [4, "1 beat"], [8, "2 beats"], [16, "1 bar"]]
const VISIBLE_PITCHES := 24

var _rows: Dictionary = {}
## The pitch of the editor's bottom row, per tonal part.
var _low_pitch: Dictionary = {}


func _ready() -> void:
	for i in SongSettings.LAYERS.size():
		var layer: String = SongSettings.LAYERS[i]
		var row: LayerRow = LAYER_ROW.instantiate()
		%Rows.add_child(row)
		row.setup(layer, SongView.LANE_COLOURS[i], "")
		row.lock_toggled.connect(func(name: String, on: bool) -> void: AppState.set_layer_locked(name, on))
		row.regenerate_pressed.connect(func(name: String) -> void: AppState.regenerate_layer(name))
		row.mute_toggled.connect(_on_mute_toggled)
		row.engine_selected.connect(func(name: String, choice: String) -> void: AppState.set_layer_engine(name, choice))
		_rows[layer] = row
	%RegenerateAll.pressed.connect(func() -> void: AppState.regenerate_unlocked())
	%Preview.toggled.connect(_on_preview_toggled)
	%Intensity.value_changed.connect(_on_intensity_changed)
	AppState.song_changed.connect(_on_song_changed)
	AppState.adaptive_changed.connect(func() -> void: _build_grid(AppState.song))
	AppState.target_changed.connect(func(_t: String) -> void:
		if AppState.song:
			_update_budget())
	AppState.locks_changed.connect(_sync_locks)
	%AddState.pressed.connect(_on_add_state)
	%NewState.text_submitted.connect(func(_t: String) -> void: _on_add_state())
	%ResetAdaptive.pressed.connect(func() -> void: AppState.reset_adaptive())
	%AddRule.pressed.connect(func() -> void:
		AppState.edit_adaptive(func(_states: Array, rules: Array) -> void:
			rules.insert(0, {"from": "*", "to": "*", "when": "bar", "how": "crossfade"})))
	%Code.text = _code_sample("combat")
	for layer in SongSettings.LAYERS:
		%PartPick.add_item(layer)
	for l in LENGTHS:
		%LengthPick.add_item(l[1])
	%LengthPick.select(0)
	%SectionPick.item_selected.connect(func(_i: int) -> void: _refresh_editor())
	%PartPick.item_selected.connect(func(_i: int) -> void: _refresh_editor())
	%OctaveDown.pressed.connect(_shift_octave.bind(-12))
	%OctaveUp.pressed.connect(_shift_octave.bind(12))
	%Undo.pressed.connect(func() -> void: AppState.undo_edit())
	%PatternGrid.cell_pressed.connect(_on_note_cell)
	if AppState.song:
		_on_song_changed(AppState.song)


func set_playhead(step: float) -> void:
	%SongView.playhead_step = step
	%PatternGrid.playhead_step = _step_in_section(step)


func _on_song_changed(song: ChipSong) -> void:
	%SongView.set_song(song)
	var instruments: Array = song.data.get("instruments", [])
	for i in SongSettings.LAYERS.size():
		var layer: String = SongSettings.LAYERS[i]
		var inst: Dictionary = instruments[i] if i < instruments.size() else {}
		_rows[layer].setup(layer, SongView.LANE_COLOURS[i], _sound_text(layer, inst))
		_rows[layer].set_engine_choice(str(AppState.settings.layer_engines.get(layer, "")))
	_sync_locks()
	_build_grid(song)
	_fill_sections(song)
	_refresh_editor()


## What a layer sounds like, under its name.
static func _sound_text(layer: String, inst: Dictionary) -> String:
	var wave := str(inst.get("wave", ""))
	var engine := str(inst.get("engine", "chip"))
	if layer == "Drums":
		return "Sampled drums" if engine == "sampled" else "Triangle kick and noise"
	match engine:
		"analog":
			return "Analog %s, filtered" % ("pulse" if wave == "pulse" else "saw")
		"fm":
			return "FM, ratio %s" % str(inst.get("ratio", 1.0))
		"wavetable":
			return "Wavetable, %s bank" % str(inst.get("bank", "bright"))
		"sampled":
			return "Sampled %s" % str(inst.get("sample", "")).replace("epiano", "electric piano")
	if wave == "pulse":
		return "Pulse %d%%" % int(float(inst.get("duty", 0.5)) * 100.0)
	return wave.capitalize()


func _sync_locks() -> void:
	for layer in _rows:
		_rows[layer].set_locked(AppState.locked_layers.has(layer))


func _build_grid(song: ChipSong) -> void:
	for child in %Grid.get_children():
		child.queue_free()
	for child in %States.get_children():
		child.queue_free()
	var states: Array = song.data.get("states", [])
	%Grid.columns = states.size() + 1
	%Grid.add_child(Control.new())
	for state in states:
		var header := HBoxContainer.new()
		header.alignment = BoxContainer.ALIGNMENT_CENTER
		var title := Label.new()
		title.text = str(state["name"])
		title.theme_type_variation = &"SectionLabel"
		title.tooltip_text = "Begins at intensity %.2f" % float(state.get("min_intensity", 0.0))
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		header.add_child(title)
		if states.size() > 1:
			var remove := Button.new()
			remove.text = "×"
			remove.flat = true
			remove.tooltip_text = "Remove %s" % state["name"]
			remove.custom_minimum_size = Vector2(32, 32)
			remove.pressed.connect(_on_remove_state.bind(str(state["name"])))
			header.add_child(remove)
		%Grid.add_child(header)
		var button := Button.new()
		button.text = "Play %s" % state["name"]
		button.theme_type_variation = &"Chip"
		button.custom_minimum_size.y = 40
		button.pressed.connect(_on_state_pressed.bind(str(state["name"])))
		%States.add_child(button)
	for layer in SongSettings.LAYERS:
		var name_label := Label.new()
		name_label.text = layer
		%Grid.add_child(name_label)
		for s in states.size():
			var level := str(states[s]["levels"].get(layer, "full"))
			var cell := Button.new()
			cell.theme_type_variation = &"LevelButton"
			cell.custom_minimum_size = Vector2(64, 40)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_style_cell(cell, level)
			cell.pressed.connect(_on_cell_pressed.bind(cell, s, layer))
			%Grid.add_child(cell)
	_update_budget()
	_build_transitions(song)


func _style_cell(cell: Button, level: String) -> void:
	cell.text = LEVEL_TEXT.get(level, level)
	var strength := LEVELS.find(level) / 3.0
	cell.self_modulate = Color(1, 1, 1).lerp(Color("f5b942"), strength * 0.9)


func _on_cell_pressed(cell: Button, state_index: int, layer: String) -> void:
	var song: ChipSong = AppState.song
	var current := str(song.data["states"][state_index]["levels"].get(layer, "full"))
	var next := LEVELS[(LEVELS.find(current) + 1) % LEVELS.size()]
	AppState.edit_adaptive(func(states: Array, _rules: Array) -> void:
		states[state_index]["levels"][layer] = next)
	var music: ChipMusicPlayer = AudioService.music
	if music.adaptive and music.get_current_state() != "":
		music.set_state(music.get_current_state(), 0.5)


## Each state's voices against the chip's, with a warning when one is over.
func _update_budget() -> void:
	var parts := PackedStringArray()
	var over := PackedStringArray()
	for b in AppState.state_budgets():
		parts.append("%s %d" % [b["name"], b["voices"]])
		if int(b["limit"]) > 0 and int(b["voices"]) > int(b["limit"]):
			over.append(str(b["name"]))
	var budgets := AppState.state_budgets()
	var text := "Parts playing per state: " + ", ".join(parts) + "."
	if budgets.is_empty() or int(budgets[0]["limit"]) <= 0:
		text += " Modern chiptune has no voice limit."
	else:
		text = "Parts playing per state, against the chip's %d voices: %s." % [int(budgets[0]["limit"]), ", ".join(parts)]
	if not over.is_empty():
		text += " Over the limit in %s, so the arranger merges or drops parts there. Turn a layer Off to fit." % ", ".join(over)
	%Budget.text = text
	%Budget.theme_type_variation = &"WarningLabel" if not over.is_empty() else &"MutedLabel"


func _on_add_state() -> void:
	var name: String = %NewState.text.strip_edges()
	if name == "":
		name = "State %d" % (AppState.song.data.get("states", []).size() + 1)
	for state in AppState.song.data.get("states", []):
		if str(state["name"]).to_lower() == name.to_lower():
			%NewState.text = ""
			%NewState.placeholder_text = "%s already exists" % name
			return
	var from: float = %NewStateFrom.value
	AppState.edit_adaptive(func(states: Array, _rules: Array) -> void:
		var levels := {}
		for layer in SongSettings.LAYERS:
			levels[layer] = "full"
		if not states.is_empty():
			levels = states[states.size() - 1]["levels"].duplicate()
		states.append({"name": name, "min_intensity": from, "levels": levels}))
	%NewState.text = ""


func _on_remove_state(state_name: String) -> void:
	AppState.edit_adaptive(func(states: Array, rules: Array) -> void:
		for i in range(states.size() - 1, -1, -1):
			if str(states[i]["name"]) == state_name:
				states.remove_at(i)
		for i in range(rules.size() - 1, -1, -1):
			if str(rules[i].get("to", "")) == state_name or str(rules[i].get("from", "")) == state_name:
				rules.remove_at(i))


## One row per transition rule: from, to, when, how, the stinger, a preview
## and remove.
func _build_transitions(song: ChipSong) -> void:
	for child in %Transitions.get_children():
		child.queue_free()
	var names := PackedStringArray(["*"])
	for state in song.data.get("states", []):
		names.append(str(state["name"]))
	var stingers := PackedStringArray()
	for stinger in song.data.get("stingers", []):
		stingers.append(str(stinger["name"]))
	var rules: Array = song.data.get("transitions", [])
	for i in rules.size():
		var rule: Dictionary = rules[i]
		var row := HFlowContainer.new()
		row.add_child(_rule_pick(names, str(rule.get("from", "*")), i, "from", "Any state"))
		var arrow := Label.new()
		arrow.text = "to"
		row.add_child(arrow)
		row.add_child(_rule_pick(names, str(rule.get("to", "*")), i, "to", "Any state"))
		row.add_child(_rule_pick(SongGenerator.WHEN, str(rule.get("when", "beat")), i, "when", ""))
		row.add_child(_rule_pick(SongGenerator.HOW, str(rule.get("how", "crossfade")), i, "how", ""))
		if str(rule.get("how", "")) == "stinger":
			row.add_child(_rule_pick(stingers, str(rule.get("stinger", "rise")), i, "stinger", ""))
			var hear := Button.new()
			hear.text = "Hear"
			hear.tooltip_text = "Preview this stinger"
			hear.custom_minimum_size.y = 40
			hear.pressed.connect(func() -> void: AudioService.music.play_stinger(str(rule.get("stinger", "rise"))))
			row.add_child(hear)
		var remove := Button.new()
		remove.text = "×"
		remove.flat = true
		remove.tooltip_text = "Remove this route"
		remove.custom_minimum_size = Vector2(40, 40)
		remove.pressed.connect(func() -> void:
			AppState.edit_adaptive(func(_states: Array, r: Array) -> void: r.remove_at(i)))
		row.add_child(remove)
		%Transitions.add_child(row)


const RULE_TEXT := {"*": "Any state", "now": "Now", "beat": "Next beat", "bar": "Next bar", "phrase": "Next phrase",
	"crossfade": "Crossfade", "cut": "Cut", "stinger": "Stinger", "rise": "Rising stinger", "fall": "Falling stinger", "hit": "Hit stinger"}


func _rule_pick(options: PackedStringArray, current: String, index: int, key: String, _any: String) -> OptionButton:
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(0, 40)
	for option in options:
		pick.add_item(str(RULE_TEXT.get(option, option)))
		pick.set_item_metadata(pick.item_count - 1, option)
		if option == current:
			pick.selected = pick.item_count - 1
	pick.item_selected.connect(func(choice: int) -> void:
		var value := str(pick.get_item_metadata(choice))
		AppState.edit_adaptive(func(_states: Array, rules: Array) -> void:
			rules[index][key] = value
			if key == "how" and value == "stinger" and not rules[index].has("stinger"):
				rules[index]["stinger"] = "rise"))
	return pick


func _on_state_pressed(state: String) -> void:
	%Preview.button_pressed = true
	_ensure_playing()
	AudioService.music.set_state(state)
	var bands: Array = AppState.song.data.get("states", [])
	for b in bands:
		if b["name"] == state:
			%Intensity.set_value_silently(float(b["min_intensity"]))
	%Code.text = _code_sample(state.to_lower())


func _on_preview_toggled(on: bool) -> void:
	var music: ChipMusicPlayer = AudioService.music
	if on:
		_ensure_playing()
		music.adaptive = true
		music.intensity = %Intensity.value
		music.set_state(music.state_for_intensity(%Intensity.value))
	else:
		music.clear_state()


func _on_intensity_changed(value: float) -> void:
	if not %Preview.button_pressed:
		%Preview.button_pressed = true
	AudioService.music.intensity = value
	%Code.text = _code_sample(AudioService.music.get_current_state().to_lower(), value)


func _on_mute_toggled(layer: String, muted: bool) -> void:
	var channels: Array = SongGenerator.LAYER_CHANNELS[layer]
	for c in channels:
		AudioService.music.set_channel_muted(c, muted)
		%SongView.dimmed[c] = muted
	%SongView.queue_redraw()


func _ensure_playing() -> void:
	if not AudioService.is_playing() and AppState.song:
		AudioService.play_song(AppState.song)


func _code_sample(state: String, intensity := -1.0) -> String:
	var lines := [
		"# Godot: add a ChipMusicPlayer node and assign the song.",
		"$Music.play()",
		"$Music.set_state(\"%s\")" % (state if state != "" else "combat"),
	]
	if intensity >= 0.0:
		lines.append("$Music.intensity = %.2f" % intensity)
	else:
		lines.append("$Music.intensity = 0.72")
	lines.append("$Music.play_stinger(\"rise\")")
	lines.append("$Music.transition_to(\"B\", \"bar\")")
	return "\n".join(lines)


# Note editor -----------------------------------------------------------------

func _fill_sections(song: ChipSong) -> void:
	var sections: Array = song.data["sections"]
	var keep: int = %SectionPick.selected
	if %SectionPick.item_count != sections.size():
		_low_pitch.clear()
		keep = 0
	%SectionPick.clear()
	for s in sections.size():
		%SectionPick.add_item(str(sections[s]["name"]))
	%SectionPick.select(clampi(keep, 0, sections.size() - 1))


func _part() -> String:
	return SongSettings.LAYERS[maxi(%PartPick.selected, 0)]


func _is_drums() -> bool:
	return _part() == "Drums"


func _channel() -> int:
	return int(SongGenerator.LAYER_CHANNELS[_part()][0])


func _low() -> int:
	var part := _part()
	if not _low_pitch.has(part):
		_low_pitch[part] = PatternEdit.default_low_pitch(AppState.song, _channel())
	return int(_low_pitch[part])


func _refresh_editor() -> void:
	var song: ChipSong = AppState.song
	var section: int = %SectionPick.selected
	%OctaveDown.disabled = _is_drums()
	%OctaveUp.disabled = _is_drums()
	%Undo.disabled = not AppState.can_undo()
	if song == null or section < 0:
		%PatternGrid.set_view(PackedStringArray(), 16, 4, 4, [], Color.WHITE)
		%Shared.visible = false
		return
	var info: Dictionary = song.data["sections"][section]
	var timing: Dictionary = song.data["timing"]
	var colour: Color = SongView.LANE_COLOURS[_channel()]
	var labels := PackedStringArray()
	var marked := PackedInt32Array()
	var rows: Array = []
	if _is_drums():
		for instrument in PatternEdit.DRUM_ROWS:
			labels.append(PatternEdit.DRUM_NAMES[instrument])
		for channel in SongGenerator.LAYER_CHANNELS["Drums"]:
			for n in PatternEdit.notes_at(song, section, channel):
				var row := PatternEdit.DRUM_ROWS.find(int(n[4]) if n.size() > 4 else DrumWriter.TOM)
				if row >= 0:
					rows.append([int(n[0]), int(n[1]), row])
	else:
		var low := _low()
		for r in VISIBLE_PITCHES:
			var pitch := low + VISIBLE_PITCHES - 1 - r
			labels.append(PatternEdit.note_name(pitch))
			if pitch % 12 == 0:
				marked.append(r)
		for n in PatternEdit.notes_at(song, section, _channel()):
			var row := low + VISIBLE_PITCHES - 1 - int(n[2])
			if row >= 0 and row < VISIBLE_PITCHES:
				rows.append([int(n[0]), int(n[1]), row])
	%PatternGrid.set_view(labels, int(info["length"]), int(timing["steps_per_beat"]), int(timing["beats_per_bar"]), rows, colour, marked)
	var others := PatternEdit.sharing(song, section, _channel()) - 1
	if others > 0:
		%Shared.text = "These notes also play in %d other section%s with the same part." % [others, "" if others == 1 else "s"]
	else:
		%Shared.text = ""
	%Shared.visible = others > 0


func _shift_octave(by: int) -> void:
	_low_pitch[_part()] = clampi(_low() + by, 12, 108 - VISIBLE_PITCHES)
	_refresh_editor()


func _on_note_cell(step: int, row: int) -> void:
	var section: int = %SectionPick.selected
	if AppState.song == null or section < 0:
		return
	var length: int = LENGTHS[maxi(%LengthPick.selected, 0)][0]
	if _is_drums():
		var instrument := PatternEdit.DRUM_ROWS[row]
		AppState.edit_song("Drums", func(song: ChipSong) -> void:
			PatternEdit.toggle(song, section, 0, step, 0, 1, instrument))
	else:
		var pitch := _low() + VISIBLE_PITCHES - 1 - row
		var channel := _channel()
		AppState.edit_song(_part(), func(song: ChipSong) -> void:
			PatternEdit.toggle(song, section, channel, step, pitch, length))


## The step within the section shown in the editor, or -1 when another
## section is playing.
func _step_in_section(step: float) -> float:
	var song: ChipSong = AppState.song
	if song == null or step < 0.0:
		return -1.0
	var start := 0.0
	for index in song.data["order"]:
		var length := float(song.data["sections"][int(index)]["length"])
		if step < start + length:
			return step - start if int(index) == %SectionPick.selected else -1.0
		start += length
	return -1.0
