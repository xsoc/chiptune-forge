class_name TargetPicker
extends PanelContainer
## The first step on the Music and Sound FX screens: which machine the sound
## is for. It sets the shared AppState.target, so every preview, the Export
## screen and the other mode all follow it.

## Theme variation for the target buttons ("Chip" for music, "SfxChip" for SFX).
@export var chip_variation := &"Chip"

var _buttons: Dictionary = {}
var _later := ""
var _card: OptionButton
var _card_row: HBoxContainer


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
	elif AppState.target == "sms":
		%Hint.text = "Previews play through an emulated Master System sound chip: 3 square, 1 noise."
	elif AppState.target == "genesis":
		%Hint.text = "Previews play through the Mega Drive's emulated sound chips: 6 FM, 3 square, 1 noise."
	elif AppState.target == "snes":
		%Hint.text = "Previews play through an emulated SNES sound chip: 8 sample voices with echo."
	elif AppState.target == "pce":
		%Hint.text = "Previews play through the PC Engine's emulated sound chip: 6 wavetable channels, 2 with noise."
	elif AppState.target == "msx":
		%Hint.text = "Previews play through an emulated AY-3-8910, the MSX and ZX Spectrum 128 sound chip: 3 square and noise."
	elif AppState.target == "gba":
		%Hint.text = "Previews play through an emulation of Maxmod's mixer on the Game Boy Advance: 8-bit samples on 7 channels."
	elif AppState.target == "pc":
		%Hint.text = "Previews play through the %s's emulated sound: %s" % [PcCards.name_of(AppState.pc_card), PcCards.INFO[AppState.pc_card]["description"].get_slice(" Exports", 0)]
	elif AppState.target == "c64":
		%Hint.text = "Previews play through an emulated SID, the Commodore 64 sound chip: 3 voices with their own waveforms and envelopes."
	else:
		%Hint.text = "Plays on any voice, with no limits."
	%Hint.text += _later
	_card_row.visible = AppState.target == "pc"
	_card.select(maxi(PcCards.CARDS.find(AppState.pc_card), 0))


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
	_build_cards()
	if not later.is_empty():
		_later = " %s come later." % " and ".join(later.slice(0, 2))


## The sound card choice, shown while the DOS PC is picked.
func _build_cards() -> void:
	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = "Sound card"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"MutedLabel"
	_card_row.add_child(label)
	_card = OptionButton.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(200, 40)
	for card in PcCards.CARDS:
		_card.add_item("%s (%d)" % [PcCards.name_of(card), PcCards.INFO[card]["year"]])
	_card.item_selected.connect(func(index: int) -> void: AppState.set_pc_card(PcCards.CARDS[index]))
	_card_row.add_child(_card)
	%Buttons.get_parent().add_child(_card_row)
	%Buttons.get_parent().move_child(_card_row, %Buttons.get_index() + 1)
