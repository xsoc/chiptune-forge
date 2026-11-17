class_name LiveSynth
extends Node
## Plays notes as they are pressed, for the on-screen keys, MIDI keyboards
## and auditioning notes in the editor. Uses the same [ChipVoice] as the
## song player, so a part sounds the same live as in the song.

const POLYPHONY := 8
const RATE := 44100
const WEB_RATE := 32000
## Kept short so a key sounds as soon as it is pressed.
const BUFFER := 0.05
const WEB_BUFFER := 0.1
## How long a note held "forever" stays gated, in seconds.
const HOLD := 60.0
const CLICK := {"wave": "noise", "short": true, "attack": 0.0005, "decay": 0.03, "sustain": 0.0, "release": 0.01, "volume": 0.5}

var gain := 0.5

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _voices: Array[ChipVoice] = []
## Voice index -> the key holding it (or -1 when released).
var _keys: PackedInt32Array = []
var _rate := RATE
var _left := PackedFloat32Array()
var _right := PackedFloat32Array()
var _send := PackedFloat32Array()


func _ready() -> void:
	_rate = WEB_RATE if OS.has_feature("web") else RATE
	for i in POLYPHONY:
		_voices.append(ChipVoice.new(float(_rate)))
		_keys.append(-1)
	_player = AudioStreamPlayer.new()
	_player.name = "Output"
	add_child(_player)


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	_playback.push_buffer(render(frames))
	if not is_sounding():
		# Stop pushing silence once everything has died away.
		_player.stop()
		_playback = null


## Starts [param pitch] with [param instrument] (a song instrument). It holds
## until [method note_off] with the same [param key], or for [param seconds]
## when that is above 0.
func note_on(key: int, pitch: float, instrument: Dictionary, velocity := 1.0, seconds := 0.0) -> void:
	var index := _free_voice(key)
	var gate := int((seconds if seconds > 0.0 else HOLD) * _rate)
	_voices[index].note_on(pitch, gate, instrument, clampf(velocity, 0.0, 1.0), PackedFloat32Array())
	_keys[index] = key if seconds <= 0.0 else -1
	_start()


func note_off(key: int) -> void:
	for i in _keys.size():
		if _keys[i] == key:
			_voices[i].release()
			_keys[i] = -1


func all_off() -> void:
	for i in _voices.size():
		_voices[i].release()
		_keys[i] = -1


## A metronome click; [param accent] for the first beat of a bar.
func click(accent: bool) -> void:
	note_on(-2, 96.0 if accent else 84.0, CLICK, 1.0 if accent else 0.6, 0.02)


func is_sounding() -> bool:
	for v in _voices:
		if v.is_active():
			return true
	return false


## Mixes [param count] frames of every sounding voice.
func render(count: int) -> PackedVector2Array:
	if _left.size() != count:
		_left.resize(count)
		_right.resize(count)
		_send.resize(count)
	_left.fill(0.0)
	_right.fill(0.0)
	for v in _voices:
		if v.is_active():
			v.render(_left, _right, _send, 0, count, 1.0, 1.0)
	var out := PackedVector2Array()
	out.resize(count)
	for i in count:
		out[i] = Vector2(clampf(_left[i] * gain, -1.0, 1.0), clampf(_right[i] * gain, -1.0, 1.0))
	return out


func _free_voice(key: int) -> int:
	# The same key retriggers its own voice.
	for i in _keys.size():
		if _keys[i] == key and key >= 0:
			return i
	var oldest := 0
	for i in _voices.size():
		if not _voices[i].is_active():
			return i
		if _voices[i].age > _voices[oldest].age:
			oldest = i
	return oldest


func _start() -> void:
	if _playback != null or _player == null or not is_inside_tree():
		return
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _rate
	generator.buffer_length = WEB_BUFFER if OS.has_feature("web") else BUFFER
	_player.stream = generator
	_player.play()
	_playback = _player.get_stream_playback()
