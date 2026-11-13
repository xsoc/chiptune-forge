class_name TargetPicker
extends PanelContainer
## The first step on the Music and Sound FX screens: which machine the sound
## is for. It sets the shared AppState.target, so every preview, the Export
## screen and the other mode all follow it.

## Theme variation for the target buttons ("Chip" for music, "SfxChip" for SFX).
@export var chip_variation := &"Chip"

var _buttons: Dictionary = {}
var _later := ""


func _ready() -> void:
	_build()
	AppState.target_changed.connect(func(_t: String) -> void: refresh())
	refresh()


func refresh() -> void:
	for id in _buttons:
		_buttons[id].set_pressed_no_signal(id == AppState.target)
	if AppState.target == "gameboy":
		%Hint.text = "Previews play through an emulated Game Boy sound chip: 2 pulse, 1 wave, 1 noise."
	elif AppState.target == "nes":
		%Hint.text = "Previews play through an emulated NES sound chip: 2 pulse, 1 triangle, 1 noise."
	else:
		%Hint.text = "Plays on any voice, with no limits."
	%Hint.text += _later


func _build() -> void:
	var chips: Dictionary = AppState.catalog.chips
	var ids := chips.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return chips[a].get_meta("order", 0) < chips[b].get_meta("order", 0))
	var group := ButtonGroup.new()
	var later: Array[String] = []
	for id: String in ids:
		var chip: ChipProfile = chips[id]
		if not chip.available:
			later.append(chip.display_name)
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = chip_variation
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size.y = 40
		button.text = chip.display_name
		button.tooltip_text = "%s · %s\n%s" % [chip.display_name, chip.chip_name, chip.description]
		button.pressed.connect(func() -> void: AppState.set_target(id))
		%Buttons.add_child(button)
		_buttons[id] = button
	if not later.is_empty():
		_later = " %s come later." % " and ".join(later.slice(0, 2))
