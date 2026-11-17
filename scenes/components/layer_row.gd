class_name LayerRow
extends HBoxContainer
## One layer on the Layers screen: synth engine, lock, regenerate and mute.

signal lock_toggled(layer: String, locked: bool)
signal regenerate_pressed(layer: String)
signal mute_toggled(layer: String, muted: bool)
## [param choice] is "" for the song's engine, or one of
## [constant SynthEngines.CHOICES].
signal engine_selected(layer: String, choice: String)

## The engine menu: "" follows the song's Synth setting.
const ENGINE_ITEMS := [["", "Song"], ["chip", "Chip"], ["analog", "Analog"], ["fm", "FM"], ["wavetable", "Wave"], ["sampled", "Sampled"]]

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
	for item in ENGINE_ITEMS:
		%Engine.add_item(item[1])
		%Engine.set_item_metadata(%Engine.item_count - 1, item[0])
	%Engine.item_selected.connect(func(index: int) -> void: engine_selected.emit(layer, str(%Engine.get_item_metadata(index))))


func set_engine_choice(choice: String) -> void:
	if %Engine.item_count == 0:
		return
	for i in %Engine.item_count:
		if str(%Engine.get_item_metadata(i)) == choice:
			%Engine.select(i)
			return
	%Engine.select(0)


func set_locked(locked: bool) -> void:
	%Lock.set_pressed_no_signal(locked)
	%Lock.icon = LOCK_ICON if locked else UNLOCK_ICON
