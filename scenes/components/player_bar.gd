class_name PlayerBar
extends PanelContainer
## Play and stop, song title, position and loop toggle. Pinned to the bottom
## of the screen on phones.

signal play_toggled
signal seek_requested(fraction: float)
signal loop_toggled(on: bool)

const PLAY_ICON := preload("res://assets/ui/icon_play.svg")
const STOP_ICON := preload("res://assets/ui/icon_stop.svg")

var _dragging := false
var _compact := false


func _ready() -> void:
	%Play.pressed.connect(func() -> void: play_toggled.emit())
	%Loop.toggled.connect(func(on: bool) -> void: loop_toggled.emit(on))
	%Position.drag_started.connect(func() -> void: _dragging = true)
	%Position.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		seek_requested.emit(%Position.value / maxf(%Position.max_value, 0.001)))


func set_song_info(title: String, info: String) -> void:
	%Title.text = title
	%Info.text = info


func set_playing(playing: bool) -> void:
	%Play.icon = STOP_ICON if playing else PLAY_ICON
	%Play.tooltip_text = "Stop" if playing else "Play"


func set_play_enabled(enabled: bool) -> void:
	%Play.disabled = not enabled
	%Position.editable = enabled
	%Play.tooltip_text = "Play" if enabled else "Pick a vibe to play music"


func set_time(seconds: float, length: float) -> void:
	if _dragging:
		return
	%Position.max_value = maxf(length, 0.001)
	%Position.set_value_no_signal(clampf(seconds, 0.0, length))
	%Time.text = _clock(seconds) if _compact else "%s / %s" % [_clock(seconds), _clock(length)]


## Narrower layout for phones: shorter time label and smaller minimums.
func set_compact(on: bool) -> void:
	_compact = on
	$Row/Text.custom_minimum_size.x = 84 if on else 120
	%Position.custom_minimum_size.x = 48 if on else 80
	set_time(%Position.value, %Position.max_value)


func is_loop_on() -> bool:
	return %Loop.button_pressed


func set_loop(on: bool) -> void:
	%Loop.set_pressed_no_signal(on)


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
