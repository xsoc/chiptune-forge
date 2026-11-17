extends Control
## Saved songs and sounds, with search, favourites and delete, and the
## community packs installed.

signal entry_opened(kind: String)

const STAR_ICON := preload("res://assets/ui/icon_star.svg")
const TRASH_ICON := preload("res://assets/ui/icon_trash.svg")


func _ready() -> void:
	if %Kind.selected < 0:
		%Kind.select(0)
	%Search.text_changed.connect(func(_t: String) -> void: _rebuild())
	%Kind.item_selected.connect(func(_i: int) -> void: _rebuild())
	AppState.library_changed.connect(_rebuild)
	AppState.catalog_changed.connect(_rebuild_packs)
	%AddPack.pressed.connect(func() -> void:
		FileDelivery.pick_text(PackedStringArray([ChipPack.EXTENSION, "json"]), "Chiptune Forge pack", self, add_pack))
	%OpenProject.pressed.connect(func() -> void:
		FileDelivery.pick_text(PackedStringArray([ProjectFile.EXTENSION]), "Chiptune Forge project", self, open_project))
	_rebuild()
	_rebuild_packs()


## Opens a .cforge project's text and says how it went.
func open_project(text: String, file_name := "") -> void:
	var result := AppState.open_project(text)
	if result.begins_with("error: "):
		%ProjectStatus.text = "Could not open %s: %s" % [file_name if file_name != "" else "the project", result.trim_prefix("error: ")]
		return
	%ProjectStatus.text = "Opened %s." % (file_name if file_name != "" else "the project")
	entry_opened.emit(result)


## Installs a pack from a file's text and says how it went.
func add_pack(text: String, file_name := "") -> void:
	var error := AppState.install_pack(text)
	%PackStatus.visible = true
	if error != "":
		%PackStatus.text = "Could not add %s: %s" % [file_name if file_name != "" else "the pack", error]
	else:
		var pack: ChipPack = AppState.catalog.packs[-1]
		%PackStatus.text = "Added %s: %s." % [pack.name, pack.summary()]


func _rebuild_packs() -> void:
	for child in %PackRows.get_children():
		child.queue_free()
	for pack in AppState.catalog.packs:
		var row := HBoxContainer.new()
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := Label.new()
		title.text = pack.name
		title.clip_text = true
		text.add_child(title)
		var info := Label.new()
		var by := " by %s" % pack.author if pack.author != "" else ""
		var licence := " · %s" % pack.license if pack.license != "" else ""
		info.text = "%s%s%s" % [pack.summary(), by, licence]
		info.theme_type_variation = &"MutedLabel"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(info)
		row.add_child(text)
		var remove := Button.new()
		remove.icon = TRASH_ICON
		remove.theme_type_variation = &"FlatButton"
		remove.tooltip_text = "Remove this pack"
		remove.custom_minimum_size = Vector2(44, 44)
		var pack_name := pack.name
		remove.pressed.connect(func() -> void:
			AppState.remove_pack(pack_name)
			%PackStatus.visible = true
			%PackStatus.text = "Removed %s." % pack_name)
		row.add_child(remove)
		%PackRows.add_child(row)


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
