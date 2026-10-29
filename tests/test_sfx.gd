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


func test_every_variant_renders() -> void:
	var catalog := Catalog.get_default()
	for id in catalog.sfx_presets:
		var preset: SfxPreset = catalog.sfx_presets[id]
		check(preset.variants.size() >= 3, "%s has at least three variants" % id)
		var found := {}
		for seed_value in range(1, 400):
			var variant := SfxGenerator.variant_index(preset, seed_value)
			if variant == 0 or found.has(variant):
				continue
			found[variant] = true
			var sfx := SfxGenerator.make_sfx(preset, seed_value)
			var samples := sfx.render(11025)
			var peak := 0.0
			for v in samples:
				peak = maxf(peak, absf(v))
			var label := "%s %s" % [id, sfx.data["meta"]["variant"]]
			check(samples.size() > 20, "%s renders samples" % label)
			check(samples.size() < 11025 * 8, "%s is under 8 s" % label)
			check(peak > 0.01, "%s is audible" % label)
			if found.size() == preset.variants.size():
				break
		check_eq(found.size(), preset.variants.size(), "%s: seeds reach every variant" % id)


func test_variants_are_deterministic_and_seed_zero_is_classic() -> void:
	var preset := Catalog.get_default().get_sfx_preset("coin")
	check_eq(SfxGenerator.variant_name(preset, 0), "Classic")
	for seed_value in [3, 77, 1234]:
		check_eq(JSON.stringify(SfxGenerator.roll(preset, seed_value)), JSON.stringify(SfxGenerator.roll(preset, seed_value)), "roll %d repeatable" % seed_value)
	var names := {}
	for seed_value in range(1, 50):
		names[SfxGenerator.variant_name(preset, seed_value)] = true
	check(names.size() >= 4, "seeds spread across baselines")
