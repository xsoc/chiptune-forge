@tool
extends "chip_import_base.gd"


func _get_importer_name() -> String:
	return "chipforge.kit"


func _get_visible_name() -> String:
	return "Chiptune Forge Kit"


func _get_recognized_extensions() -> PackedStringArray:
	return ["chipkit"]


func _get_resource_type() -> String:
	return "Resource"


func _parse(text: String) -> Resource:
	return ChipSfxKit.from_json(text)
