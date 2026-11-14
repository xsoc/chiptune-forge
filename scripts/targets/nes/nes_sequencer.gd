class_name NesSequencer
extends ChipSongSequencer
## Plays a [NesSong] the way a NES would: [NesPlayer] runs FamiStudio's
## engine logic once per video frame and [NesApu] turns its register writes
## into sound.
##
## It stands in for a [ChipSongSequencer], so [ChipMusicPlayer] and the
## exporters can use it unchanged. Channel numbers in its API (mutes, fades,
## meters) are the original song's, which is what the Layers screen uses;
## each one follows the NES channel playing that part at the time.

var nes: NesSong
## The emulated chip and the driver playing it ([NesApu] and [NesPlayer]
## here; subclasses swap in other hardware through [method _make_chip]).
var apu
var driver

var _frame_samples := 735.0
var _until_frame := 0.0
var _song_row := 0
var _mono := PackedFloat32Array()
var _gain := PackedFloat32Array()
var _target := PackedFloat32Array()
var _step := PackedFloat32Array()
var _off := PackedByteArray()


func _init(nes_song: NesSong, rate := 44100, source_channels := 7) -> void:
	nes = nes_song
	super(nes_song.source, rate)
	_make_chip(rate)
	_frame_samples = rate / nes.frame_hz
	_gain.resize(source_channels)
	_gain.fill(1.0)
	_target.resize(source_channels)
	_target.fill(1.0)
	_step.resize(source_channels)
	_off.resize(source_channels)
	# The arranged song's tempo is the groove's average, so a step lasts
	# exactly as long as an average row.
	_step_frames = _frame_samples * nes.frames_per_row()
	_loop_start_frame = int(nes.frames_before(nes.loop_start_row) * _frame_samples)
	_loop_end_frame = int(nes.frames_before(nes.row_count) * _frame_samples)
	_length_frames = _loop_end_frame
	if not nes.looping:
		_loop_start_frame = 0
	looping = nes.looping


func _make_chip(rate: int) -> void:
	apu = NesApu.new(float(rate))
	driver = NesPlayer.new(nes, apu)


## Brings the chip's output up to the level of the other targets.
func _output_gain() -> float:
	return 3.2


func get_channel_count() -> int:
	return _gain.size()


func get_channel_level(channel: int) -> float:
	var nes_channel := _nes_channel_of(channel)
	if nes_channel < 0:
		return 0.0
	return driver.get_channel_volume(nes_channel) / 15.0 * _gain[channel]


func set_channel_gain(channel: int, gain: float, fade_frames := 0) -> void:
	if channel < 0 or channel >= _gain.size():
		return
	_target[channel] = gain
	if fade_frames <= 0:
		_gain[channel] = gain
		_step[channel] = 0.0
	else:
		_step[channel] = absf(gain - _gain[channel]) / float(fade_frames)


func set_channel_muted(channel: int, muted: bool) -> void:
	if channel >= 0 and channel < _off.size():
		_off[channel] = 1 if muted else 0


func seek_step(step: float, kill := true) -> void:
	var row := clampi(int(step), 0, maxi(nes.row_count - 1, 0))
	if kill or row != driver.row:
		driver.start(row)
	_until_frame = 0.0
	_song_row = row
	position = int(nes.frames_before(row) * _frame_samples)
	_last_step = row - 1
	finished = false


func render(count: int) -> PackedVector2Array:
	events.clear()
	if _mono.size() != count:
		_mono.resize(count)
	_update_gains(count)
	var done := 0
	while done < count:
		if _until_frame <= 0.0:
			_driver_frame()
			_until_frame += _frame_samples
		var n := mini(count - done, maxi(int(ceilf(_until_frame)), 1))
		apu.render(_mono, done, n)
		_until_frame -= n
		done += n
		if not finished:
			position += n
	var out := PackedVector2Array()
	out.resize(count)
	var gain := master_gain * _output_gain()
	for i in count:
		var s := _soft_clip(_mono[i] * gain)
		out[i] = Vector2(s, s)
	return out


func _driver_frame() -> void:
	if finished:
		return
	if driver.frame == 0:
		var row: int = driver.row
		if driver.finished or (not looping and row < _song_row):
			finished = true
			events.append([EventType.FINISHED, 0])
			apu.reset()
			return
		if row < _song_row:
			events.append([EventType.LOOPED, 0])
			_last_step = row - 1
		position = int(nes.frames_before(row) * _frame_samples)
		_song_row = row
		_step_events(row)
		_apply_channel_gains()
	driver.tick()


func _step_events(row: int) -> void:
	var spb := song.get_steps_per_beat()
	var bar_steps := spb * song.get_beats_per_bar()
	for s in range(maxi(_last_step + 1, row), row + 1):
		if s % spb == 0:
			events.append([EventType.BEAT, s / spb])
		if s % bar_steps == 0:
			events.append([EventType.BAR, s / bar_steps])
		if _section_steps.has(s):
			events.append([EventType.SECTION, _section_steps[s]])
		for cue_name in _cue_steps.get(s, []):
			events.append([EventType.CUE, cue_name])
	_last_step = row


func _update_gains(count: int) -> void:
	var changed := false
	for c in _gain.size():
		if _gain[c] != _target[c]:
			_gain[c] = move_toward(_gain[c], _target[c], _step[c] * count) if _step[c] > 0.0 else _target[c]
			changed = true
	if changed:
		_apply_channel_gains()


## Each NES channel takes the gain of the part it is playing now.
func _apply_channel_gains() -> void:
	for nes_channel in nes.notes.size():
		var sources: Array = nes.sources_at(_song_row, nes_channel)
		var gain := 1.0
		if not sources.is_empty():
			gain = 0.0
			for c in sources:
				var index := int(c)
				if index >= 0 and index < _gain.size() and _off[index] == 0:
					gain = maxf(gain, _gain[index])
		apu.channel_gain[nes_channel] = gain


func _nes_channel_of(channel: int) -> int:
	for nes_channel in nes.notes.size():
		if nes.sources_at(_song_row, nes_channel).has(channel):
			return nes_channel
	return -1
