class_name KeyboardStrip
extends Control
## On-screen piano keys (or drum pads) for playing live with touch or the
## mouse. Several fingers play chords; sliding a finger along the keys plays
## each key it reaches.

signal key_down(pitch: int)
signal key_up(pitch: int)

## The lowest key, a C works best.
var base_pitch := 48:
	set(v):
		base_pitch = clampi(v, 0, 108)
		_release_all()
		queue_redraw()
## Drum pads instead of keys: [{label, pitch}].
var pads: Array = []:
	set(v):
		pads = v
		_release_all()
		queue_redraw()
var colour := Color("f5b942")
## Pitches lit from outside (a MIDI keyboard playing).
var lit: Dictionary = {}

const WHITE_KEYS := [0, 2, 4, 5, 7, 9, 11]
const BLACK_KEYS := {1: 0, 3: 1, 6: 3, 8: 4, 10: 5}
const NAMES: PackedStringArray = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

## Finger (touch index, or -1 for the mouse) -> pitch held.
var _held: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


## How many octaves fit at a comfortable key width.
func octaves() -> int:
	return clampi(int(size.x / (7.0 * 40.0)), 1, 4)


func pitch_at(point: Vector2) -> int:
	if point.x < 0.0 or point.y < 0.0 or point.x >= size.x or point.y >= size.y:
		return -1
	if not pads.is_empty():
		var w := size.x / pads.size()
		return int(pads[clampi(int(point.x / w), 0, pads.size() - 1)]["pitch"])
	var count := octaves() * 7
	var white_w := size.x / count
	var white := clampi(int(point.x / white_w), 0, count - 1)
	var octave := white / 7
	if point.y < size.y * 0.6:
		# Black keys sit over the white ones.
		for semitone in BLACK_KEYS:
			var left := (octave * 7 + int(BLACK_KEYS[semitone]) + 1) * white_w - white_w * 0.3
			if point.x >= left and point.x < left + white_w * 0.6:
				return base_pitch + octave * 12 + int(semitone)
	return base_pitch + octave * 12 + int(WHITE_KEYS[white % 7])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_finger(event.index, event.position, event.pressed)
		accept_event()
	elif event is InputEventScreenDrag:
		_slide(event.index, event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not _emulated(event):
		_finger(-1, event.position, event.pressed)
		accept_event()
	elif event is InputEventMouseMotion and _held.has(-1) and not _emulated(event):
		_slide(-1, event.position)
		accept_event()


## Mouse events made up from touches: the touch events handle those.
func _emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION


func _finger(index: int, point: Vector2, pressed: bool) -> void:
	if pressed:
		var pitch := pitch_at(point)
		if pitch >= 0:
			_held[index] = pitch
			key_down.emit(pitch)
	elif _held.has(index):
		key_up.emit(int(_held[index]))
		_held.erase(index)
	queue_redraw()


func _slide(index: int, point: Vector2) -> void:
	if not _held.has(index):
		return
	var pitch := pitch_at(point)
	if pitch != int(_held[index]):
		key_up.emit(int(_held[index]))
		if pitch >= 0:
			_held[index] = pitch
			key_down.emit(pitch)
		else:
			_held.erase(index)
		queue_redraw()


func _release_all() -> void:
	for index in _held:
		key_up.emit(int(_held[index]))
	_held.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release_all()


func _is_down(pitch: int) -> bool:
	return lit.has(pitch) or _held.values().has(pitch)


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color("101116"))
	if not pads.is_empty():
		var w := size.x / pads.size()
		for i in pads.size():
			var rect := Rect2(i * w + 3.0, 3.0, w - 6.0, size.y - 6.0)
			var down := _is_down(int(pads[i]["pitch"]))
			draw_rect(rect, colour if down else Color("2a2c36"))
			draw_string(font, Vector2(rect.position.x + 6.0, rect.end.y - 8.0), str(pads[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8.0, 12,
				Color("101116") if down else Color.WHITE)
		return
	var count := octaves() * 7
	var white_w := size.x / count
	for i in count:
		var pitch: int = base_pitch + (i / 7) * 12 + int(WHITE_KEYS[i % 7])
		var rect := Rect2(i * white_w + 1.0, 0.0, white_w - 2.0, size.y)
		draw_rect(rect, colour if _is_down(pitch) else Color("d8dae2"))
		if i % 7 == 0:
			draw_string(font, Vector2(rect.position.x + 4.0, size.y - 8.0), "%s%d" % [NAMES[pitch % 12], pitch / 12 - 1], HORIZONTAL_ALIGNMENT_LEFT, white_w, 11, Color("101116"))
	for octave in octaves():
		for semitone in BLACK_KEYS:
			var pitch: int = base_pitch + octave * 12 + int(semitone)
			var left := (octave * 7 + int(BLACK_KEYS[semitone]) + 1) * white_w - white_w * 0.3
			draw_rect(Rect2(left, 0.0, white_w * 0.6, size.y * 0.6), colour if _is_down(pitch) else Color("1b1c24"))
