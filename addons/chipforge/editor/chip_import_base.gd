@tool
extends EditorImportPlugin
## Shared behaviour for the Chiptune Forge importers. Each file is JSON text
## that becomes a binary resource in the imported cache.


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _get_save_extension() -> String:
	return "res"


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _parse(_text: String) -> Resource:
	return null


func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var file := FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var resource := _parse(file.get_as_text())
	if resource == null:
		return ERR_PARSE_ERROR
	return ResourceSaver.save(resource, "%s.%s" % [save_path, _get_save_extension()])
