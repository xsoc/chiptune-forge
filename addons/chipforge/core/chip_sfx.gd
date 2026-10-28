@tool
@icon("res://addons/chipforge/icons/chip_sfx.svg")
class_name ChipSfx
extends Resource
## A sound effect in the Chiptune Forge format (version 1).
##
## A sound is a set of synth parameters in the sfxr family, plus an optional
## second layer. It is rendered to audio on first use and cached.

const FORMAT := "chipforge-sfx"
const VERSION := 1

## Raw sound data: [code]meta[/code], [code]params[/code] and an optional
## [code]layer2[/code].
@export var data: Dictionary = {}:
	set(value):
		data = value
		_cached_stream = null

var _cached_stream: AudioStreamWAV


static func from_json(text: String) -> ChipSfx:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ChipSfx: file is not a JSON object.")
		return null
	return from_dict(parsed)


static func from_dict(dict: Dictionary) -> ChipSfx:
	var error := validate(dict)
	if error != "":
		push_error("ChipSfx: " + error)
		return null
	var sfx := ChipSfx.new()
	sfx.data = dict
	return sfx


## Wraps a parameter dictionary in a complete sound.
static func from_params(params: Dictionary, sound_name := "sound", layer2 := {}) -> ChipSfx:
	var dict := {
		"format": FORMAT,
		"version": VERSION,
		"meta": {"name": sound_name},
		"params": params,
	}
	if not layer2.is_empty():
		dict["layer2"] = layer2
	var sfx := ChipSfx.new()
	sfx.data = dict
	return sfx


static func load_file(path: String) -> ChipSfx:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ChipSfx: cannot open %s" % path)
		return null
	return from_json(file.get_as_text())


static func validate(dict: Dictionary) -> String:
	if dict.get("format", "") != FORMAT:
		return "format is not \"%s\"." % FORMAT
	var version := int(dict.get("version", 0))
	if version < 1 or version > VERSION:
		return "unsupported version %d (this plugin reads 1 to %d)." % [version, VERSION]
	if typeof(dict.get("params")) != TYPE_DICTIONARY:
		return "missing \"params\"."
	return ""


func to_json() -> String:
	return JSON.stringify(data, "\t", false)


func get_sound_name() -> String:
	return str(data.get("meta", {}).get("name", "sound"))


## Renders the sound (both layers) to mono samples in the range -1 to 1.
func render(mix_rate := ChipSfxSynth.DEFAULT_RATE) -> PackedFloat32Array:
	var samples := ChipSfxSynth.render(data.get("params", {}), mix_rate)
	var layer2: Dictionary = data.get("layer2", {})
	if not layer2.is_empty():
		var second := ChipSfxSynth.render(layer2, mix_rate)
		if second.size() > samples.size():
			var old_size := samples.size()
			samples.resize(second.size())
			for i in range(old_size, samples.size()):
				samples[i] = 0.0
		for i in second.size():
			samples[i] = clampf(samples[i] + second[i], -1.0, 1.0)
	return samples


## Returns a playable stream, rendering and caching it on first call.
func get_stream() -> AudioStreamWAV:
	if _cached_stream == null:
		_cached_stream = ChipAudio.mono_to_stream(render(), ChipSfxSynth.DEFAULT_RATE)
	return _cached_stream
