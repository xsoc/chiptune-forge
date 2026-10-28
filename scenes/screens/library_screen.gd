extends Control
## Saved songs and sounds, with search, favourites and delete.

signal entry_opened(kind: String)

const STAR_ICON := preload("res://assets/ui/icon_star.svg")
const TRASH_ICON := preload("res://assets/ui/icon_trash.svg")


func _ready() -> void:
	%Search.text_changed.connect(func(_t: String) -> void: _rebuild())
	%Kind.item_selected.connect(func(_i: int) -> void: _rebuild())
	AppState.library_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in %Rows.get_children():
		child.queue_free()
	var query: String = %Search.text.strip_edges().to_lower()
	var shown := 0
	for i in AppState.library.size():
		var entry: Dictionary = AppState.library[i]
		match %Kind.selected:
			1:
				if entry["kind"] != "song":
					continue
			2:
				if entry["kind"] != "sfx":
					continue
			3:
				if not entry.get("favourite", false):
					continue
		if query != "" and not str(entry["name"]).to_lower().contains(query):
			continue
		%Rows.add_child(_row(i, entry))
		shown += 1
	%Empty.visible = shown == 0


func _row(index: int, entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var badge := Label.new()
	badge.text = "SONG" if entry["kind"] == "song" else "SFX"
	badge.theme_type_variation = &"SectionLabel"
	badge.custom_minimum_size.x = 44
	row.add_child(badge)
	var open := Button.new()
	open.text = str(entry["name"])
	open.theme_type_variation = &"FlatButton"
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.clip_text = true
	open.tooltip_text = "Open (saved %s)" % str(entry.get("created", "")).replace("T", " ")
	open.custom_minimum_size.y = 44
	open.pressed.connect(func() -> void:
		AppState.open_library_entry(index)
		entry_opened.emit(entry["kind"]))
	row.add_child(open)
	var star := Button.new()
	star.icon = STAR_ICON
	star.toggle_mode = true
	star.button_pressed = entry.get("favourite", false)
	star.theme_type_variation = &"FlatButton"
	star.tooltip_text = "Favourite"
	star.custom_minimum_size = Vector2(44, 44)
	star.toggled.connect(func(_on: bool) -> void: AppState.toggle_favourite(index))
	row.add_child(star)
	var remove := Button.new()
	remove.icon = TRASH_ICON
	remove.theme_type_variation = &"FlatButton"
	remove.tooltip_text = "Delete"
	remove.custom_minimum_size = Vector2(44, 44)
	remove.pressed.connect(func() -> void: AppState.delete_library_entry(index))
	row.add_child(remove)
	return row
