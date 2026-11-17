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


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return [{"name": "prerender", "default_value": false, "hint_string": "Render the song to a looping OGG Vorbis stream on import, for low-end devices or when live synthesis is not needed."}]


func _finish(resource: Resource, options: Dictionary) -> void:
	if bool(options.get("prerender", false)):
		(resource as ChipSong).prerendered = (resource as ChipSong).render_ogg()
