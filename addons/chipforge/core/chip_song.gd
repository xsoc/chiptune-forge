@tool
@icon("res://addons/chipforge/icons/chip_song.svg")
class_name ChipSong
extends Resource
## A chiptune song in the Chiptune Forge format (version 1).
##
## The song is stored as the same dictionary that is written to a
## [code].chipsong[/code] file, so it round-trips without loss. Use
## [method from_json] to load one at runtime, or drop the file into a Godot
## project with the Chiptune Forge plugin enabled to import it.

const FORMAT := "chipforge-song"
const VERSION := 1

## Raw song data. See [code]docs/format.md[/code] for the schema.
@export var data: Dictionary = {}


## Parses JSON text into a song. Returns [code]null[/code] and pushes an
## error when the text is not a valid song.
static func from_json(text: String) -> ChipSong:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ChipSong: file is not a JSON object.")
		return null
	return from_dict(parsed)


## Builds a song from an already parsed dictionary.
static func from_dict(dict: Dictionary) -> ChipSong:
	var error := validate(dict)
	if error != "":
		push_error("ChipSong: " + error)
		return null
	var song := ChipSong.new()
	song.data = dict
	return song


## Loads a song from a [code].chipsong[/code] file path.
static func load_file(path: String) -> ChipSong:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ChipSong: cannot open %s" % path)
		return null
	return from_json(file.get_as_text())


## Returns an empty string when [param dict] is a readable song, or the reason
## it is not.
static func validate(dict: Dictionary) -> String:
	if dict.get("format", "") != FORMAT:
		return "format is not \"%s\"." % FORMAT
	var version := int(dict.get("version", 0))
	if version < 1 or version > VERSION:
		return "unsupported version %d (this plugin reads 1 to %d)." % [version, VERSION]
	for key in ["timing", "instruments", "channels", "patterns", "sections", "order"]:
		if not dict.has(key):
			return "missing \"%s\"." % key
	return ""


func to_json() -> String:
	return JSON.stringify(data, "\t", false)


func get_title() -> String:
	return str(data.get("meta", {}).get("title", "Untitled"))


func get_bpm() -> float:
	return float(data.get("timing", {}).get("bpm", 120.0))


func get_steps_per_beat() -> int:
	return int(data.get("timing", {}).get("steps_per_beat", 4))


func get_beats_per_bar() -> int:
	return int(data.get("timing", {}).get("beats_per_bar", 4))


func get_step_seconds() -> float:
	return 60.0 / get_bpm() / float(get_steps_per_beat())


## Total length in steps of one pass through the order list.
func get_length_steps() -> int:
	var total := 0
	for section_index in data.get("order", []):
		total += int(data["sections"][int(section_index)].get("length", 0))
	return total


func get_length_seconds() -> float:
	return get_length_steps() * get_step_seconds()


func get_loop_start_step() -> int:
	return int(data.get("timing", {}).get("loop_start", 0))


func get_loop_end_step() -> int:
	return int(data.get("timing", {}).get("loop_end", get_length_steps()))


func get_layer_names() -> PackedStringArray:
	var names := PackedStringArray()
	for layer in data.get("layers", []):
		names.append(str(layer.get("name", "")))
	return names


func get_state_names() -> PackedStringArray:
	var names := PackedStringArray()
	for state in data.get("states", []):
		names.append(str(state.get("name", "")))
	return names


func get_cues() -> Array:
	return data.get("cues", [])
