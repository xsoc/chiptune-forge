class_name SeedField
extends HBoxContainer
## Seed text with a dice button. Same settings and same seed give the same song.

signal seed_submitted(text: String)
signal dice_pressed

@export var sfx_style := false


func _ready() -> void:
	%Edit.text_submitted.connect(func(t: String) -> void: seed_submitted.emit(t))
	%Edit.focus_exited.connect(func() -> void: seed_submitted.emit(%Edit.text))
	%Dice.pressed.connect(func() -> void: dice_pressed.emit())


func set_seed_text(text: String) -> void:
	%Edit.text = text
