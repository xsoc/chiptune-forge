extends "res://tests/test_case.gd"
## The command line, run in-process. The golden songs are made through it
## too, so the CLI and the app give the same files.

const GOLDEN := [
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _out_dir(name: String) -> String:
	var dir := "user://cli_test/%s_%d" % [name, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _run(args: Array) -> CliRunner:
	var cli := CliRunner.new()
	cli.silent = true
	cli.set_meta("code", cli.run(PackedStringArray(args)))
	return cli


func _code(cli: CliRunner) -> int:
	return int(cli.get_meta("code"))


func _report(cli: CliRunner) -> Dictionary:
	var parsed: Variant = JSON.parse_string("\n".join(cli.output))
	return parsed if parsed is Dictionary else {}


func test_golden_songs_through_the_cli() -> void:
	for combo in GOLDEN:
		var out := _out_dir("golden")
		var cli := _run(["generate", "--vibe", combo[0], "--style", combo[1], "--seed", combo[2], "--format", "json", "--name", "song", "--out", out])
		check_eq(_code(cli), 0, "generate %s" % [combo])
		check_golden("song_%s_%s_%s.chipsong" % combo, FileAccess.get_file_as_string(out.path_join("godot/song.chipsong")) + "\n")


func test_same_files_as_the_app() -> void:
	var s := SongSettings.new()
	s.vibes.assign(["happy", "cozy"])
	s.vibe_strengths.assign([70.0, 30.0])
	s.style = "platformer"
	s.seed_text = "1234"
	s.tempo = 140
	s.key = 9
	var song := SongGenerator.generate(s)
	var app := ExportJob.for_target_song("nes", song, {"prefix": "tune", "console": true, "wav": false, "godot": true, "plugin": false})
	app.run()
	var out := _out_dir("same")
	var cli := _run(["generate", "--vibe", "happy:70", "--vibe", "cozy:30", "--style", "platformer", "--seed", "1234",
		"--tempo", "140", "--key", "A", "--target", "nes", "--format", "json,console", "--name", "tune", "--out", out])
	check_eq(_code(cli), 0, "generated")
	for name in app.files:
		check_eq(FileAccess.get_file_as_bytes(out.path_join(name)), app.files[name], "%s is the same" % name)


func test_json_report_and_strict() -> void:
	var out := _out_dir("json")
	var cli := _run(["generate", "--vibe", "happy", "--style", "platformer", "--seed", "9", "--target", "gameboy", "--format", "console,project", "--out", out, "--json"])
	check_eq(_code(cli), 0, "generated")
	var report := _report(cli)
	check_eq(report.get("seed"), "9", "seed")
	check_eq(report.get("target"), "gameboy", "target")
	check(report.get("chip_report", {}).get("fits", false), "fits")
	check(not (report.get("chip_report", {}).get("lines", []) as Array).is_empty(), "the target's report")
	check((report.get("files", []) as Array).size() > 3, "files listed")
	check(FileAccess.file_exists(out.path_join("happy_platformer.cforge")), "project written")
	var strict := _run(["validate", out.path_join("happy_platformer.cforge"), "--strict"])
	check_eq(_code(strict), CliRunner.LIMITS, "strict fails when the arranger changed the song")
	var modern := _run(["validate", out.path_join("happy_platformer.cforge"), "--target", "modern", "--strict"])
	check_eq(_code(modern), 0, "nothing changes on the modern target")


func test_random_seed_is_reported() -> void:
	var out := _out_dir("seed")
	var cli := _run(["generate", "--vibe", "calm", "--style", "ambient", "--format", "project", "--out", out, "--json"])
	check_eq(_code(cli), 0, "generated")
	var seed_text := str(_report(cli).get("seed", ""))
	check(seed_text != "", "the seed is printed")
	var again := _run(["generate", "--vibe", "calm", "--style", "ambient", "--seed", seed_text, "--format", "project", "--name", "again", "--out", out, "--json"])
	var a: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("calm_ambient.cforge")))
	var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out.path_join("again.cforge")))
	check_eq(JSON.stringify(a["song"]), JSON.stringify(b["song"]), "the printed seed makes the same song")


func test_export_project_to_another_target() -> void:
	var out := _out_dir("export")
	check_eq(_code(_run(["generate", "--vibe", "haunted", "--style", "platformer", "--seed", "3", "--format", "project", "--name", "level", "--out", out])), 0, "generated")
	var cli := _run(["export", out.path_join("level.cforge"), "--target", "c64", "--format", "console", "--out", out.path_join("c64")])
	check_eq(_code(cli), 0, "exported")
	check(FileAccess.file_exists(out.path_join("c64/c64/level.sid")), "a SID file: %s" % [DirAccess.get_directories_at(out.path_join("c64"))])


func test_sfx_with_variants() -> void:
	var out := _out_dir("sfx")
	var cli := _run(["sfx", "--preset", "jump", "--preset", "coin", "--variants", "3", "--seed", "5", "--format", "json,wav", "--name", "kit", "--out", out, "--json"])
	check_eq(_code(cli), 0, "made")
	var sounds: Dictionary = _report(cli).get("sounds", {})
	check_eq(sounds.size(), 6, "three takes of each")
	check(FileAccess.file_exists(out.path_join("audio/jump_2.wav")), "a WAV per sound")
	check(FileAccess.file_exists(out.path_join("godot/kit.chipkit")), "the kit")
	var preset := Catalog.get_default().get_sfx_preset("jump")
	var expected := SfxGenerator.make_sfx(preset, 6)
	var made := ChipSfx.load_file(out.path_join("godot/sounds/jump_2.chipsfx"))
	check_eq(JSON.stringify(made.data["params"]), JSON.stringify(JSON.parse_string(JSON.stringify(expected.data["params"]))), "the same sound as the app makes from that seed")


func test_batch_manifest() -> void:
	var dir := _out_dir("batch")
	var manifest := {"jobs": [
		{"command": "generate", "vibe": ["happy"], "style": "platformer", "seed": 1, "format": "project", "name": "a", "out": "songs"},
		{"command": "sfx", "preset": ["coin"], "seed": 2, "format": "wav", "out": "sounds"},
		{"command": "export", "file": "songs/a.cforge", "target": "pce", "format": "console", "out": "pce"},
	]}
	var file := FileAccess.open(dir.path_join("m.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	var cli := _run(["batch", dir.path_join("m.json"), "--json"])
	check_eq(_code(cli), 0, "every job ran")
	check_eq((_report(cli).get("jobs", []) as Array).size(), 3, "three jobs reported")
	check(FileAccess.file_exists(dir.path_join("songs/a.cforge")), "paths are relative to the manifest")
	check(FileAccess.file_exists(dir.path_join("sounds/audio/coin.wav")), "the sound")
	check(DirAccess.dir_exists_absolute(dir.path_join("pce")), "the exported project")


func test_errors_and_exit_codes() -> void:
	check_eq(_code(_run(["generate", "--vibe", "nope"])), CliRunner.BAD_ARGS, "unknown vibe")
	check_eq(_code(_run(["generate", "--vibe", "a", "--vibe", "b", "--vibe", "c", "--vibe", "d"])), CliRunner.BAD_ARGS, "four vibes")
	check_eq(_code(_run(["generate", "--target", "atari"])), CliRunner.BAD_ARGS, "unknown target")
	check_eq(_code(_run(["generate", "--format", "mp3"])), CliRunner.BAD_ARGS, "unknown format")
	check_eq(_code(_run(["generate", "--tempo", "9000"])), CliRunner.BAD_ARGS, "tempo out of range")
	check_eq(_code(_run(["generate", "--seed"])), CliRunner.BAD_ARGS, "flag without a value")
	check_eq(_code(_run(["frobnicate"])), CliRunner.BAD_ARGS, "unknown command")
	check_eq(_code(_run(["sfx"])), CliRunner.BAD_ARGS, "no preset")
	check_eq(_code(_run(["export", "user://no_such_file.cforge"])), CliRunner.FILE_ERROR, "missing file")
	var dir := _out_dir("bad")
	var file := FileAccess.open(dir.path_join("bad.chipsong"), FileAccess.WRITE)
	file.store_string("{\"format\": \"chipforge-song\", \"version\": 1}")
	file.close()
	check_eq(_code(_run(["validate", dir.path_join("bad.chipsong")])), CliRunner.SCHEMA, "invalid song")
	check_eq(_code(_run(["validate", "res://packs/seasons.chippack"])), 0, "a valid pack")
	var failed := _run(["generate", "--vibe", "nope", "--json"])
	check_eq(int(_report(failed).get("exit_code", -1)), CliRunner.BAD_ARGS, "errors in the JSON report")
	check(str(_report(failed).get("error", "")).contains("nope"), "with the reason")


func test_list_and_version() -> void:
	var vibes := _report(_run(["list", "vibes", "--json"]))
	check(int((vibes.get("items", []) as Array).size()) >= 147, "every vibe")
	var targets := _report(_run(["list", "targets", "--json"]))
	check_eq((targets.get("items", []) as Array).size(), ExportJob.TARGETS.size(), "every target")
	var version := _report(_run(["version", "--json"]))
	check_eq(version.get("engine"), SongGenerator.ENGINE_VERSION, "engine version")
	check(CliRunner.wants_cli(PackedStringArray(["generate"])), "generate is a command")
	check(not CliRunner.wants_cli(PackedStringArray([])), "no arguments opens the app")
	check(not CliRunner.wants_cli(PackedStringArray(["--some-godot-flag"])), "other arguments open the app")


func test_pack_flag() -> void:
	var out := _out_dir("pack")
	var cli := _run(["generate", "--pack", "res://packs/seasons.chippack", "--vibe", "winter_frost", "--style", "harvest_dance", "--seed", "1", "--format", "project", "--out", out])
	check_eq(_code(cli), 0, "a pack's vibe and style")
	Catalog.get_default().remove_pack("Seasons")
