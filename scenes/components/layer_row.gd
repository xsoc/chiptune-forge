class_name LayerRow
extends HBoxContainer
## One layer on the Layers screen: lock, regenerate and mute.

signal lock_toggled(layer: String, locked: bool)
signal regenerate_pressed(layer: String)
signal mute_toggled(layer: String, muted: bool)

const LOCK_ICON := preload("res://assets/ui/icon_lock.svg")
const UNLOCK_ICON := preload("res://assets/ui/icon_unlock.svg")

var layer := ""


func setup(layer_name: String, colour: Color, channels_text: String) -> void:
	layer = layer_name
	%Swatch.color = colour
	%Name.text = layer_name
	%Channels.text = channels_text


func _ready() -> void:
	%Lock.toggled.connect(func(on: bool) -> void:
		%Lock.icon = LOCK_ICON if on else UNLOCK_ICON
		lock_toggled.emit(layer, on))
	%Regenerate.pressed.connect(func() -> void: regenerate_pressed.emit(layer))
	%Play.toggled.connect(func(on: bool) -> void: mute_toggled.emit(layer, not on))


func set_locked(locked: bool) -> void:
	%Lock.set_pressed_no_signal(locked)
	%Lock.icon = LOCK_ICON if locked else UNLOCK_ICON
