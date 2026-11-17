extends "res://tests/test_case.gd"

const PACKS_DIR := "res://packs"


func _fresh_catalog() -> Catalog:
	var catalog := Catalog.new()
	catalog.load_all()
	return catalog


func _pack_text(extra := {}) -> String:
	var data := {
		"format": ChipPack.FORMAT, "version": 1, "name": "Test pack",
		"vibes": [{"id": "test_vibe", "group": "Places", "tempo_min": 90, "tempo_max": 120, "mode_weights": {"major": 1}}],
	}
	data.merge(extra, true)
	return JSON.stringify(data)


## Every pack in the repository's packs folder loads.
func test_repository_packs_load() -> void:
	var files := DirAccess.get_files_at(PACKS_DIR)
	var count := 0
	for file in files:
		if not file.ends_with("." + ChipPack.EXTENSION):
			continue
		count += 1
		var catalog := _fresh_catalog()
		var parsed := ChipPack.parse(FileAccess.get_file_as_string(PACKS_DIR.path_join(file)), catalog)
		check(not parsed.has("error"), "%s: %s" % [file, parsed.get("error", "")])
		if parsed.has("pack"):
			check_eq(catalog.add_pack(parsed["pack"]), "", "%s adds" % file)
	check(count > 0, "the example pack is there")


func test_pack_items_make_music_and_sounds() -> void:
	var catalog := _fresh_catalog()
	var parsed := ChipPack.parse(FileAccess.get_file_as_string(PACKS_DIR.path_join("seasons.chippack")), catalog)
	var pack: ChipPack = parsed["pack"]
	check_eq(pack.summary(), "4 vibes, 1 style, 2 sounds", "summary")
	check_eq(pack.file_name(), "seasons.chippack", "file name")
	check_eq(catalog.add_pack(pack), "", "added")
	check(catalog.get_vibe("winter_frost") != null, "a vibe from the pack")
	check(catalog.in_group(catalog.styles, "World and folk").has(catalog.get_style("harvest_dance")), "in its group, after the built-ins")
	var s := SongSettings.new()
	s.vibes.assign(["winter_frost", "happy"])
	s.style = "harvest_dance"
	s.seed_text = "3"
	var a := SongGenerator.generate(s, catalog)
	var b := SongGenerator.generate(s, catalog)
	check_eq(a.to_json(), b.to_json(), "the same seed gives the same song")
	check(int(a.data["timing"]["beats_per_bar"]) == 2, "the style's metre")
	for id in ["raindrop", "gust_of_wind"]:
		var sfx := SfxGenerator.make_sfx(catalog.get_sfx_preset(id), 5)
		check(sfx != null and sfx.data.has("params"), "%s makes a sound" % id)
	catalog.remove_pack("Seasons")
	check(catalog.get_vibe("winter_frost") == null, "removed")
	check(catalog.packs.is_empty(), "no packs")


func test_bad_packs_are_refused() -> void:
	var catalog := _fresh_catalog()
	var cases := {
		"not json": "{",
		"wrong format": JSON.stringify({"format": "other"}),
		"no name": _pack_text({"name": ""}),
		"empty": _pack_text({"vibes": []}),
		"bad id": _pack_text({"vibes": [{"id": "Bad Id", "group": "Places"}]}),
		"unknown property": _pack_text({"vibes": [{"id": "x", "group": "Places", "script": "evil"}]}),
		"wrong type": _pack_text({"vibes": [{"id": "x", "group": "Places", "energy": "loud"}]}),
		"unknown group": _pack_text({"vibes": [{"id": "x", "group": "Nowhere"}]}),
		"built-in id": _pack_text({"vibes": [{"id": "happy", "group": "Places"}]}),
		"unknown mode": _pack_text({"vibes": [{"id": "x", "group": "Places", "mode_weights": {"klingon": 1}}]}),
		"unknown drums": _pack_text({"styles": [{"id": "x", "group": "Electronic", "drum_pattern": "nope"}]}),
		"unknown sound parameter": _pack_text({"sfx_presets": [{"id": "x", "group": "World", "base": {"volume_of_doom": 1}}]}),
		"bad wave": _pack_text({"sfx_presets": [{"id": "x", "group": "World", "waves": ["laser"]}]}),
		"newer version": _pack_text({"version": 99}),
		"duplicate": _pack_text({"vibes": [{"id": "x", "group": "Places"}, {"id": "x", "group": "Places"}]}),
	}
	for name in cases:
		var parsed := ChipPack.parse(cases[name], catalog)
		check(parsed.has("error"), "%s is refused" % name)


func test_ids_cannot_clash_between_packs() -> void:
	var catalog := _fresh_catalog()
	var first: ChipPack = ChipPack.parse(_pack_text(), catalog)["pack"]
	check_eq(catalog.add_pack(first), "", "first")
	var again: ChipPack = ChipPack.parse(_pack_text({"description": "v2"}), catalog)["pack"]
	check_eq(catalog.add_pack(again), "", "a new version of the same pack replaces it")
	check_eq(catalog.packs.size(), 1, "still one pack")
	var other: ChipPack = ChipPack.parse(_pack_text({"name": "Other"}), catalog)["pack"]
	check(catalog.add_pack(other) != "", "another pack cannot take the id")


func test_written_pack_reads_back() -> void:
	var catalog := _fresh_catalog()
	var copies: Array = [catalog.get_vibe("happy").duplicate(), catalog.get_style("rock").duplicate(), catalog.get_sfx_preset("coin").duplicate()]
	for res in copies:
		res.id += "_copy"
	var text := ChipPack.write({"name": "Round trip", "license": "CC0-1.0"}, copies)
	var parsed := ChipPack.parse(text, catalog)
	check(not parsed.has("error"), "reads back: %s" % parsed.get("error", ""))
	if parsed.has("pack"):
		var pack: ChipPack = parsed["pack"]
		var vibe: Vibe = pack.items["vibes"][0]
		check_eq(vibe.tempo_max, catalog.get_vibe("happy").tempo_max, "values kept")
		var coin: SfxPreset = pack.items["sfx_presets"][0]
		check_eq(SfxGenerator.roll(coin, 0), SfxGenerator.roll(catalog.get_sfx_preset("coin"), 0), "the copy sounds the same")
		check_eq(coin.variants, catalog.get_sfx_preset("coin").variants, "variants kept")


func test_installing_from_the_library_screen() -> void:
	var state: Node = Engine.get_main_loop().root.get_node("AppState")
	if state.catalog == null:
		state.catalog = Catalog.get_default()
	var screen: Control = load("res://scenes/screens/library_screen.tscn").instantiate()
	Engine.get_main_loop().root.add_child(screen)
	if not screen.is_node_ready():
		screen._ready()
	var changed := [0]
	var on_change := func() -> void: changed[0] += 1
	state.catalog_changed.connect(on_change)
	screen.add_pack("{", "broken.chippack")
	check(screen.get_node("%PackStatus").text.begins_with("Could not add broken.chippack"), "says why a pack was refused")
	var name := "Library test pack %d" % Time.get_ticks_usec()
	screen.add_pack(_pack_text({"name": name, "vibes": [{"id": "library_test_vibe", "group": "Places"}]}), "test.chippack")
	check(screen.get_node("%PackStatus").text.begins_with("Added " + name), "says it was added")
	check(state.catalog.get_vibe("library_test_vibe") != null, "in the catalog")
	var pack: ChipPack = state.catalog.get_pack(name)
	check(FileAccess.file_exists(Catalog.PACKS_DIR.path_join(pack.file_name())), "kept for next time")
	check_eq(changed[0], 1, "pickers told")
	state.remove_pack(name)
	check(state.catalog.get_vibe("library_test_vibe") == null, "removed")
	check(not FileAccess.file_exists(Catalog.PACKS_DIR.path_join(pack.file_name())), "file removed")
	state.catalog_changed.disconnect(on_change)
	screen.free()
