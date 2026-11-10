class_name GbSequencer
extends ChipSongSequencer
## Plays a [GbSong] the way a Game Boy would: [HugePlayer] runs the driver at
## the song's tick rate and [GbApu] turns its register writes into sound.
##
## It stands in for a [ChipSongSequencer], so [ChipMusicPlayer] and the
## exporters can use it unchanged. Channel numbers in its API (mutes, fades,
## meters) are the original song's, which is what the Layers screen uses;
## each one follows the Game Boy channel playing that part at the time.

var gb: GbSong
var apu: GbApu
var driver: HugePlayer

var _tick_frames := 735.0
var _until_tick := 0.0
var _song_row := 0
var _gain := PackedFloat32Array()
var _target := PackedFloat32Array()
var _step := PackedFloat32Array()
var _off := PackedByteArray()


func _init(gb_song: GbSong, rate := 44100, source_channels := 7) -> void:
	gb = gb_song
	super(gb_song.source, rate)
	apu = GbApu.new(float(rate))
	driver = HugePlayer.new(gb, apu)
	_tick_frames = rate / gb.tick_hz
	_gain.resize(source_channels)
	_gain.fill(1.0)
	_target.resize(source_channels)
	_target.fill(1.0)
	_step.resize(source_channels)
	_off.resize(source_channels)
	# The arranged song's timing is the driver's, so a step lasts exactly as
	# many frames as a row of ticks.
	_step_frames = _tick_frames * gb.ticks_per_row
	_loop_start_frame = int(gb.loop_start_row * _step_frames)
	_loop_end_frame = int(gb.row_count * _step_frames)
	if not gb.looping:
		_loop_start_frame = 0
		_loop_end_frame = _length_frames
	looping = gb.looping


func get_channel_count() -> int:
	return _gain.size()


func get_channel_level(channel: int) -> float:
	var gb_channel := _gb_channel_of(channel)
	if gb_channel < 0:
		return 0.0
	return apu.get_channel_volume(gb_channel) / 15.0 * _gain[channel]


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
	var row := clampi(int(step), 0, maxi(gb.row_count - 1, 0))
	var at := driver.find_position(row)
	if kill:
		driver.start(at.x, at.y)
	else:
		driver.jump(at.x, at.y)
	_until_tick = 0.0
	_song_row = row
	position = int(row * _step_frames)
	_last_step = row - 1
	finished = false


func render(count: int) -> PackedVector2Array:
	events.clear()
	if _left.size() != count:
		_left.resize(count)
		_right.resize(count)
	_left.fill(0.0)
	_right.fill(0.0)
	_update_gains(count)
	var done := 0
	while done < count:
		if _until_tick <= 0.0:
			_driver_tick()
			_until_tick += _tick_frames
		var n := mini(count - done, maxi(int(ceilf(_until_tick)), 1))
		apu.render(_left, _right, done, n)
		_until_tick -= n
		done += n
		if not finished:
			position += n
	var out := PackedVector2Array()
	out.resize(count)
	var gain := master_gain * 1.6
	for i in count:
		out[i] = Vector2(_soft_clip(_left[i] * gain), _soft_clip(_right[i] * gain))
	return out


func _driver_tick() -> void:
	if finished:
		return
	if driver.tick == 0:
		var row := driver.get_song_row()
		if row < 0 or (not looping and row < _song_row):
			finished = true
			events.append([EventType.FINISHED, 0])
			apu.reset()
			return
		if row < _song_row:
			events.append([EventType.LOOPED, 0])
			_last_step = row - 1
		position = int(row * _step_frames)
		_song_row = row
		_step_events(row)
		_apply_channel_gains()
	driver.dosound()


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


## Each Game Boy channel takes the gain of the part it is playing now.
func _apply_channel_gains() -> void:
	for gb_channel in 4:
		var sources: Array = gb.sources_at(_song_row, gb_channel)
		var gain := 1.0
		if not sources.is_empty():
			gain = 0.0
			for c in sources:
				var index := int(c)
				if index >= 0 and index < _gain.size() and _off[index] == 0:
					gain = maxf(gain, _gain[index])
		apu.channel_gain[gb_channel] = gain


func _gb_channel_of(channel: int) -> int:
	for gb_channel in 4:
		if gb.sources_at(_song_row, gb_channel).has(channel):
			return gb_channel
	return -1
