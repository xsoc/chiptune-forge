class_name NesPlayer
extends RefCounted
## Plays a [NesSong] one video frame at a time, the way FamiStudio's sound
## engine does, writing the registers of a [NesApu].
##
## Covers the features the arranger uses: notes with durations, the volume
## column, per-note arpeggios, and the volume, arpeggio, pitch and duty
## envelopes (each restarts on a new note, loops at its loop point and
## otherwise holds its last value). The volume column and the volume
## envelope combine through FamiStudio's volume table, and the noise
## channel's pitch and mode work as in the engine.

var song: NesSong
## The sound chip the driver writes: a [NesApu] here, another chip in
## subclasses that play the same song data on other hardware.
var apu
## Current row and the frame within it.
var row := 0
var frame := 0
var finished := false

## Per channel, the row index each note starts on, and the note.
var _starts: Array = []
## Per channel: row -> true where a note ends without another starting.
var _stops: Array = []
var _ch: Array[_Channel] = []
## Channels in the song: four on the NES, more on other hardware.
var _count := 4


func _init(nes_song: NesSong, nes_apu: Variant) -> void:
	song = nes_song
	apu = nes_apu
	_count = song.notes.size()
	for c in _count:
		_ch.append(_Channel.new())
		_starts.append({})
		_stops.append({})
	_index_notes()
	start(0)


func _index_notes() -> void:
	for c in _count:
		var list: Array = song.notes[c]
		for k in list.size():
			var n: Dictionary = list[k]
			var start := int(n["row"])
			_starts[c][start] = n
			var next_start := int(list[k + 1]["row"]) if k + 1 < list.size() else song.row_count
			var end := mini(start + int(n["length"]), next_start)
			if end < next_start and end < song.row_count:
				_stops[c][end] = true


## Starts playback at [param from_row] with every channel silent.
func start(from_row := 0) -> void:
	_reset_chip()
	for ch in _ch:
		ch.clear()
	row = clampi(from_row, 0, maxi(song.row_count - 1, 0))
	frame = 0
	finished = song.row_count == 0
	# A note that started earlier and is still sounding plays on.
	for c in _count:
		var list: Array = song.notes[c]
		for k in list.size():
			var n: Dictionary = list[k]
			var s := int(n["row"])
			if s >= row:
				break
			var next_start := int(list[k + 1]["row"]) if k + 1 < list.size() else song.row_count
			if row < mini(s + int(n["length"]), next_start):
				_attack(c, n)
				# Skip its envelopes ahead to where they would be by now.
				var frames := song.frames_before(row) - song.frames_before(s)
				for f in mini(frames, 300):
					_ch[c].advance()


func _reset_chip() -> void:
	apu.reset()
	apu.write(NesApu.STATUS, 0x0F)
	# Sweep units off with the negate flag set, so they never mute low notes.
	apu.write(NesApu.PULSE1_SWEEP, 0x08)
	apu.write(NesApu.PULSE2_SWEEP, 0x08)


## Runs one frame of the engine: reads the row on its first frame, then
## updates every channel's envelopes and registers.
func tick() -> void:
	if finished:
		return
	if frame == 0:
		for c in _count:
			if _starts[c].has(row):
				_attack(c, _starts[c][row])
			elif _stops[c].has(row):
				_ch[c].note = 0
	for c in _count:
		_output(c)
		_ch[c].advance()
	frame += 1
	if frame >= song.frames_in_row(row):
		frame = 0
		row += 1
		if row >= song.row_count:
			if song.looping:
				row = song.loop_start_row
			else:
				finished = true
				for c in _count:
					_ch[c].note = 0
					_output(c)


func _attack(channel: int, n: Dictionary) -> void:
	var ch := _ch[channel]
	ch.note = int(n["note"])
	ch.instrument = song.instruments[int(n["instrument"])] if int(n["instrument"]) < song.instruments.size() else {}
	ch.volume = int(n.get("volume", 15))
	var arp := int(n.get("arp", -1))
	ch.arp = song.arpeggios[arp] if arp >= 0 and arp < song.arpeggios.size() else {}
	ch.restart()


func _output(channel: int) -> void:
	var ch := _ch[channel]
	var env_volume := ch.value("volume", 15)
	var volume := NesSong.mix_volume(ch.volume, env_volume) if ch.note > 0 else 0
	var offset := ch.arp_value()
	var duty := ch.value("duty", 0) & 3
	match channel:
		NesSong.PULSE1, NesSong.PULSE2:
			var base := channel * 4
			apu.write(0x4000 + base, (duty << 6) | 0x30 | volume)
			if ch.note > 0:
				var note := clampi(ch.note + offset, NesSong.FIRST_NOTE, NesSong.LAST_NOTE)
				var period := clampi(NesSong.note_period(note) + ch.value("pitch", 0), 0, 0x7FF)
				apu.write(0x4002 + base, period & 0xFF)
				# The engine only rewrites the high byte when it changes, so the
				# duty cycle does not restart (and click) on every frame.
				var hi := period >> 8
				if hi != ch.last_hi:
					apu.write(0x4003 + base, hi)
					ch.last_hi = hi
		NesSong.TRIANGLE:
			if ch.note > 0 and volume > 0:
				var note := clampi(ch.note + offset, NesSong.FIRST_NOTE, NesSong.LAST_NOTE)
				var period := clampi(NesSong.note_period(note) + ch.value("pitch", 0), 0, 0x7FF)
				apu.write(NesApu.TRI_LINEAR, 0x81)
				apu.write(NesApu.TRI_LO, period & 0xFF)
				apu.write(NesApu.TRI_HI, period >> 8)
			else:
				apu.write(NesApu.TRI_LINEAR, 0x80)
		NesSong.NOISE:
			apu.write(NesApu.NOISE_VOL, 0x30 | volume)
			if ch.note > 0:
				var index := ((ch.note + offset) & 0x0F) ^ 0x0F
				apu.write(NesApu.NOISE_LO, ((duty & 1) << 7) | index)


## Current volume of a channel (0 to 15) as the engine sets it, for meters.
func get_channel_volume(channel: int) -> int:
	var ch := _ch[channel]
	if ch.note <= 0:
		return 0
	return NesSong.mix_volume(ch.volume, ch.value("volume", 15))


## The row and frame a song row starts at. Exists for symmetry with the Game
## Boy driver; rows map one to one.
func find_position(song_row: int) -> int:
	return clampi(song_row, 0, maxi(song.row_count - 1, 0))


class _Channel:
	extends RefCounted

	var note := 0
	var volume := 15
	var instrument: Dictionary = {}
	var arp: Dictionary = {}
	var last_hi := -1
	# Envelope positions, by envelope name.
	var pos := {"volume": 0, "arp": 0, "pitch": 0, "duty": 0}
	var arp_pos := 0

	func clear() -> void:
		note = 0
		volume = 15
		instrument = {}
		arp = {}
		last_hi = -1
		restart()

	func restart() -> void:
		for key in pos:
			pos[key] = 0
		arp_pos = 0

	func value(env: String, default: int) -> int:
		var values: Array = instrument.get(env, [])
		if values.is_empty():
			return default
		return int(values[mini(int(pos[env]), values.size() - 1)])

	## The arpeggio offset: the note's arpeggio if it has one, else the
	## instrument's arpeggio envelope.
	func arp_value() -> int:
		if not arp.is_empty():
			var values: Array = arp["values"]
			return int(values[mini(arp_pos, values.size() - 1)]) if not values.is_empty() else 0
		return value("arp", 0)

	func advance() -> void:
		for key in pos:
			var values: Array = instrument.get(key, [])
			if values.is_empty():
				continue
			pos[key] = _next(int(pos[key]), values.size(), int(instrument.get(key + "_loop", -1)))
		if not arp.is_empty():
			arp_pos = _next(arp_pos, (arp["values"] as Array).size(), int(arp.get("loop", -1)))

	static func _next(at: int, length: int, loop: int) -> int:
		at += 1
		if at >= length:
			return loop if loop >= 0 and loop < length else length - 1
		return at
