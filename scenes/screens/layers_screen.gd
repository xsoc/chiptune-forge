extends Control
## Music mode, Layers screen: lock and regenerate layers, and set the levels
## of each layer in each adaptive state.

const LAYER_ROW := preload("res://scenes/components/layer_row.tscn")
const LEVELS: PackedStringArray = ["off", "low", "mid", "full"]
const LEVEL_TEXT := {"off": "Off", "low": "Low", "mid": "Mid", "full": "Full"}

var _rows: Dictionary = {}


func _ready() -> void:
	for i in SongSettings.LAYERS.size():
		var layer: String = SongSettings.LAYERS[i]
		var row: LayerRow = LAYER_ROW.instantiate()
		%Rows.add_child(row)
		row.setup(layer, SongView.LANE_COLOURS[i], "")
		row.lock_toggled.connect(func(name: String, on: bool) -> void: AppState.set_layer_locked(name, on))
		row.regenerate_pressed.connect(func(name: String) -> void: AppState.regenerate_layer(name))
		row.mute_toggled.connect(_on_mute_toggled)
		_rows[layer] = row
	%RegenerateAll.pressed.connect(func() -> void: AppState.regenerate_unlocked())
	%Preview.toggled.connect(_on_preview_toggled)
	%Intensity.value_changed.connect(_on_intensity_changed)
	AppState.song_changed.connect(_on_song_changed)
	AppState.locks_changed.connect(_sync_locks)
	%Code.text = _code_sample("combat")
	if AppState.song:
		_on_song_changed(AppState.song)


func set_playhead(step: float) -> void:
	%SongView.playhead_step = step


func _on_song_changed(song: ChipSong) -> void:
	%SongView.set_song(song)
	var instruments: Array = song.data.get("instruments", [])
	for i in SongSettings.LAYERS.size():
		var layer: String = SongSettings.LAYERS[i]
		var inst: Dictionary = instruments[i] if i < instruments.size() else {}
		var wave := str(inst.get("wave", ""))
		var text := wave.capitalize()
		if wave == "pulse":
			text = "Pulse %d%%" % int(float(inst.get("duty", 0.5)) * 100.0)
		if layer == "Drums":
			text = "Triangle kick and noise"
		_rows[layer].setup(layer, SongView.LANE_COLOURS[i], text)
	_sync_locks()
	_build_grid(song)


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
		var header := Label.new()
		header.text = str(state["name"])
		header.theme_type_variation = &"SectionLabel"
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


func _style_cell(cell: Button, level: String) -> void:
	cell.text = LEVEL_TEXT.get(level, level)
	var strength := LEVELS.find(level) / 3.0
	cell.self_modulate = Color(1, 1, 1).lerp(Color("f5b942"), strength * 0.9)


func _on_cell_pressed(cell: Button, state_index: int, layer: String) -> void:
	var song: ChipSong = AppState.song
	var levels: Dictionary = song.data["states"][state_index]["levels"]
	var current := str(levels.get(layer, "full"))
	var next := LEVELS[(LEVELS.find(current) + 1) % LEVELS.size()]
	levels[layer] = next
	_style_cell(cell, next)
	var music: ChipMusicPlayer = AudioService.music
	if music.adaptive and music.get_current_state() != "":
		music.set_state(music.get_current_state(), 0.5)


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
	lines.append("$Music.transition_to(\"B\", \"bar\")")
	return "\n".join(lines)
