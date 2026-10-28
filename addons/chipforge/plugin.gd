@tool
extends EditorPlugin

const ImportSong := preload("editor/chip_import_song.gd")
const ImportSfx := preload("editor/chip_import_sfx.gd")
const ImportKit := preload("editor/chip_import_kit.gd")

var _importers: Array[EditorImportPlugin] = []


func _enter_tree() -> void:
	for importer in [ImportSong.new(), ImportSfx.new(), ImportKit.new()]:
		_importers.append(importer)
		add_import_plugin(importer)


func _exit_tree() -> void:
	for importer in _importers:
		remove_import_plugin(importer)
	_importers.clear()
