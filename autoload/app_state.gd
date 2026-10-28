extends Node
## Current settings, song, sound effects and library. Screens read from here
## and call its methods; it emits signals when things change.

signal song_changed(song: ChipSong)
signal settings_changed
signal locks_changed
signal sfx_changed(sfx: ChipSfx)
signal kit_changed
signal library_changed
signal mode_changed(mode: String)

const LIBRARY_PATH := "user://library.json"
const MAX_RECENT := 8

var catalog: Catalog
var mode := "music":
	set(value):
		if mode != value:
			mode = value
			mode_changed.emit(value)

var settings := SongSettings.new()
var song: ChipSong
var locked_layers := PackedStringArray()

var sfx_preset_id := "coin"
var sfx_seed := 1
var sfx_tweaks: Dictionary = SfxGenerator.TWEAK_DEFAULTS.duplicate()
var sfx: ChipSfx
## Recent variations: Array of {preset, seed}.
var sfx_recent: Array = []
var kit := ChipSfxKit.new()

## Saved entries: {kind, name, favourite, created, settings | sfx}.
var library: Array = []


func _ready() -> void:
	catalog = Catalog.get_default()
	kit.kit_name = "My kit"
	_load_library()
	settings.seed_text = str(_fresh_seed())


## Rolls a new seed and generates a new song from the current settings.
func generate_new_song() -> void:
	settings.seed_text = str(_fresh_seed())
	settings.variations.clear()
	generate()


## Generates from the current settings and seed.
func generate() -> void:
	song = SongGenerator.generate(settings, catalog)
	song_changed.emit(song)


## Gives every unlocked layer a new variation and keeps the locked ones.
func regenerate_unlocked() -> void:
	if song == null:
		generate()
		return
	for layer in SongSettings.LAYERS:
		if not locked_layers.has(layer):
			settings.variations[layer] = settings.get_variation(layer) + 1
	song = SongGenerator.generate(settings, catalog, song, locked_layers)
	song_changed.emit(song)


## Regenerates a single layer, keeping every other layer as it is.
func regenerate_layer(layer: String) -> void:
	if song == null:
		return
	settings.variations[layer] = settings.get_variation(layer) + 1
	var keep := PackedStringArray()
	for other in SongSettings.LAYERS:
		if other != layer:
			keep.append(other)
	song = SongGenerator.generate(settings, catalog, song, keep)
	song_changed.emit(song)


func set_layer_locked(layer: String, locked: bool) -> void:
	if locked and not locked_layers.has(layer):
		locked_layers.append(layer)
	elif not locked and locked_layers.has(layer):
		locked_layers.remove_at(locked_layers.find(layer))
	locks_changed.emit()


func notify_settings_changed() -> void:
	settings_changed.emit()


# Sound effects --------------------------------------------------------------

func get_sfx_preset() -> SfxPreset:
	return catalog.get_sfx_preset(sfx_preset_id)


func select_sfx_preset(preset_id: String) -> void:
	sfx_preset_id = preset_id
	roll_sfx()


## "New variation": a fresh seed for the current preset.
func roll_sfx() -> void:
	sfx_seed = _fresh_seed()
	_rebuild_sfx(true)


## "Mutate a little": nudges the current sound.
func mutate_sfx() -> void:
	if sfx == null:
		roll_sfx()
		return
	var mutated := SfxGenerator.mutate(sfx.data["params"], _fresh_seed(), 1.0)
	var next := ChipSfx.from_params(mutated, sfx.get_sound_name(), sfx.data.get("layer2", {}))
	next.data["meta"] = sfx.data["meta"].duplicate()
	next.data["meta"]["mutated"] = true
	sfx = next
	sfx_changed.emit(sfx)


## "Surprise me": any preset, any seed.
func surprise_sfx() -> void:
	var ids := catalog.sfx_presets.keys()
	ids.sort()
	var rng := Pcg32.new(_fresh_seed(), 7)
	sfx_preset_id = ids[rng.range_int(0, ids.size() - 1)]
	sfx_seed = _fresh_seed()
	_rebuild_sfx(true)


func set_sfx_tweak(key: String, value: float) -> void:
	sfx_tweaks[key] = value
	_rebuild_sfx(false)


func reset_sfx_tweaks() -> void:
	sfx_tweaks = SfxGenerator.TWEAK_DEFAULTS.duplicate()
	_rebuild_sfx(false)


## Replaces the current sound's parameters (the Advanced tab).
func set_sfx_params(params: Dictionary) -> void:
	if sfx == null:
		return
	var next := ChipSfx.from_params(params, sfx.get_sound_name(), sfx.data.get("layer2", {}))
	next.data["meta"] = sfx.data["meta"].duplicate()
	sfx = next
	sfx_changed.emit(sfx)


func recall_recent(index: int) -> void:
	if index < 0 or index >= sfx_recent.size():
		return
	sfx_preset_id = sfx_recent[index]["preset"]
	sfx_seed = sfx_recent[index]["seed"]
	_rebuild_sfx(false)


func add_sfx_to_kit() -> String:
	if sfx == null:
		return ""
	var id := SfxGenerator.c_id(sfx.get_sound_name()).trim_prefix("SFX_").to_lower()
	var unique := id
	var n := 2
	while kit.sounds.has(unique):
		unique = "%s_%d" % [id, n]
		n += 1
	var copy := ChipSfx.new()
	copy.data = sfx.data.duplicate(true)
	kit.sounds[unique] = copy
	kit_changed.emit()
	return unique


func remove_from_kit(id: String) -> void:
	kit.sounds.erase(id)
	kit_changed.emit()


func _rebuild_sfx(remember: bool) -> void:
	var preset := get_sfx_preset()
	if preset == null:
		return
	sfx = SfxGenerator.make_sfx(preset, sfx_seed, sfx_tweaks)
	if remember:
		sfx_recent.push_front({"preset": sfx_preset_id, "seed": sfx_seed})
		if sfx_recent.size() > MAX_RECENT:
			sfx_recent.resize(MAX_RECENT)
	sfx_changed.emit(sfx)


# Library --------------------------------------------------------------------

func save_song_to_library() -> void:
	if song == null:
		return
	library.push_front({
		"kind": "song",
		"name": "%s #%s" % [song.get_title(), settings.seed_text],
		"favourite": false,
		"created": Time.get_datetime_string_from_system(),
		"settings": settings.to_dict(),
		"engine_version": SongGenerator.ENGINE_VERSION,
	})
	_save_library()


func save_sfx_to_library() -> void:
	if sfx == null:
		return
	library.push_front({
		"kind": "sfx",
		"name": "%s #%d" % [sfx.get_sound_name(), sfx_seed],
		"favourite": false,
		"created": Time.get_datetime_string_from_system(),
		"sfx": sfx.data,
	})
	_save_library()


func open_library_entry(index: int) -> void:
	var entry: Dictionary = library[index]
	if entry["kind"] == "song":
		settings = SongSettings.from_dict(entry["settings"])
		settings_changed.emit()
		generate()
		mode = "music"
	else:
		var loaded := ChipSfx.from_dict(entry["sfx"])
		if loaded:
			sfx = loaded
			sfx_preset_id = str(loaded.data.get("meta", {}).get("preset", sfx_preset_id))
			sfx_changed.emit(sfx)
		mode = "sfx"


func toggle_favourite(index: int) -> void:
	library[index]["favourite"] = not library[index].get("favourite", false)
	_save_library()


func delete_library_entry(index: int) -> void:
	library.remove_at(index)
	_save_library()


func _load_library() -> void:
	var file := FileAccess.open(LIBRARY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		library = parsed


func _save_library() -> void:
	var file := FileAccess.open(LIBRARY_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(library, "\t"))
	library_changed.emit()


func _fresh_seed() -> int:
	# The only place that uses the clock: new seeds. Everything after a seed
	# is deterministic.
	var mixed := Pcg32.new(Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system() * 1000.0), 99)
	return mixed.range_int(1, 99999)
