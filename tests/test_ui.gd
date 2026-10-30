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


## The X button by each pick asks first, then removes it. With allow_empty the
## last pick can go too.
func test_picker_name_buttons_remove_picks() -> void:
	var catalog := Catalog.get_default()
	var picker: CatalogPicker = CATALOG_PICKER.instantiate()
	picker.multi_select = true
	picker.show_strengths = true
	picker.allow_empty = true
	picker.empty_hint = "Pick a vibe"
	Engine.get_main_loop().root.add_child(picker)
	picker.setup(catalog, catalog.vibes, Catalog.VIBE_GROUPS)
	var ids := PackedStringArray(catalog.vibes.keys().slice(0, 2))
	picker.set_selected(ids, [100.0, 50.0] as Array[float])
	var emitted := []
	picker.selection_changed.connect(func(picked: PackedStringArray) -> void: emitted.append(picked.duplicate()))

	var buttons := _name_buttons(picker)
	check_eq(buttons.size(), 2, "one X button per pick")
	buttons[1].pressed.emit()
	check_eq(picker.get_selected().size(), 2, "nothing removed before confirming")
	var dialog: ConfirmationDialog = picker.get_node("%ConfirmRemove")
	check(dialog.dialog_text.contains(catalog.vibes[ids[1]].display_name), "confirmation names the vibe")
	dialog.confirmed.emit()
	check_eq(picker.get_selected(), PackedStringArray([ids[0]]), "second pick removed")

	_name_buttons(picker)[0].pressed.emit()
	dialog.confirmed.emit()
	check(picker.get_selected().is_empty(), "last pick removed")
	check(picker.get_node("%EmptyHint").visible, "hint shown with no picks")
	check_eq(emitted.size(), 2, "selection_changed per removal")
	picker.free()


## Without allow_empty the last pick stays.
func test_picker_keeps_last_pick_by_default() -> void:
	var catalog := Catalog.get_default()
	var picker: CatalogPicker = CATALOG_PICKER.instantiate()
	picker.multi_select = true
	picker.show_strengths = true
	Engine.get_main_loop().root.add_child(picker)
	picker.setup(catalog, catalog.vibes, Catalog.VIBE_GROUPS)
	var id: String = catalog.vibes.keys()[0]
	picker.set_selected(PackedStringArray([id]))
	check(_name_buttons(picker)[0].disabled, "last X button disabled")
	picker.deselect(id)
	check_eq(picker.get_selected(), PackedStringArray([id]), "last pick kept")
	picker.free()


func test_no_vibe_means_no_music() -> void:
	var state: Node = Engine.get_main_loop().root.get_node("AppState")
	var saved: Array[String] = state.settings.vibes.duplicate()
	var before: ChipSong = state.song
	state.settings.vibes.clear()
	check(not state.can_make_music(), "cannot make music without a vibe")
	state.generate()
	check(state.song == before, "generate does nothing without a vibe")
	state.settings.vibes.assign(saved)
	check(state.can_make_music(), "can make music again")


func _name_buttons(picker: CatalogPicker) -> Array:
	var out := []
	for row in picker.get_node("%Strengths").get_children():
		if row.is_queued_for_deletion():
			continue
		for child in row.get_children():
			if child is Button and child.has_meta("remove"):
				out.append(child)
	return out


func _strength_sliders(picker: CatalogPicker) -> Array:
	var out := []
	for row in picker.get_node("%Strengths").get_children():
		if row.is_queued_for_deletion():
			continue
		for child in row.get_children():
			if child is HSlider:
				out.append(child)
	return out
