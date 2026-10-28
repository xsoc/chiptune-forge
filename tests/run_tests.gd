extends SceneTree
## Runs every tests/test_*.gd file and exits with 1 if anything failed.
##   godot --headless --path . -s tests/run_tests.gd [-- --update-golden] [-- name_filter]

const TEST_DIR := "res://tests"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var update := args.has("--update-golden")
	var filter := ""
	for arg in args:
		if not arg.begins_with("--"):
			filter = arg
	var files := []
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			files.append(file)
	files.sort()
	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for file in files:
		var script: GDScript = load(TEST_DIR.path_join(file))
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_") or (filter != "" and not (file + ":" + test_name).contains(filter)):
				continue
			var test: RefCounted = script.new()
			test.update_golden = update
			test.call(test_name)
			if test.failures.is_empty():
				passed += 1
			else:
				failed += 1
				printerr("FAIL %s:%s" % [file, test_name])
				for message in test.failures:
					printerr("    ", message)
	print("%d passed, %d failed in %.1f s" % [passed, failed, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failed > 0 else 0)
