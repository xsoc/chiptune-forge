extends Control
## Sound FX mode, Kit screen: the sounds collected for one game.

const PLAY_ICON := preload("res://assets/ui/icon_play.svg")
const TRASH_ICON := preload("res://assets/ui/icon_trash.svg")


func _ready() -> void:
	%Name.text = AppState.kit.kit_name
	%Name.text_changed.connect(func(t: String) -> void: AppState.kit.kit_name = t)
	AppState.kit_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for child in %Rows.get_children():
		child.queue_free()
	var ids := AppState.kit.sounds.keys()
	%Empty.visible = ids.is_empty()
	for id in ids:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = SfxGenerator.c_id(id)
		label.theme_type_variation = &"MonoLabel"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var play := Button.new()
		play.icon = PLAY_ICON
		play.tooltip_text = "Play"
		play.custom_minimum_size = Vector2(44, 44)
		play.pressed.connect(func() -> void: AudioService.play_sfx(AppState.kit.sounds[id]))
		row.add_child(play)
		var remove := Button.new()
		remove.icon = TRASH_ICON
		remove.tooltip_text = "Remove from kit"
		remove.theme_type_variation = &"FlatButton"
		remove.custom_minimum_size = Vector2(44, 44)
		remove.pressed.connect(func() -> void: AppState.remove_from_kit(id))
		row.add_child(remove)
		%Rows.add_child(row)
	var first: String = ids[0] if not ids.is_empty() else "jump"
	%Code.text = "# Godot: add a ChipSfxPlayer node and assign the kit.\n$Sfx.play(\"%s\")\n$Sfx.play(\"%s\", 1.2)  # a little higher" % [first, first]
