extends "res://tests/test_case.gd"

const GOLDEN_PRESETS := ["coin", "jump", "explosion", "laser", "power_up", "select"]


func test_golden_sfx_params() -> void:
	var catalog := Catalog.get_default()
	var out := {}
	for id in GOLDEN_PRESETS:
		var preset := catalog.get_sfx_preset(id)
		check(preset != null, "preset %s exists" % id)
		if preset:
			out[id] = SfxGenerator.make_sfx(preset, 1234).data
	check_golden("sfx_params.json", JSON.stringify(out, "\t") + "\n")


func test_every_preset_renders() -> void:
	var catalog := Catalog.get_default()
	for id in catalog.sfx_presets:
		var sfx := SfxGenerator.make_sfx(catalog.sfx_presets[id], 1)
		var samples := sfx.render(22050)
		check(samples.size() > 100, "%s renders samples" % id)
		check(samples.size() < 22050 * 8, "%s is under 8 s" % id)
		var peak := 0.0
		for v in samples:
			peak = maxf(peak, absf(v))
		check(peak > 0.01, "%s is audible" % id)
		check(peak <= 1.0, "%s does not clip (peak %f)" % [id, peak])


func test_mutate_is_deterministic_and_small() -> void:
	var preset := Catalog.get_default().get_sfx_preset("coin")
	var params := SfxGenerator.roll(preset, 5)
	var a := SfxGenerator.mutate(params, 9, 0.5)
	check_eq(JSON.stringify(a), JSON.stringify(SfxGenerator.mutate(params, 9, 0.5)), "mutate repeatable")
	check(JSON.stringify(a) != JSON.stringify(params), "mutate changes something")


func test_c_ids() -> void:
	check_eq(SfxGenerator.c_id("Heavy Laser"), "SFX_HEAVY_LASER")
