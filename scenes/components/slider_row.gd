@tool
class_name SliderRow
extends VBoxContainer
## A labelled slider with its value shown on the right.

signal value_changed(value: float)

@export var label_text := "Value":
	set(v):
		label_text = v
		if is_node_ready():
			%Label.text = v
@export var min_value := 0.0
@export var max_value := 100.0
@export var step := 1.0
@export var value := 50.0:
	set(v):
		value = v
		if is_node_ready():
			%Slider.set_value_no_signal(v)
			_update_text()
## Format for the value, for example "%d%%" or "%.2f".
@export var value_format := "%d"
@export var sfx_style := false


func _ready() -> void:
	%Label.text = label_text
	%Slider.min_value = min_value
	%Slider.max_value = max_value
	%Slider.step = step
	%Slider.set_value_no_signal(value)
	if sfx_style:
		%Slider.theme_type_variation = &"SfxSlider"
	%Slider.value_changed.connect(_on_slider_value_changed)
	_update_text()


func set_value_silently(v: float) -> void:
	value = v


func _on_slider_value_changed(v: float) -> void:
	value = v
	_update_text()
	value_changed.emit(v)


func _update_text() -> void:
	%Value.text = value_format % value
