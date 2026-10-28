extends "res://tests/test_case.gd"


func test_counts_match_the_spec() -> void:
	var catalog := Catalog.get_default()
	check_eq(catalog.vibes.size(), 147, "vibes")
	check_eq(catalog.styles.size(), 100, "styles")
	check(catalog.sfx_presets.size() >= 150 and catalog.sfx_presets.size() <= 170, "about 160 SFX presets, got %d" % catalog.sfx_presets.size())
	check_eq(Catalog.VIBE_GROUPS.size(), 11, "vibe categories")
	check_eq(Catalog.STYLE_GROUPS.size(), 9, "style families")
	check_eq(Catalog.SFX_GROUPS.size(), 12, "SFX categories")


func test_every_entry_is_in_a_known_group() -> void:
	var catalog := Catalog.get_default()
	for pair in [[catalog.vibes, Catalog.VIBE_GROUPS], [catalog.styles, Catalog.STYLE_GROUPS], [catalog.sfx_presets, Catalog.SFX_GROUPS]]:
		var used := {}
		for id in pair[0]:
			var entry: Resource = pair[0][id]
			check_eq(entry.id, id, "id matches file")
			check(entry.display_name != "", "%s has a name" % id)
			check(pair[1].has(entry.group), "%s is in unknown group %s" % [id, entry.group])
			used[entry.group] = true
		check_eq(used.size(), pair[1].size(), "every group is used")


func test_styles_are_playable() -> void:
	var catalog := Catalog.get_default()
	for id in catalog.styles:
		var style: Style = catalog.styles[id]
		check(style.tempo_min > 0 and style.tempo_min <= style.tempo_max, "%s tempo range" % id)


func test_search() -> void:
	var catalog := Catalog.get_default()
	check(catalog.search(catalog.vibes, "happ").has(catalog.get_vibe("happy")), "search finds happy")
	check(catalog.in_group(catalog.vibes, "Places").size() > 0, "Places has vibes")
