extends SceneTree
## Encodes every sample in SnesSamples.RECIPES as BRR into
## assets/snes/samples/, with the port of smconv's encoder:
##   godot --headless --path . -s tools/snes_samples.gd [-- --check]
## With --check it writes nothing and exits 1 if a stored file differs from
## a fresh encoding (CI runs this, so the files can't drift from the
## recipes).


func _initialize() -> void:
	var check := OS.get_cmdline_user_args().has("--check")
	var dir := ProjectSettings.globalize_path(SnesSamples.BRR_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var failed := 0
	for name in SnesSamples.RECIPES:
		var started := Time.get_ticks_msec()
		var data: PackedByteArray = SnesSamples.encode(name)["data"]
		var path := dir.path_join(name + ".brr")
		if check:
			var stored := FileAccess.get_file_as_bytes(path)
			if stored != data:
				printerr("%s: stored BRR differs from a fresh encoding" % name)
				failed += 1
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(data)
			file.close()
		print("%s: %d bytes in %d ms" % [name, data.size(), Time.get_ticks_msec() - started])
	quit(1 if failed > 0 else 0)
