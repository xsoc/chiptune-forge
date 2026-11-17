class_name FileDelivery
extends RefCounted
## Hands an exported file to the user: a browser download on the web, a save
## dialog on desktop and mobile, or a file in the app's data folder when no
## dialog is available. [method pick_text] goes the other way, for opening
## a file.

## Keeps the browser's callback alive while its file picker is open.
static var _web_callback: JavaScriptObject


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


## Asks the user for a text file: the browser's file picker on the web, an
## open dialog elsewhere. Calls [param on_picked] with the text and the
## file's name, unless the user cancels.
static func pick_text(extensions: PackedStringArray, description: String, host: Node, on_picked: Callable) -> void:
	if OS.has_feature("web"):
		_web_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
			on_picked.call(str(args[1]), str(args[0])))
		JavaScriptBridge.get_interface("window").chiptuneForgePicked = _web_callback
		var accept := ",".join(Array(extensions).map(func(e: String) -> String: return "." + e))
		JavaScriptBridge.eval("""(function () {
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '%s';
			input.onchange = function () {
				var file = input.files[0];
				if (file) file.text().then(function (text) { window.chiptuneForgePicked(file.name, text); });
			};
			input.click();
		})();""" % accept)
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray([" ".join(Array(extensions).map(func(e: String) -> String: return "*." + e)) + " ; " + description])
	dialog.title = "Open %s" % description
	host.add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		on_picked.call(FileAccess.get_file_as_string(path), path.get_file())
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered_ratio(0.6)
