extends Node
## Current settings, song, sound effects and library. Screens read from here
## and call its methods; it emits signals when things change.

signal song_changed(song: ChipSong)
signal settings_changed
signal locks_changed
signal sfx_changed(sfx: ChipSfx)
signal kit_changed
signal library_changed
## Packs were added or removed, so the vibes, styles and presets changed.
signal catalog_changed
signal mode_changed(mode: String)
## The export target changed, or its options did. Previews follow it.
signal target_changed(target: String)
## The preview should restart with another sound (the A/B switch).
signal preview_changed
## A state or transition rule was edited (the song is patched in place).
signal adaptive_changed
## The reduced-motion preference changed.
signal prefs_changed

const LIBRARY_PATH := "user://library.json"
const PREFS_PATH := "user://prefs.cfg"
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
## True once the notes of the song have been edited by hand.
var song_edited := false
## Song data before each note edit, newest last, for Undo.
var _undo: Array = []

var sfx_preset_id := "coin"
var sfx_seed := 1
var sfx_tweaks: Dictionary = SfxGenerator.TWEAK_DEFAULTS.duplicate()
var sfx: ChipSfx
## Recent variations: Array of {preset, seed}.
var sfx_recent: Array = []
var kit := ChipSfxKit.new()

## Export target id from the catalog: "modern", "gameboy", "nes", "sms",
## "genesis", "snes", "pce", "gba", "msx", "c64" or "pc".
var target := "modern"
## The sound card the "pc" target plays and exports for (see [PcCards]).
var pc_card := PcCards.DEFAULT
## Game Boy arranger options: sfx_channel (-1 none, 1 Pulse 2, 3 noise) and
## sfx_free (keep that channel free of music).
var gameboy_options := {"sfx_channel": -1, "sfx_free": false}
var _gb_song: GbSong
var _gb_key := []
var _nes_song: NesSong
var _nes_key := []
var _sms_song: SmsSong
var _sms_key := []
var _md_song: MdSong
var _md_key := []
var _snes_song: SnesSong
var _snes_key := []
var _pce_song: PceSong
var _pce_key := []
var _ay_song: AySong
var _ay_key := []
var _sid_song: SidSong
var _sid_key := []
var _gba_song: GbaSong
var _gba_key := []
var _pc_song: Variant
var _pc_key := []

## True while the A/B switch plays the song on the classic chip synth.
var ab_classic := false:
	set(value):
		if ab_classic != value:
			ab_classic = value
			preview_changed.emit()

## Saved entries: {kind, name, favourite, created, settings | sfx}.
var library: Array = []
## Accessibility: the playhead and the song view move once a bar instead
## of smoothly. Saved between runs.
var reduce_motion := false:
	set(v):
		if v == reduce_motion:
			return
		reduce_motion = v
		var prefs := ConfigFile.new()
		prefs.load(PREFS_PATH)
		prefs.set_value("accessibility", "reduce_motion", v)
		prefs.save(PREFS_PATH)
		prefs_changed.emit()


func _ready() -> void:
	catalog = Catalog.get_default()
	kit.kit_name = "My kit"
	_load_library()
	var prefs := ConfigFile.new()
	if prefs.load(PREFS_PATH) == OK:
		reduce_motion = bool(prefs.get_value("accessibility", "reduce_motion", false))
	settings.seed_text = str(_fresh_seed())


## False while no vibe is picked: there is nothing to make or play until one is.
func set_target(id: String) -> void:
	if id != target:
		target = id
		target_changed.emit(id)


func set_pc_card(card: String) -> void:
	if card != pc_card and PcCards.is_card(card):
		pc_card = card
		target_changed.emit(target)


func set_gameboy_option(key: String, value: Variant) -> void:
	if gameboy_options.get(key) != value:
		gameboy_options[key] = value
		target_changed.emit(target)


## The current song arranged for the Game Boy, cached until the song or the
## options change. Null when there is no song.
func get_gameboy_song() -> GbSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash(), gameboy_options.hash()]
	if _gb_song == null or key != _gb_key:
		_gb_song = GbArranger.arrange(SynthEngines.chip_song(song), gameboy_options)
		_gb_key = key
	return _gb_song


## The current song arranged for the NES, cached until the song changes.
## Null when there is no song.
func get_nes_song() -> NesSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _nes_song == null or key != _nes_key:
		_nes_song = NesArranger.arrange(SynthEngines.chip_song(song))
		_nes_key = key
	return _nes_song


## The current song arranged for the Master System, cached until the song
## changes. Null when there is no song.
func get_sms_song() -> SmsSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _sms_song == null or key != _sms_key:
		_sms_song = SmsArranger.arrange(SynthEngines.chip_song(song))
		_sms_key = key
	return _sms_song


## The current song arranged for the Mega Drive, cached until the song
## changes. Null when there is no song.
func get_md_song() -> MdSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _md_song == null or key != _md_key:
		_md_song = MdArranger.arrange(SynthEngines.chip_song(song))
		_md_key = key
	return _md_song


## The current song arranged for the SNES, cached until the song changes.
## Null when there is no song.
func get_snes_song() -> SnesSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _snes_song == null or key != _snes_key:
		_snes_song = SnesArranger.arrange(SynthEngines.chip_song(song))
		_snes_key = key
	return _snes_song


## The current song arranged for the PC Engine, cached until the song
## changes. Null when there is no song.
func get_pce_song() -> PceSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _pce_song == null or key != _pce_key:
		_pce_song = PceArranger.arrange(SynthEngines.chip_song(song))
		_pce_key = key
	return _pce_song


## The current song arranged for the MSX and ZX Spectrum 128, cached until
## the song changes. Null when there is no song.
func get_ay_song() -> AySong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _ay_song == null or key != _ay_key:
		_ay_song = AyArranger.arrange(SynthEngines.chip_song(song))
		_ay_key = key
	return _ay_song


## The current song arranged for the Commodore 64, cached until the song
## changes. Null when there is no song.
func get_sid_song() -> SidSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _sid_song == null or key != _sid_key:
		_sid_song = SidArranger.arrange(SynthEngines.chip_song(song))
		_sid_key = key
	return _sid_song


## The current song arranged for the Game Boy Advance, cached until the
## song changes. Null when there is no song.
func get_gba_song() -> GbaSong:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash()]
	if _gba_song == null or key != _gba_key:
		_gba_song = GbaArranger.arrange(SynthEngines.chip_song(song))
		_gba_key = key
	return _gba_song


## The current song arranged for the current PC sound card, cached until
## the song or the card changes. Null when there is no song.
func get_pc_song() -> Variant:
	if song == null:
		return null
	var key := [song.get_instance_id(), song.to_json().hash(), pc_card]
	if _pc_song == null or key != _pc_key:
		_pc_song = ExportJob.arrange("pc", song, {"card": pc_card})
		_pc_key = key
	return _pc_song


## The current song arranged for the current target (cached), or null on
## the modern target.
func get_arranged_song() -> Variant:
	match target:
		"gameboy":
			return get_gameboy_song()
		"nes":
			return get_nes_song()
		"sms":
			return get_sms_song()
		"genesis":
			return get_md_song()
		"snes":
			return get_snes_song()
		"pce":
			return get_pce_song()
		"msx":
			return get_ay_song()
		"c64":
			return get_sid_song()
		"gba":
			return get_gba_song()
		"pc":
			return get_pc_song()
	return null


## True when previews play through an emulated console instead of the
## modern synth.
func is_console_target() -> bool:
	return target in ["gameboy", "nes", "sms", "genesis", "snes", "pce", "gba", "msx", "c64", "pc"]


func can_make_music() -> bool:
	return not settings.vibes.is_empty()


## Rolls a new seed and generates a new song from the current settings.
func generate_new_song() -> void:
	if not can_make_music():
		return
	settings.seed_text = str(_fresh_seed())
	settings.variations.clear()
	generate()


## Generates from the current settings and seed.
func generate() -> void:
	if not can_make_music():
		return
	song = SongGenerator.generate(settings, catalog)
	_undo.clear()
	song_edited = false
	song_changed.emit(song)


## Gives every unlocked layer a new variation and keeps the locked ones.
func regenerate_unlocked() -> void:
	if not can_make_music():
		return
	if song == null:
		generate()
		return
	for layer in SongSettings.LAYERS:
		if not locked_layers.has(layer):
			settings.variations[layer] = settings.get_variation(layer) + 1
	song = SongGenerator.generate(settings, catalog, song, locked_layers)
	_undo.clear()
	song_changed.emit(song)


## Regenerates a single layer, keeping every other layer as it is.
func regenerate_layer(layer: String) -> void:
	if song == null or not can_make_music():
		return
	settings.variations[layer] = settings.get_variation(layer) + 1
	var keep := PackedStringArray()
	for other in SongSettings.LAYERS:
		if other != layer:
			keep.append(other)
	song = SongGenerator.generate(settings, catalog, song, keep)
	_undo.clear()
	song_changed.emit(song)


## Changes the song's notes with [param change] (it takes the song), keeping
## the old notes for Undo. Editing a layer locks it, so regenerating keeps
## the edit.
func edit_song(layer: String, change: Callable) -> void:
	if song == null:
		return
	_undo.append(song.data.duplicate(true))
	if _undo.size() > 100:
		_undo.pop_front()
	change.call(song)
	song_edited = true
	if not locked_layers.has(layer):
		set_layer_locked(layer, true)
	song_changed.emit(song)


func can_undo() -> bool:
	return not _undo.is_empty()


func undo_edit() -> void:
	if _undo.is_empty() or song == null:
		return
	song.data = _undo.pop_back()
	_apply_engines()
	song_changed.emit(song)


## Sets the song's synth engine ([constant SynthEngines.CHOICES]). Only the
## sound changes: the notes stay as they are.
func set_engine(choice: String) -> void:
	if settings.engine == choice:
		return
	settings.engine = choice
	settings_changed.emit()
	if song:
		_apply_engines()
		song_changed.emit(song)


## Sets one layer's engine, or "" to follow the song's.
func set_layer_engine(layer: String, choice: String) -> void:
	if str(settings.layer_engines.get(layer, "")) == choice:
		return
	if choice == "":
		settings.layer_engines.erase(layer)
	else:
		settings.layer_engines[layer] = choice
	settings_changed.emit()
	if song:
		_apply_engines()
		song_changed.emit(song)


## The engine "Style's pick" gives for the current style.
func get_style_engine() -> String:
	return SynthEngines.style_engine(catalog.get_style(settings.style) if catalog else null)


func _apply_engines() -> void:
	var style: Style = catalog.get_style(settings.style) if catalog else null
	var engine := SynthEngines.resolve(settings.engine, style)
	song.data["instruments"] = SynthEngines.apply(song.data.get("instruments", []), engine, settings.layer_engines, style)


func set_layer_locked(layer: String, locked: bool) -> void:
	if locked and not locked_layers.has(layer):
		locked_layers.append(layer)
	elif not locked and locked_layers.has(layer):
		locked_layers.remove_at(locked_layers.find(layer))
	locks_changed.emit()


## Edits the adaptive states and transition rules. [param change] gets the
## states and rules (copies of the song's) and changes them in place; they
## are kept in the settings, so they survive regenerating, and patched into
## the playing song.
func edit_adaptive(change: Callable) -> void:
	if song == null:
		return
	var states: Array = song.data.get("states", []).duplicate(true)
	var rules: Array = song.data.get("transitions", []).duplicate(true)
	change.call(states, rules)
	settings.states = SongSettings.clean_states(states)
	settings.transitions = SongSettings.clean_transitions(rules)
	song.data["states"] = settings.states.duplicate(true)
	song.data["transitions"] = settings.transitions.duplicate(true)
	adaptive_changed.emit()


## Puts the default states and transitions back.
func reset_adaptive() -> void:
	if song == null:
		return
	settings.states = []
	settings.transitions = []
	song.data["states"] = SongGenerator.STATES.duplicate(true)
	song.data["transitions"] = SongGenerator.TRANSITIONS.duplicate(true)
	adaptive_changed.emit()


## How many parts each state keeps sounding, against the target's voices:
## [{name, voices, limit}] with limit 0 for no limit. Each layer that is not
## Off needs a voice of its own; a chip arranger merges or drops the rest.
func state_budgets() -> Array:
	var out: Array = []
	if song == null:
		return out
	var limit := 0
	var chip: ChipProfile = catalog.chips.get(target)
	if chip and target != "modern":
		limit = chip.max_voices
		if target == "pc":
			limit = PcCards.voice_count(pc_card)
	for state in song.data.get("states", []):
		var voices := 0
		var levels: Dictionary = state.get("levels", {})
		for layer in SongSettings.LAYERS:
			var level: Variant = levels.get(layer, "full")
			if (level is String and level == "off") or ((level is float or level is int) and float(level) <= 0.0):
				continue
			voices += 1
		out.append({"name": str(state.get("name", "")), "voices": voices, "limit": limit})
	return out


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


## "Surprise me" for music: a vibe and style that suit each other, one
## vibe at full strength, and a new seed.
func surprise_song() -> void:
	var pair := catalog.surprise_pair(Pcg32.new(_fresh_seed(), 7))
	settings.vibes.assign([pair[0]])
	settings.vibe_strengths.assign([100.0])
	settings.style = pair[1]
	settings_changed.emit()
	generate_new_song()


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
	set_sfx_layers(params, sfx.data.get("layer2", {}))


## Replaces both layers of the current sound. An empty [param layer2]
## removes the second layer.
func set_sfx_layers(params: Dictionary, layer2: Dictionary) -> void:
	if sfx == null:
		return
	var next := ChipSfx.from_params(params, sfx.get_sound_name(), layer2)
	next.data["meta"] = sfx.data["meta"].duplicate()
	sfx = next
	sfx_changed.emit(sfx)


## Imports jsfxr settings (JSON or a share code) as the current sound's
## first layer. Returns "" or the reason it could not.
func import_jsfxr(text: String) -> String:
	var result := JsfxrImport.parse(text)
	if result.has("error"):
		return str(result["error"])
	if sfx == null:
		select_sfx_preset(sfx_preset_id)
	var params: Dictionary = ChipSfxSynth.with_defaults(result["params"])
	sfx = ChipSfx.from_params(params, "imported", {})
	sfx.data["meta"] = {"name": "imported", "preset": "", "seed": 0, "variant": "jsfxr", "license": SongGenerator.LICENSE}
	sfx_changed.emit(sfx)
	return ""


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
	# Edited notes cannot be made again from the settings: keep the song.
	if song_edited:
		library[0]["song"] = song.data.duplicate(true)
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
		var saved: ChipSong = ChipSong.from_dict(entry["song"]) if entry.has("song") else null
		if saved:
			song = saved
			_undo.clear()
			song_edited = true
			song_changed.emit(song)
		else:
			generate()
		mode = "music"
	else:
		var loaded := ChipSfx.from_dict(entry["sfx"])
		if loaded:
			sfx = loaded
			sfx_preset_id = str(loaded.data.get("meta", {}).get("preset", sfx_preset_id))
			sfx_changed.emit(sfx)
		mode = "sfx"


# Community packs ---------------------------------------------------------------

## Installs a pack from its file's text and keeps it for next time. Returns
## an error message, or "" when it worked.
func install_pack(text: String) -> String:
	var parsed := ChipPack.parse(text, catalog)
	if parsed.has("error"):
		return parsed["error"]
	var pack: ChipPack = parsed["pack"]
	var error := catalog.add_pack(pack)
	if error != "":
		return error
	DirAccess.make_dir_recursive_absolute(Catalog.PACKS_DIR)
	var file := FileAccess.open(Catalog.PACKS_DIR.path_join(pack.file_name()), FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
	catalog_changed.emit()
	return ""


func remove_pack(pack_name: String) -> void:
	var pack := catalog.get_pack(pack_name)
	if pack == null:
		return
	DirAccess.remove_absolute(Catalog.PACKS_DIR.path_join(pack.file_name()))
	catalog.remove_pack(pack_name)
	if not catalog.sfx_presets.has(sfx_preset_id):
		sfx_preset_id = "coin"
	catalog_changed.emit()


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
