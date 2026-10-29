class_name CatalogPicker
extends VBoxContainer
## Search, group tabs and a wrap of chips for picking from a long catalogue:
## vibes, styles or sound effect presets. Single select, or multi select with
## a blend strength per pick.

signal selection_changed(ids: PackedStringArray)
signal strengths_changed(strengths: Array[float])

const ALL_TAB := "All"

@export var title := "Vibe"
@export var hint := ""
@export var multi_select := false
@export_range(1, 8) var max_selected := 3
@export var show_strengths := false
@export var chip_variation := &"Chip"
@export var slider_variation := &""
@export var chips_min_height := 180

var _items: Dictionary = {}
var _groups := PackedStringArray()
var _selected := PackedStringArray()
var _strengths: Array[float] = []
var _strength_sliders: Array[HSlider] = []
var _strength_labels: Array[Label] = []
var _catalog: Catalog


func _ready() -> void:
	%Title.text = title
	%Hint.text = hint
	%Hint.visible = hint != ""
	%ChipScroll.custom_minimum_size.y = chips_min_height
	%Search.text_changed.connect(func(_t: String) -> void: _rebuild_chips())
	%Tabs.tab_changed.connect(func(_i: int) -> void: _rebuild_chips())


func setup(catalog: Catalog, items: Dictionary, groups: PackedStringArray) -> void:
	_catalog = catalog
	_items = items
	_groups = groups
	%Search.placeholder_text = "Search %d %s" % [items.size(), title.to_lower() + ("s" if not title.ends_with("s") else "")]
	%Tabs.clear_tabs()
	%Tabs.add_tab(ALL_TAB)
	for group in groups:
		%Tabs.add_tab(group)
	_rebuild_chips()


func set_selected(ids: PackedStringArray, strengths: Array[float] = []) -> void:
	var same_ids := ids == _selected
	_selected = ids.duplicate()
	_strengths = strengths.duplicate()
	while _strengths.size() < _selected.size():
		_strengths.append(100.0)
	_sync_chips()
	# Rebuilding would free a slider the user may be dragging right now.
	if same_ids and _strength_sliders.size() == _selected.size():
		for i in _strength_sliders.size():
			_strength_sliders[i].set_value_no_signal(_strengths[i])
			_strength_labels[i].text = "%d" % _strengths[i]
	else:
		_rebuild_strengths()


func get_selected() -> PackedStringArray:
	return _selected


func get_strengths() -> Array[float]:
	return _strengths


## Shows the tab holding [param id] and scrolls it into view.
func reveal(id: String) -> void:
	var item: Resource = _items.get(id)
	if item == null:
		return
	var index := _groups.find(item.group)
	if index >= 0 and %Tabs.current_tab != index + 1:
		%Tabs.current_tab = index + 1


func _visible_items() -> Array:
	var query: String = %Search.text
	if query.strip_edges() != "":
		return _catalog.search(_items, query)
	var tab: int = %Tabs.current_tab
	if tab <= 0:
		return _catalog.search(_items, "")
	return _catalog.in_group(_items, _groups[tab - 1])


func _rebuild_chips() -> void:
	for child in %Chips.get_children():
		child.queue_free()
	for item in _visible_items():
		var chip := Button.new()
		chip.text = item.display_name
		chip.tooltip_text = item.description
		chip.toggle_mode = true
		chip.theme_type_variation = chip_variation
		chip.focus_mode = Control.FOCUS_ALL
		chip.set_meta("id", item.id)
		chip.button_pressed = _selected.has(item.id)
		chip.toggled.connect(_on_chip_toggled.bind(item.id))
		%Chips.add_child(chip)


func _sync_chips() -> void:
	for chip in %Chips.get_children():
		if chip is Button:
			chip.set_pressed_no_signal(_selected.has(chip.get_meta("id")))


func _on_chip_toggled(pressed: bool, id: String) -> void:
	if not multi_select:
		_selected = PackedStringArray([id])
		_strengths = [100.0]
	elif pressed and not _selected.has(id):
		if _selected.size() >= max_selected:
			_selected.remove_at(_selected.size() - 1)
			_strengths.remove_at(_strengths.size() - 1)
		_selected.append(id)
		_strengths.append(100.0 if _selected.size() == 1 else 50.0)
	elif not pressed and _selected.has(id):
		if _selected.size() == 1:
			# Always keep one selected.
			_sync_chips()
			return
		var index := _selected.find(id)
		_selected.remove_at(index)
		_strengths.remove_at(index)
	_sync_chips()
	_rebuild_strengths()
	selection_changed.emit(_selected)


func _rebuild_strengths() -> void:
	for child in %Strengths.get_children():
		child.queue_free()
	_strength_sliders.clear()
	_strength_labels.clear()
	%Strengths.visible = show_strengths and _selected.size() > 0
	if not show_strengths:
		return
	for i in _selected.size():
		var item: Resource = _items.get(_selected[i])
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = item.display_name if item else _selected[i]
		label.custom_minimum_size.x = 96
		label.clip_text = true
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = _strengths[i]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.y = 28
		slider.tooltip_text = "Blend strength"
		if slider_variation != &"":
			slider.theme_type_variation = slider_variation
		slider.value_changed.connect(_on_strength_changed.bind(i))
		row.add_child(slider)
		_strength_sliders.append(slider)
		var value := Label.new()
		value.theme_type_variation = &"MonoLabel"
		value.text = "%d" % _strengths[i]
		value.custom_minimum_size.x = 30
		_strength_labels.append(value)
		slider.value_changed.connect(func(v: float) -> void: value.text = "%d" % v)
		row.add_child(value)
		%Strengths.add_child(row)


func _on_strength_changed(v: float, index: int) -> void:
	if index < _strengths.size():
		_strengths[index] = v
		strengths_changed.emit(_strengths)
