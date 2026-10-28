@tool
extends "chip_import_base.gd"


func _get_importer_name() -> String:
	return "chipforge.sfx"


func _get_visible_name() -> String:
	return "Chiptune Forge Sfx"


func _get_recognized_extensions() -> PackedStringArray:
	return ["chipsfx"]


func _get_resource_type() -> String:
	return "Resource"


func _parse(text: String) -> Resource:
	return ChipSfx.from_json(text)
