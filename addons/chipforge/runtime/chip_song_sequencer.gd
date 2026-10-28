class_name ChipSongSequencer
extends RefCounted
## Plays a [ChipSong] by rendering stereo frames on demand.
##
## Used by [ChipMusicPlayer] for live playback and by exporters for offline
## rendering. Each channel has its own gain, so adaptive layers can fade in and
## out while the song plays.

enum EventType { BEAT, BAR, SECTION, CUE, LOOPED, FINISHED }

const MAX_POLYPHONY := 4

var song: ChipSong
var mix_rate := 44100
var looping := true
var finished := false
## Current position in frames from the start of the song.
var position := 0
var master_gain := 0.55
## Events crossed by the last [method render] call, as [code][type, value][/code] pairs.
var events: Array = []

var _step_frames := 1.0
var _length_frames := 0
var _loop_start_frame := 0
var _loop_end_frame := 0
var _instruments: Array = []
var _channels: Array[_Channel] = []

# Flattened note timeline, sorted by start frame.
var _ev_frame := PackedInt64Array()
var _ev_channel := PackedInt32Array()
var _ev_pitch := PackedFloat32Array()
var _ev_gate := PackedInt32Array()
var _ev_velocity := PackedFloat32Array()
var _ev_instrument := PackedInt32Array()
var _ev_arp: Array[PackedFloat32Array] = []
var _ev_index := 0

var _section_steps: Dictionary = {} # step -> section name
var _cue_steps: Dictionary = {} # step -> Array of cue names
var _last_step := -1

var _left := PackedFloat32Array()
var _right := PackedFloat32Array()
var _send := PackedFloat32Array()
var _echo_l := PackedFloat32Array()
var _echo_r := PackedFloat32Array()
var _echo_pos := 0
var _echo_level := 0.0
var _echo_feedback := 0.35


func _init(chip_song: ChipSong, rate := 44100) -> void:
	song = chip_song
	mix_rate = rate
	_build()


func get_length_frames() -> int:
	return _length_frames


func get_loop_start_frame() -> int:
	return _loop_start_frame


func get_loop_end_frame() -> int:
	return _loop_end_frame


func get_step_frames() -> float:
	return _step_frames


func get_position_step() -> float:
	return position / _step_frames


func get_channel_count() -> int:
	return _channels.size()


## Returns the loudest envelope level on a channel, 0 to 1, for meters.
func get_channel_level(channel: int) -> float:
	var best := 0.0
	for voice in _channels[channel].voices:
		best = maxf(best, voice.level)
	return best * _channels[channel].gain


## Sets a channel's gain, fading over [param fade_frames].
func set_channel_gain(channel: int, gain: float, fade_frames := 0) -> void:
	if channel < 0 or channel >= _channels.size():
		return
	var ch := _channels[channel]
	ch.target_gain = gain
	if fade_frames <= 0:
		ch.gain = gain
		ch.gain_step = 0.0
	else:
		ch.gain_step = absf(gain - ch.gain) / float(fade_frames)


func set_channel_muted(channel: int, muted: bool) -> void:
	if channel >= 0 and channel < _channels.size():
		_channels[channel].muted = muted


## Jumps to a step. With [param kill] on, ringing notes are silenced.
func seek_step(step: float, kill := true) -> void:
	position = clampi(int(step * _step_frames), 0, _length_frames)
	_ev_index = _find_event(position)
	_last_step = int(step) - 1
	finished = false
	if not kill:
		return
	for ch in _channels:
		for voice in ch.voices:
			voice.kill()


## Renders [param count] frames and advances the song.
func render(count: int) -> PackedVector2Array:
	events.clear()
	if _left.size() != count:
		_left.resize(count)
		_right.resize(count)
		_send.resize(count)
	_left.fill(0.0)
	_right.fill(0.0)
	_send.fill(0.0)
	var done := 0
	while done < count:
		var n := count - done
		if not finished:
			var boundary := _loop_end_frame if looping else _length_frames
			n = mini(n, maxi(boundary - position, 0))
			if _ev_index < _ev_frame.size():
				n = mini(n, maxi(int(_ev_frame[_ev_index] - position), 0))
		if n > 0:
			_render_voices(done, n)
			position += n
			done += n
		if not finished:
			_fire_events()
			_check_wrap()
		if finished and n == 0:
			_render_voices(done, count - done)
			done = count
	_apply_echo(count)
	var out := PackedVector2Array()
	out.resize(count)
	var gain := master_gain
	for i in count:
		out[i] = Vector2(_soft_clip(_left[i] * gain), _soft_clip(_right[i] * gain))
	return out


## Renders the whole song once (or [param loops] times through the loop) for
## export. Includes the release tail when the song does not loop.
func render_all(loops := 1, tail_seconds := 1.5) -> PackedVector2Array:
	seek_step(0)
	var total := _loop_start_frame + (_loop_end_frame - _loop_start_frame) * maxi(loops, 1)
	if not looping:
		total = _length_frames + int(tail_seconds * mix_rate)
	var out := PackedVector2Array()
	var block := 4096
	while out.size() < total:
		var chunk := render(mini(block, total - out.size()))
		if chunk.is_empty():
			break
		out.append_array(chunk)
	return out


static func _soft_clip(x: float) -> float:
	if x > 1.0:
		return 1.0
	if x < -1.0:
		return -1.0
	return x * (1.5 - 0.5 * x * x)


func _render_voices(offset: int, count: int) -> void:
	if count <= 0:
		return
	for ch in _channels:
		if ch.gain != ch.target_gain:
			ch.gain = move_toward(ch.gain, ch.target_gain, ch.gain_step * count) if ch.gain_step > 0.0 else ch.target_gain
		var g := 0.0 if ch.muted else ch.gain * ch.volume
		for voice in ch.voices:
			if voice.is_active():
				voice.render(_left, _right, _send, offset, count, ch.pan_l * g, ch.pan_r * g)


func _fire_events() -> void:
	while _ev_index < _ev_frame.size() and _ev_frame[_ev_index] <= position:
		var i := _ev_index
		_ev_index += 1
		var ch := _channels[_ev_channel[i]]
		var inst_index := _ev_instrument[i]
		if inst_index < 0:
			inst_index = ch.instrument
		var inst: Dictionary = _instruments[inst_index] if inst_index < _instruments.size() else {}
		var voice := _pick_voice(ch, inst)
		voice.note_on(_ev_pitch[i], _ev_gate[i], inst, _ev_velocity[i], _ev_arp[i])
	var step := int(position / _step_frames)
	if step != _last_step:
		var spb := song.get_steps_per_beat()
		var bar_steps := spb * song.get_beats_per_bar()
		for s in range(_last_step + 1, step + 1):
			if s % spb == 0:
				events.append([EventType.BEAT, s / spb])
			if s % bar_steps == 0:
				events.append([EventType.BAR, s / bar_steps])
			if _section_steps.has(s):
				events.append([EventType.SECTION, _section_steps[s]])
			for cue_name in _cue_steps.get(s, []):
				events.append([EventType.CUE, cue_name])
		_last_step = step


func _check_wrap() -> void:
	if looping and position >= _loop_end_frame:
		position = _loop_start_frame
		_ev_index = _find_event(position)
		_last_step = int(position / _step_frames) - 1
		events.append([EventType.LOOPED, 0])
		_fire_events()
	elif not looping and position >= _length_frames:
		finished = true
		events.append([EventType.FINISHED, 0])


func _pick_voice(ch: _Channel, inst: Dictionary) -> ChipVoice:
	# Mono channels reuse their voice so glide and retrigger work.
	if ch.voices.size() == 1:
		return ch.voices[0]
	var oldest: ChipVoice = ch.voices[0]
	for voice in ch.voices:
		if not voice.is_active():
			return voice
		if voice.age > oldest.age:
			oldest = voice
	return oldest


func _apply_echo(count: int) -> void:
	if _echo_level <= 0.0:
		return
	var size := _echo_l.size()
	var pos := _echo_pos
	var fb := _echo_feedback
	var wet := _echo_level
	for i in count:
		var dl := _echo_l[pos]
		var dr := _echo_r[pos]
		_left[i] += dl * wet
		_right[i] += dr * wet
		# Ping-pong: each repeat swaps sides.
		_echo_l[pos] = _send[i] + dr * fb
		_echo_r[pos] = dl * fb
		pos += 1
		if pos >= size:
			pos = 0
	_echo_pos = pos


func _find_event(frame: int) -> int:
	var lo := 0
	var hi := _ev_frame.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _ev_frame[mid] < frame:
			lo = mid + 1
		else:
			hi = mid
	return lo


func _build() -> void:
	var data := song.data
	_step_frames = song.get_step_seconds() * mix_rate
	_instruments = data.get("instruments", [])
	for ch_data in data.get("channels", []):
		var ch := _Channel.new()
		ch.instrument = int(ch_data.get("instrument", 0))
		ch.volume = float(ch_data.get("volume", 1.0))
		var pan := clampf(float(ch_data.get("pan", 0.0)), -1.0, 1.0)
		ch.pan_l = cos((pan + 1.0) * PI / 4.0) * sqrt(2.0)
		ch.pan_r = sin((pan + 1.0) * PI / 4.0) * sqrt(2.0)
		var poly := clampi(int(ch_data.get("polyphony", 1)), 1, MAX_POLYPHONY)
		for i in poly:
			ch.voices.append(ChipVoice.new(float(mix_rate)))
		_channels.append(ch)

	var timing: Dictionary = data.get("timing", {})
	var spb := song.get_steps_per_beat()
	var swing := clampf(float(timing.get("swing", 0.0)), 0.0, 1.0)
	var swing_frames := swing * _step_frames * 0.667
	var half_beat := spb / 2

	var rows: Array = []
	var section_start := 0
	for section_index in data.get("order", []):
		var section: Dictionary = data["sections"][int(section_index)]
		_section_steps[section_start] = str(section.get("name", ""))
		var patterns: Array = section.get("patterns", [])
		for ch_index in mini(patterns.size(), _channels.size()):
			var pattern_index := int(patterns[ch_index])
			if pattern_index < 0:
				continue
			for note in data["patterns"][pattern_index].get("notes", []):
				var step := section_start + int(note[0])
				var frame := step * _step_frames
				if half_beat > 0 and spb % 2 == 0 and step % spb == half_beat:
					frame += swing_frames
				rows.append([int(frame), ch_index, note, section_start])
		section_start += int(section.get("length", 0))
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])

	var count := rows.size()
	_ev_frame.resize(count)
	_ev_channel.resize(count)
	_ev_pitch.resize(count)
	_ev_gate.resize(count)
	_ev_velocity.resize(count)
	_ev_instrument.resize(count)
	_ev_arp.resize(count)
	for i in count:
		var row: Array = rows[i]
		var note: Array = row[2]
		_ev_frame[i] = row[0]
		_ev_channel[i] = row[1]
		_ev_pitch[i] = float(note[2])
		_ev_gate[i] = int(float(note[1]) * _step_frames)
		_ev_velocity[i] = float(note[3]) / 127.0 if note.size() > 3 else 1.0
		_ev_instrument[i] = int(note[4]) if note.size() > 4 else -1
		var arp := PackedFloat32Array()
		if note.size() > 5 and note[5] is Array:
			for value in note[5]:
				arp.append(float(value))
		_ev_arp[i] = arp

	_length_frames = int(section_start * _step_frames)
	_loop_start_frame = int(song.get_loop_start_step() * _step_frames)
	_loop_end_frame = int(song.get_loop_end_step() * _step_frames)
	if _loop_end_frame <= _loop_start_frame:
		_loop_start_frame = 0
		_loop_end_frame = _length_frames
	looping = bool(timing.get("loop", true))
	for cue in data.get("cues", []):
		var cue_step := int(cue.get("step", 0))
		if not _cue_steps.has(cue_step):
			_cue_steps[cue_step] = []
		_cue_steps[cue_step].append(str(cue.get("name", "")))

	var fx: Dictionary = data.get("effects", {})
	_echo_level = clampf(float(fx.get("echo", 0.0)), 0.0, 1.0)
	_echo_feedback = clampf(float(fx.get("echo_feedback", 0.35)), 0.0, 0.85)
	var echo_beats := float(fx.get("echo_beats", 0.75))
	var echo_frames := maxi(64, int(echo_beats * spb * _step_frames))
	_echo_l.resize(echo_frames)
	_echo_r.resize(echo_frames)
	_echo_l.fill(0.0)
	_echo_r.fill(0.0)


class _Channel:
	extends RefCounted

	var voices: Array[ChipVoice] = []
	var instrument := 0
	var volume := 1.0
	var pan_l := 1.0
	var pan_r := 1.0
	var gain := 1.0
	var target_gain := 1.0
	var gain_step := 0.0
	var muted := false
