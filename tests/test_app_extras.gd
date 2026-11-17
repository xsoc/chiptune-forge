extends "res://tests/test_case.gd"
## The About screen's licence list, Surprise me, and 48 kHz exports.


func test_about_lists_every_third_party_row() -> void:
	var markdown := FileAccess.get_file_as_string("res://THIRD_PARTY.md")
	var text := AboutDialog.notices_bbcode(markdown)
	check(text.contains("[b]Godot Engine 4.5[/b]: MIT"), "Godot row")
	check(text.contains("OPL2 and OPL3"), "the DOS PC rows")
	var rows := 0
	for line in markdown.split("\n"):
		if line.begins_with("| ") and not line.begins_with("| Component"):
			rows += 1
	check_eq(text.split("\n").size(), rows, "one line per table row")
	check_eq(AboutDialog.notices_bbcode(""), "See THIRD_PARTY.md in the source repository.")


func test_about_dialog_builds() -> void:
	var dialog: AboutDialog = load("res://scenes/components/about_dialog.tscn").instantiate()
	check(dialog.get_node("%Notices") is RichTextLabel)
	dialog.free()


func test_surprise_pairs_suit_each_other() -> void:
	var catalog := Catalog.get_default()
	var rng := Pcg32.new(42, 7)
	for i in 40:
		var pair := catalog.surprise_pair(rng)
		var vibe := catalog.get_vibe(pair[0])
		var style := catalog.get_style(pair[1])
		check(vibe != null and style != null, "real ids")
		check_eq(Catalog.combo_note(vibe, style), "", "%s with %s" % [pair[0], pair[1]])
	check_eq(catalog.surprise_pair(Pcg32.new(5, 7)), catalog.surprise_pair(Pcg32.new(5, 7)), "deterministic")


func test_48k_wav_export() -> void:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "platformer"
	s.length_seconds = 8.0
	s.seed_text = "4"
	var song := SongGenerator.generate(s, Catalog.get_default())
	var job := ExportJob.for_target_song("modern", song, {"prefix": "t", "godot": false, "rate": 48000})
	job.run()
	var wav: PackedByteArray = job.files["audio/t.wav"]
	check_eq(wav.decode_u32(24), 48000, "rate in the header")
	check(job.files["README.txt"].get_string_from_utf8().contains("WAV, 48 kHz"), "README says 48 kHz")
	var plain := ExportJob.for_target_song("modern", song, {"prefix": "t", "godot": false, "rate": 12345})
	check_eq(plain.rate, 44100, "unknown rates fall back to 44.1 kHz")
	var sfx := ExportJob.for_target_sfx("nes", {"jump": SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("jump"), 1)}, "kit", {"rate": 48000, "console": false})
	sfx.run()
	check_eq(sfx.files["audio/jump.wav"].decode_u32(24), 48000, "console sound effects too")
