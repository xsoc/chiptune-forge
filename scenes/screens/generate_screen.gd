extends Control
## Music mode, Generate screen: vibe and style pickers, the sliders, and the
## song card with the seed and the Generate buttons.
##
## Every change regenerates the song with the same seed after a short pause,
## so tweaking a slider changes the song in place. "Generate new song" rolls a
## new seed.

signal seek_requested(step: float)

const LENGTHS := [30, 60, 90, 120, 300, 600, 900]

var _loading := false


func _ready() -> void:
	var catalog: Catalog = AppState.catalog
	%VibePicker.setup(catalog, catalog.vibes, Catalog.VIBE_GROUPS)
	%StylePicker.setup(catalog, catalog.styles, Catalog.STYLE_GROUPS)
	_fill_options()

	%VibePicker.selection_changed.connect(func(_ids: PackedStringArray) -> void: _on_changed())
	%VibePicker.strengths_changed.connect(func(_s: Array[float]) -> void: _on_changed())
	%StylePicker.selection_changed.connect(func(_ids: PackedStringArray) -> void: _on_changed())
	for row in [%Intensity, %Complexity, %Tempo]:
		row.value_changed.connect(func(_v: float) -> void: _on_changed())
	%AutoKeyTempo.toggled.connect(func(_on: bool) -> void: _on_changed())
	for option in [%Key, %Mode, %Form, %Energy]:
		option.item_selected.connect(func(_i: int) -> void: _on_changed())
	for check in [%Intro, %Loop, %Outro]:
		check.toggled.connect(func(_on: bool) -> void: _on_changed())
	%CustomLength.value_changed.connect(func(_v: float) -> void: _on_length_changed())
	%Debounce.timeout.connect(func() -> void: AppState.generate())
	%SeedField.seed_submitted.connect(_on_seed_submitted)
	%SeedField.dice_pressed.connect(_on_generate_new)
	%Generate.pressed.connect(_on_generate_new)
	%Regenerate.pressed.connect(func() -> void: AppState.regenerate_unlocked())
	%Save.pressed.connect(_on_save)
	%SongView.seek_requested.connect(func(step: float) -> void: seek_requested.emit(step))

	AppState.song_changed.connect(_on_song_changed)
	AppState.settings_changed.connect(_load_settings)
	_load_settings()
	if AppState.song:
		_on_song_changed(AppState.song)


func set_playhead(step: float) -> void:
	%SongView.playhead_step = step


func _fill_options() -> void:
	%Key.clear()
	%Key.add_item("Key: auto")
	for i in 12:
		%Key.add_item(MusicTheory.NOTE_NAMES[i])
	%Mode.clear()
	%Mode.add_item("Mode: auto")
	for mode in MusicTheory.MODE_NAMES:
		%Mode.add_item(MusicTheory.mode_label(mode))
		%Mode.set_item_metadata(%Mode.item_count - 1, mode)
	%Form.clear()
	var form_names := {"auto": "Form: style picks", "loop": "Loop (A A)", "verse_chorus": "Verse-chorus", "aaba": "AABA",
		"rondo": "Rondo (A B A C A)", "through": "Through-composed", "build": "Build", "boss": "Boss (two phases)", "jingle": "Jingle (stinger)"}
	for form in SongSettings.FORMS:
		%Form.add_item(form_names.get(form, form))
		%Form.set_item_metadata(%Form.item_count - 1, form)
	%Energy.clear()
	var curve_names := {"flat": "Energy: flat", "build": "Energy: build", "wave": "Energy: wave", "peak_drop": "Energy: peak and drop"}
	for curve in SongSettings.ENERGY_CURVES:
		%Energy.add_item(curve_names[curve])
		%Energy.set_item_metadata(%Energy.item_count - 1, curve)
	for seconds in LENGTHS:
		var chip := Button.new()
		chip.text = "%d:%02d" % [seconds / 60, seconds % 60]
		chip.toggle_mode = true
		chip.theme_type_variation = &"Chip"
		chip.custom_minimum_size.y = 40
		chip.set_meta("seconds", seconds)
		chip.pressed.connect(_on_length_chip.bind(seconds))
		%Lengths.add_child(chip)
		%Lengths.move_child(chip, %Lengths.get_child_count() - 2)


func _load_settings() -> void:
	_loading = true
	var s: SongSettings = AppState.settings
	var vibe_ids := PackedStringArray(s.vibes)
	%VibePicker.set_selected(vibe_ids, s.vibe_strengths)
	%StylePicker.set_selected(PackedStringArray([s.style]))
	%Intensity.value = s.intensity
	%Complexity.value = s.complexity
	var auto := s.tempo <= 0 and s.key < 0
	%AutoKeyTempo.button_pressed = auto
	if s.tempo > 0:
		%Tempo.value = s.tempo
	%Key.selected = s.key + 1 if s.key >= 0 else 0
	%Mode.selected = 0
	for i in %Mode.item_count:
		if %Mode.get_item_metadata(i) == s.mode:
			%Mode.selected = i
	%Form.selected = maxi(SongSettings.FORMS.find(s.form), 0)
	%Energy.selected = maxi(SongSettings.ENERGY_CURVES.find(s.energy_curve), 0)
	%Intro.button_pressed = s.intro
	%Loop.button_pressed = s.loop
	%Outro.button_pressed = s.outro
	%CustomLength.set_value_no_signal(s.length_seconds)
	_sync_length_chips(s.length_seconds)
	%SeedField.set_seed_text(s.seed_text)
	_update_enabled()
	_loading = false


func _store_settings() -> void:
	var s: SongSettings = AppState.settings
	s.vibes.assign(%VibePicker.get_selected())
	s.vibe_strengths.assign(%VibePicker.get_strengths())
	var styles: PackedStringArray = %StylePicker.get_selected()
	if not styles.is_empty():
		s.style = styles[0]
	s.intensity = %Intensity.value
	s.complexity = %Complexity.value
	var auto: bool = %AutoKeyTempo.button_pressed
	s.tempo = 0 if auto else int(%Tempo.value)
	s.key = -1 if auto or %Key.selected <= 0 else %Key.selected - 1
	s.mode = "" if %Mode.selected <= 0 else str(%Mode.get_item_metadata(%Mode.selected))
	s.form = str(%Form.get_item_metadata(%Form.selected))
	s.energy_curve = str(%Energy.get_item_metadata(%Energy.selected))
	s.intro = %Intro.button_pressed
	s.loop = %Loop.button_pressed
	s.outro = %Outro.button_pressed
	s.length_seconds = %CustomLength.value


func _update_enabled() -> void:
	var auto: bool = %AutoKeyTempo.button_pressed
	%Tempo.modulate.a = 0.45 if auto else 1.0
	%Tempo.get_node("Slider").editable = not auto
	%Key.disabled = auto
	var no_vibe := not AppState.can_make_music()
	for button in [%Generate, %Regenerate, %Save]:
		button.disabled = no_vibe
	%SeedField.set_dice_disabled(no_vibe)
	%SongView.modulate.a = 0.45 if no_vibe else 1.0


func _on_changed() -> void:
	if _loading:
		return
	_store_settings()
	_update_enabled()
	AppState.notify_settings_changed()
	%Debounce.start()


func _on_length_chip(seconds: int) -> void:
	%CustomLength.set_value_no_signal(seconds)
	_sync_length_chips(seconds)
	_on_changed()


func _on_length_changed() -> void:
	_sync_length_chips(%CustomLength.value)
	_on_changed()


func _sync_length_chips(seconds: float) -> void:
	for chip in %Lengths.get_children():
		if chip is Button:
			chip.set_pressed_no_signal(int(chip.get_meta("seconds")) == int(seconds))


func _on_seed_submitted(text: String) -> void:
	if text.strip_edges() == "" or text == AppState.settings.seed_text:
		return
	AppState.settings.seed_text = text.strip_edges()
	AppState.settings.variations.clear()
	AppState.generate()


func _on_generate_new() -> void:
	_store_settings()
	AppState.generate_new_song()
	%SeedField.set_seed_text(AppState.settings.seed_text)


func _on_save() -> void:
	AppState.save_song_to_library()
	%Save.text = "Saved"
	get_tree().create_timer(1.5).timeout.connect(func() -> void: %Save.text = "Save to library")


func _on_song_changed(song: ChipSong) -> void:
	%Title.text = song.get_title()
	var meta: Dictionary = song.data["meta"]
	var seconds := int(song.get_length_seconds())
	%Info.text = "%s · %d BPM · %d:%02d · %s" % [meta.get("key", ""), int(song.get_bpm()), seconds / 60, seconds % 60, str(meta.get("form", "")).replace("_", " ")]
	%SongView.set_song(song)
	%SeedField.set_seed_text(AppState.settings.seed_text)
	if %AutoKeyTempo.button_pressed:
		%Tempo.set_value_silently(song.get_bpm())
	_update_hint()


## Shows a gentle note when the vibe and style pull in different directions.
func _update_hint() -> void:
	var s: SongSettings = AppState.settings
	var vibe: Vibe = AppState.catalog.get_vibe(s.vibes[0]) if not s.vibes.is_empty() else null
	var style: Style = AppState.catalog.get_style(s.style)
	var text := ""
	if vibe and style:
		if vibe.tempo_max < style.tempo_min - 10 or vibe.tempo_min > style.tempo_max + 10:
			text = "Unusual combo: %s and %s want different tempos, so they meet in the middle." % [vibe.display_name, style.display_name]
		elif vibe.energy < 0.3 and style.drum_density > 0.75:
			text = "Unusual combo: a calm vibe with a busy style. Try lowering Intensity."
	%Hint.text = text
	%Hint.visible = text != ""
