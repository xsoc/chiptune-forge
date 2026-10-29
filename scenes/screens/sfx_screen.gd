extends Control
## Sound FX mode, Create screen: presets, the current sound and its sliders.

const SLIDER_ROW := preload("res://scenes/components/slider_row.tscn")

## Simple sliders: key, label, min, max, step, format.
const SIMPLE := [
	["pitch", "Pitch", -1.0, 1.0, 0.01, "%.2f"],
	["length", "Length", 0.25, 2.0, 0.01, "%.2fx"],
	["slide", "Slide", -1.0, 1.0, 0.01, "%.2f"],
	["punch", "Punch", -0.01, 1.0, 0.01, "%.2f"],
	["wobble", "Wobble", 0.0, 1.0, 0.01, "%.2f"],
	["crunch", "Crunch", 0.0, 1.0, 0.01, "%.2f"],
	["steps", "Steps", 0.0, 1.0, 0.01, "%.2f"],
	["echo", "Echo", 0.0, 1.0, 0.01, "%.2f"],
]

## Advanced sliders: synth parameter, label, min, max.
const ADVANCED := [
	["attack", "Attack", 0.0, 1.0], ["sustain", "Sustain", 0.0, 1.0], ["punch", "Punch", 0.0, 1.0],
	["decay", "Decay", 0.0, 1.0], ["base_freq", "Start pitch", 0.0, 1.0], ["freq_limit", "Pitch floor", 0.0, 1.0],
	["freq_ramp", "Slide", -1.0, 1.0], ["freq_dramp", "Slide change", -1.0, 1.0],
	["vib_strength", "Vibrato depth", 0.0, 1.0], ["vib_speed", "Vibrato speed", 0.0, 1.0],
	["arp_mod", "Jump amount", -1.0, 1.0], ["arp_speed", "Jump time", 0.0, 1.0],
	["duty", "Duty", 0.0, 1.0], ["duty_ramp", "Duty sweep", -1.0, 1.0], ["repeat_speed", "Repeat", 0.0, 1.0],
	["pha_offset", "Phaser", -1.0, 1.0], ["pha_ramp", "Phaser sweep", -1.0, 1.0],
	["lpf_freq", "Low-pass", 0.0, 1.0], ["lpf_ramp", "Low-pass sweep", -1.0, 1.0], ["lpf_resonance", "Resonance", 0.0, 1.0],
	["hpf_freq", "High-pass", 0.0, 1.0], ["hpf_ramp", "High-pass sweep", -1.0, 1.0],
	["crush", "Crunch", 0.0, 1.0], ["echo", "Echo", 0.0, 1.0], ["volume", "Volume", 0.0, 1.0],
]

var _simple_rows: Dictionary = {}
var _advanced_rows: Dictionary = {}
var _syncing := false
## Slider edits wait for a short pause before the sound is rebuilt.
var _pending := ""


func _ready() -> void:
	var catalog: Catalog = AppState.catalog
	%PresetPicker.setup(catalog, catalog.sfx_presets, Catalog.SFX_GROUPS)
	%PresetPicker.selection_changed.connect(func(ids: PackedStringArray) -> void: AppState.select_sfx_preset(ids[0]))
	%Play.pressed.connect(_play)
	%NewVariation.pressed.connect(func() -> void: AppState.roll_sfx())
	%Mutate.pressed.connect(func() -> void: AppState.mutate_sfx())
	%Surprise.pressed.connect(func() -> void: AppState.surprise_sfx())
	%AddToKit.pressed.connect(_on_add_to_kit)
	%Save.pressed.connect(func() -> void:
		AppState.save_sfx_to_library()
		_flash(%Save, "Saved", "Save to library"))
	%Tabs.tab_changed.connect(func(tab: int) -> void:
		%Simple.visible = tab == 0
		%Advanced.visible = tab == 1)
	%Reset.pressed.connect(func() -> void: AppState.reset_sfx_tweaks())
	%Replay.timeout.connect(_apply_pending)

	for spec in SIMPLE:
		var row: SliderRow = SLIDER_ROW.instantiate()
		row.label_text = spec[1]
		row.min_value = spec[2]
		row.max_value = spec[3]
		row.step = spec[4]
		row.value_format = spec[5]
		row.sfx_style = true
		row.value = float(SfxGenerator.TWEAK_DEFAULTS[spec[0]])
		%Simple.add_child(row)
		%Simple.move_child(row, %Simple.get_child_count() - 2)
		row.value_changed.connect(_on_simple_changed.bind(spec[0]))
		_simple_rows[spec[0]] = row
	for wave in ChipSfxSynth.WAVES:
		%Wave.add_item(wave.replace("_", " ").capitalize())
		%Wave.set_item_metadata(%Wave.item_count - 1, wave)
	%Wave.item_selected.connect(func(_i: int) -> void: _on_advanced_changed(0.0, "wave"))
	for spec in ADVANCED:
		var row: SliderRow = SLIDER_ROW.instantiate()
		row.label_text = spec[1]
		row.min_value = spec[2]
		row.max_value = spec[3]
		row.step = 0.01
		row.value_format = "%.2f"
		row.sfx_style = true
		%Advanced.add_child(row)
		row.value_changed.connect(_on_advanced_changed.bind(spec[0]))
		_advanced_rows[spec[0]] = row

	AppState.sfx_changed.connect(_on_sfx_changed)
	AppState.kit_changed.connect(_update_kit_button)
	if AppState.sfx == null:
		AppState.select_sfx_preset(AppState.sfx_preset_id)
	else:
		_on_sfx_changed(AppState.sfx)


func _play() -> void:
	AudioService.play_sfx(AppState.sfx)


func _on_sfx_changed(sfx: ChipSfx) -> void:
	_syncing = true
	var preset := AppState.get_sfx_preset()
	%Name.text = sfx.get_sound_name()
	%PresetPicker.set_selected(PackedStringArray([AppState.sfx_preset_id]))
	var kind := preset.description.get_slice(": ", 1) if preset else "custom"
	var variant := str(sfx.data.get("meta", {}).get("variant", ""))
	if not variant.is_empty() and variant != "Classic":
		kind += " (%s)" % variant.to_lower()
	%Note.text = "%s · %s. Modern chiptune plays it on any voice, with no limits." % [SfxGenerator.c_id(sfx.get_sound_name()), kind]
	%Waveform.set_samples(sfx.render(22050), 22050)
	var params := ChipSfxSynth.with_defaults(sfx.data.get("params", {}))
	for key in _advanced_rows:
		_advanced_rows[key].set_value_silently(float(params[key]))
	%Wave.selected = maxi(ChipSfxSynth.WAVES.find(str(params["wave"])), 0)
	for key in _simple_rows:
		_simple_rows[key].set_value_silently(float(AppState.sfx_tweaks.get(key, SfxGenerator.TWEAK_DEFAULTS[key])))
	_rebuild_recent()
	_syncing = false
	_play()


func _rebuild_recent() -> void:
	for child in %Recent.get_children():
		child.queue_free()
	for i in AppState.sfx_recent.size():
		var entry: Dictionary = AppState.sfx_recent[i]
		var preset: SfxPreset = AppState.catalog.get_sfx_preset(entry["preset"])
		var chip := Button.new()
		chip.text = "#%d %s" % [i + 1, preset.display_name if preset else entry["preset"]]
		chip.theme_type_variation = &"SfxChip"
		chip.tooltip_text = "Seed %d" % entry["seed"]
		chip.pressed.connect(func() -> void: AppState.recall_recent(i))
		%Recent.add_child(chip)


func _on_simple_changed(value: float, key: String) -> void:
	if _syncing:
		return
	AppState.sfx_tweaks[key] = value
	_pending = "simple"
	%Replay.start()


func _on_advanced_changed(_value: float, _key: String) -> void:
	if _syncing or AppState.sfx == null:
		return
	_pending = "advanced"
	%Replay.start()


func _apply_pending() -> void:
	if _pending == "simple":
		AppState.set_sfx_tweak("pitch", float(AppState.sfx_tweaks["pitch"]))
	elif _pending == "advanced":
		_apply_advanced()
	_pending = ""


func _apply_advanced() -> void:
	var params: Dictionary = AppState.sfx.data["params"].duplicate()
	for key in _advanced_rows:
		params[key] = _advanced_rows[key].value
	params["wave"] = str(%Wave.get_item_metadata(%Wave.selected))
	AppState.set_sfx_params(params)


func _on_add_to_kit() -> void:
	var id := AppState.add_sfx_to_kit()
	if id != "":
		_flash(%AddToKit, "Added as %s" % id, "Add to kit")


func _update_kit_button() -> void:
	%AddToKit.tooltip_text = "%d sounds in the kit" % AppState.kit.sounds.size()


func _flash(button: Button, text: String, back: String) -> void:
	button.text = text
	get_tree().create_timer(1.5).timeout.connect(func() -> void: button.text = back)
