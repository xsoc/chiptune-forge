@tool
@icon("res://addons/chipforge/icons/chip_sfx.svg")
class_name ChipSfxKit
extends Resource
## A named set of sound effects, such as every sound a game uses.
##
## Sounds are looked up by id, for example [code]"jump"[/code]. Ids match the
## [code]SFX_JUMP[/code] style names used by the console exports.

const FORMAT := "chipforge-kit"
const VERSION := 1

@export var kit_name := "Kit"
## Sounds keyed by id.
@export var sounds: Dictionary = {}


static func from_json(text: String) -> ChipSfxKit:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ChipSfxKit: file is not a JSON object.")
		return null
	return from_dict(parsed)


static func from_dict(dict: Dictionary) -> ChipSfxKit:
	if dict.get("format", "") != FORMAT:
		push_error("ChipSfxKit: format is not \"%s\"." % FORMAT)
		return null
	var kit := ChipSfxKit.new()
	kit.kit_name = str(dict.get("name", "Kit"))
	for entry in dict.get("sounds", []):
		var sfx := ChipSfx.from_dict(entry.get("sound", {}))
		if sfx != null:
			kit.sounds[str(entry.get("id", sfx.get_sound_name()))] = sfx
	return kit


func to_dict() -> Dictionary:
	var entries: Array = []
	for id in sounds:
		entries.append({"id": id, "sound": sounds[id].data})
	return {"format": FORMAT, "version": VERSION, "name": kit_name, "sounds": entries}


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t", false)


func get_sound(id: String) -> ChipSfx:
	return sounds.get(id)
