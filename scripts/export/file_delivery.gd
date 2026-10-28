class_name FileDelivery
extends RefCounted
## Hands an exported file to the user: a browser download on the web, a save
## dialog on desktop and mobile, or a file in the app's data folder when no
## dialog is available.


## Delivers [param bytes] as [param file_name]. Calls [param on_done] with a
## message for the user.
static func deliver(bytes: PackedByteArray, file_name: String, host: Node, on_done: Callable) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, file_name, "application/zip")
		on_done.call("Downloaded %s." % file_name)
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE) or not OS.has_feature("mobile"):
		var dialog := FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.use_native_dialog = true
		dialog.current_file = file_name
		dialog.filters = PackedStringArray(["*.zip ; ZIP archive"])
		dialog.title = "Save export"
		host.add_child(dialog)
		dialog.file_selected.connect(func(path: String) -> void:
			on_done.call(_write(path, bytes))
			dialog.queue_free())
		dialog.canceled.connect(func() -> void:
			on_done.call("Export cancelled.")
			dialog.queue_free())
		dialog.popup_centered_ratio(0.6)
		return
	var path := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if path == "" or not DirAccess.dir_exists_absolute(path):
		path = OS.get_user_data_dir()
	on_done.call(_write(path.path_join(file_name), bytes))


static func _write(path: String, bytes: PackedByteArray) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not save to %s (%s)." % [path, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes)
	return "Saved %s." % path
