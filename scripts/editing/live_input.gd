class_name LiveInput
extends Node
## Turns MIDI keyboards and the computer keyboard into note events.
##
## MIDI works on Windows, macOS, Linux and in browsers with Web MIDI
## (Chrome, Edge, Firefox; the browser asks first). Phones have no MIDI in
## Godot, so they use the on-screen keys. The computer keyboard plays two
## rows like a piano: Z to M (and S, D, G, H, J for the black keys) from
## the base octave, Q to U (2, 3, 5, 6, 7) an octave up.

signal note_on(pitch: int, velocity: int)
signal note_off(pitch: int)
signal devices_changed(names: PackedStringArray)

const KEY_ROWS := {
	KEY_Z: 0, KEY_S: 1, KEY_X: 2, KEY_D: 3, KEY_C: 4, KEY_V: 5, KEY_G: 6,
	KEY_B: 7, KEY_H: 8, KEY_N: 9, KEY_J: 10, KEY_M: 11, KEY_COMMA: 12,
	KEY_Q: 12, KEY_2: 13, KEY_W: 14, KEY_3: 15, KEY_E: 16, KEY_R: 17,
	KEY_5: 18, KEY_T: 19, KEY_6: 20, KEY_Y: 21, KEY_7: 22, KEY_U: 23, KEY_I: 24,
}

## Whether events are passed on (the editor turns this off while hidden).
var enabled := true
## The computer keyboard's lowest note.
var base_pitch := 48
var midi_open := false

var _keys_down: Dictionary = {}


## Starts listening to MIDI devices. In a browser this asks for permission,
## and the device list fills in a moment later.
func open_midi() -> void:
	if not midi_open:
		OS.open_midi_inputs()
		midi_open = true
	devices_changed.emit(devices())


func close_midi() -> void:
	if midi_open:
		OS.close_midi_inputs()
		midi_open = false
	devices_changed.emit(devices())


func devices() -> PackedStringArray:
	return OS.get_connected_midi_inputs() if midi_open else PackedStringArray()


func _exit_tree() -> void:
	if midi_open:
		OS.close_midi_inputs()
		midi_open = false


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMIDI:
		handle_midi(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not event.echo and not event.ctrl_pressed and not event.meta_pressed and not event.alt_pressed:
		if _typing():
			return
		var key: int = event.physical_keycode
		if not KEY_ROWS.has(key):
			return
		var pitch: int = clampi(base_pitch + int(KEY_ROWS[key]), 0, 127)
		if event.pressed and not _keys_down.has(key):
			_keys_down[key] = pitch
			note_on.emit(pitch, 100)
		elif not event.pressed and _keys_down.has(key):
			note_off.emit(int(_keys_down[key]))
			_keys_down.erase(key)
		get_viewport().set_input_as_handled()


## Handles one MIDI message. Note on with velocity 0 is a note off, as the
## MIDI standard says.
func handle_midi(event: InputEventMIDI) -> void:
	match event.message:
		MIDI_MESSAGE_NOTE_ON:
			if event.velocity > 0:
				note_on.emit(event.pitch, event.velocity)
			else:
				note_off.emit(event.pitch)
		MIDI_MESSAGE_NOTE_OFF:
			note_off.emit(event.pitch)


func release_keys() -> void:
	for key in _keys_down:
		note_off.emit(int(_keys_down[key]))
	_keys_down.clear()


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or focus is SpinBox
