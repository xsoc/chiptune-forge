@tool
extends "chip_import_base.gd"


func _get_importer_name() -> String:
	return "chipforge.song"


func _get_visible_name() -> String:
	return "Chiptune Forge Song"


func _get_recognized_extensions() -> PackedStringArray:
	return ["chipsong"]


func _get_resource_type() -> String:
	return "Resource"


func _parse(text: String) -> Resource:
	return ChipSong.from_json(text)
