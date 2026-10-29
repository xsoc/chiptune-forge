extends "res://tests/test_case.gd"

const CATALOG_PICKER := preload("res://scenes/components/catalog_picker.tscn")


## Setting the same picks again (as the Generate screen does after every
## change) must keep the blend sliders, or a drag in progress is cut off.
func test_picker_keeps_strength_sliders_for_same_picks() -> void:
	var catalog := Catalog.get_default()
	var picker: CatalogPicker = CATALOG_PICKER.instantiate()
	picker.multi_select = true
	picker.show_strengths = true
	Engine.get_main_loop().root.add_child(picker)
	picker.setup(catalog, catalog.vibes, Catalog.VIBE_GROUPS)
	var ids := PackedStringArray(catalog.vibes.keys().slice(0, 2))
	var strengths: Array[float] = [100.0, 50.0]
	picker.set_selected(ids, strengths)
	var sliders := _strength_sliders(picker)
	check_eq(sliders.size(), 2, "one slider per pick")

	strengths = [100.0, 70.0]
	picker.set_selected(ids, strengths)
	var after := _strength_sliders(picker)
	check_eq(after, sliders, "same sliders kept")
	if after.size() == 2:
		check_near(after[1].value, 70.0, 0.001, "slider shows new strength")

	picker.set_selected(PackedStringArray([ids[0]]), [100.0] as Array[float])
	check_eq(_strength_sliders(picker).size(), 1, "rebuilt for new picks")
	picker.free()


func _strength_sliders(picker: CatalogPicker) -> Array:
	var out := []
	for row in picker.get_node("%Strengths").get_children():
		if row.is_queued_for_deletion():
			continue
		for child in row.get_children():
			if child is HSlider:
				out.append(child)
	return out
