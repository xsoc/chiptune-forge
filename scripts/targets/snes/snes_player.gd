class_name SnesPlayer
extends RefCounted
## Plays a [SnesSong]'s tracker rows one tick at a time the way SNESMod
## (PVSnesLib's sound driver, sm_spc.asm) does, writing the registers of a
## [SnesDsp].
##
## Follows the driver's logic for what our modules use: notes, note-offs,
## instruments, the volume column, the A, B, H (vibrato) and J (arpeggio)
## commands, volume envelopes with a sustain node, fadeout, and the echo
## setup from the song message. Each tick it works out every channel's
## volume (written as a direct GAIN), panning and pitch (through SNESMod's
## frequency table) exactly as the driver does, so previews match what the
## console plays.

var song: SnesSong
var apu: SnesDsp
var row := 0
## The tick within the row (named for [NesSequencer], which counts frames).
var frame := 0
var finished := false

var _rows: Array = []
var _ch: Array[_Channel] = []
var _speed := 6
## Per instrument: envelope nodes as SNESMod stores them, [y, duration,
## delta (8.8 fixed point)], or empty.
var _env: Array = []
var _sustain := PackedInt32Array()
var _fadeout := PackedInt32Array()
var _pitch_base := PackedInt32Array()
var _sine := PackedInt32Array()


func _init(snes_song: SnesSong, dsp: SnesDsp) -> void:
	song = snes_song
	apu = dsp
	_rows = song.rows()
	for c in SnesSong.CHANNEL_COUNT:
		_ch.append(_Channel.new())
	for i in 256:
		_sine.append(int(floor(64.0 * sin(TAU * i / 256.0) + 0.5)))
	for inst in song.instruments:
		_env.append(envelope_nodes(inst))
		var env: Dictionary = inst.get("env", {})
		_sustain.append(int(env.get("sustain", -1)) if not env.is_empty() else -1)
		_fadeout.append(clampi(int(inst.get("fadeout", 0)), 0, 255))
	for name in song.samples:
		_pitch_base.append(SnesSamples.pitch_base(name))
	start(0)


## An instrument's envelope as smconv converts it: for each node its level,
## the ticks to the next node, and the step per tick in 1/256ths.
static func envelope_nodes(inst: Dictionary) -> Array:
	var env: Dictionary = inst.get("env", {})
	var nodes: Array = env.get("nodes", [])
	var out: Array = []
	for i in nodes.size():
		var y := int(nodes[i][1])
		if i == nodes.size() - 1:
			out.append([y, 0, 0])
			continue
		var duration := int(nodes[i + 1][0]) - int(nodes[i][0])
		var delta := 64
		if duration > 0:
			delta = ((int(nodes[i + 1][1]) - y) * 256 + duration / 2) / duration
		else:
			duration = 255
		out.append([y, duration, delta])
	return out


## Starts playback at [param from_row]. A note that started earlier and is
## still playing starts again there.
func start(from_row := 0) -> void:
	_speed = song.speed()
	_reset_chip()
	for ch in _ch:
		ch.clear()
	row = clampi(from_row, 0, maxi(song.row_count - 1, 0))
	frame = 0
	finished = song.row_count == 0
	if row > 0:
		for c in SnesSong.CHANNEL_COUNT:
			var list: Array = song.notes[c]
			for k in list.size():
				var n: Dictionary = list[k]
				var s := int(n["row"])
				if s >= row:
					break
				var next_start := int(list[k + 1]["row"]) if k + 1 < list.size() else song.row_count
				if row < mini(s + int(n["length"]), next_start):
					_ch[c].pending = {"note": int(n["note"]), "instrument": int(n["instrument"]) + 1, "volume": int(n["volume"]), "command": 0, "param": 0}


## What SNESMod's boot and Module_Start set up: main volume, the samples,
## and the echo unit from the song message.
func _reset_chip() -> void:
	apu.reset()
	apu.write(SnesDsp.MVOLL, 80)
	apu.write(SnesDsp.MVOLR, 80)
	for i in song.samples.size():
		apu.set_source(i, SnesSamples.decoded(song.samples[i]))
	var echo: Dictionary = song.echo
	apu.write(SnesDsp.FLG, SnesDsp.FLG_ECEN)
	apu.write(SnesDsp.EVOLL, 0)
	apu.write(SnesDsp.EVOLR, 0)
	var fir: Array = echo.get("fir", [127, 0, 0, 0, 0, 0, 0, 0])
	for k in 8:
		apu.write(SnesDsp.FIR + k * 0x10, int(fir[k]) & 0xFF)
	apu.write(SnesDsp.EFB, int(echo.get("efb", 0)) & 0xFF)
	apu.write(SnesDsp.EON, int(echo.get("eon", 0)))
	apu.write(SnesDsp.EDL, int(echo.get("edl", 0)))
	if int(echo.get("edl", 0)) > 0:
		apu.write(SnesDsp.EVOLL, _echo_volume(int(echo.get("evol", 0))))
		apu.write(SnesDsp.EVOLR, _echo_volume(int(echo.get("evol", 0))))
		apu.write(SnesDsp.FLG, 0)


## SNESMod's UpdateEchoVolume: the echo volume scaled by the main volume.
static func _echo_volume(evol: int) -> int:
	var scale := 80 * 2
	var unsigned := evol & 0xFF
	var a := (scale * unsigned) >> 8
	if evol < 0:
		a -= scale
	return a & 0xFF


## Runs one tick of the driver: on the row's first tick reads it, then
## updates every channel.
func tick() -> void:
	if finished:
		return
	if frame == 0:
		var cells: Array = _rows[row]
		for c in SnesSong.CHANNEL_COUNT:
			var ch := _ch[c]
			var cell = cells[c]
			if not ch.pending.is_empty():
				cell = ch.pending
				ch.pending = {}
			ch.has_data = cell != null
			if cell != null:
				ch.cell = cell
	for c in SnesSong.CHANNEL_COUNT:
		_update_channel(c)
	frame += 1
	if frame >= _speed:
		frame = 0
		row += 1
		if row >= song.row_count:
			if song.looping:
				row = song.loop_start_row
			else:
				finished = true
				for c in SnesSong.CHANNEL_COUNT:
					_ch[c].volume = 0
					_update_channel(c)


func _update_channel(c: int) -> void:
	var ch := _ch[c]
	ch.start = false
	if ch.has_data:
		_process_data(c)
	ch.t_pitch = ch.pitch
	ch.t_volume = ch.volume
	if ch.has_data:
		_process_command(c)
	_process_audio(c)


## Channel_ProcessData's first-tick work: the note, instrument and volume.
func _process_data(c: int) -> void:
	if frame != 0:
		return
	var ch := _ch[c]
	var cell: Dictionary = ch.cell
	var note := int(cell["note"])
	var inst := int(cell["instrument"])
	if inst > 0:
		ch.instrument = inst
	if note >= 0:
		if note == SnesSong.NOTE_CUT:
			ch.volume = 0
		elif note == SnesSong.NOTE_OFF:
			ch.keyon = false
		else:
			ch.pitch = note * 64
			if ch.instrument > 0:
				ch.sample = int(song.instruments[ch.instrument - 1]["sample"])
			ch.start = true
	if inst > 0:
		# The sample's default volume, then the envelope starts over.
		ch.volume = 64
		ch.fadeout = 255
		ch.env_node = 0
		ch.env_tick = 0
		ch.cmem = 0
		ch.keyon = true
		ch.fade = false
	var vol := int(cell["volume"])
	if vol >= 0 and vol <= 64:
		ch.volume = vol


func _process_command(c: int) -> void:
	var ch := _ch[c]
	var command := int(ch.cell["command"])
	var param := int(ch.cell["param"])
	match command:
		SnesSong.CMD_SPEED:
			if frame == 0 and param > 0:
				_speed = param
		SnesSong.CMD_VIBRATO:
			ch.cmem = (ch.cmem + ((param >> 2) & 0x3C)) & 0xFF
			var s := _sine[ch.cmem]
			var depth := param & 15
			if s >= 0:
				ch.t_pitch += (s * depth) >> 4
			else:
				ch.t_pitch = maxi(ch.t_pitch - ((-s * depth) >> 4), 0)
		SnesSong.CMD_ARPEGGIO:
			if frame == 0:
				ch.cmem = 0
			else:
				ch.cmem = (ch.cmem + 1) % 3
				if ch.cmem == 1:
					ch.t_pitch += (param >> 4) * 64
				elif ch.cmem == 2:
					ch.t_pitch += (param & 15) * 64


func _process_audio(c: int) -> void:
	var ch := _ch[c]
	if ch.instrument <= 0:
		# Nothing has played here: SNESMod keeps the voice silent.
		apu.write(c * 0x10 + SnesDsp.V_GAIN, 0x9C)
		return
	var index := ch.instrument - 1
	var t_env := _envelope(ch, index)
	if ch.fade:
		ch.fadeout = maxi(ch.fadeout - _fadeout[index], 0)
	# Volume: V * envelope * fadeout * module volume, as a 7-bit GAIN.
	var y := mini(ch.t_volume * 4, 255)
	y = (y * t_env) >> 8
	y = (y * ch.fadeout) >> 8
	y = (y * 255) >> 8
	var gain := y >> 1
	if not ch.start:
		if gain == 0:
			gain = 0x9C
		elif gain == 127:
			gain = 0xDC
	var pan := song.pans[c] * 2
	if pan >= 128:
		pan = 127
	var base := c * 0x10
	if ch.start:
		apu.write(base + SnesDsp.V_SRCN, ch.sample)
		apu.write(SnesDsp.KON, 1 << c)
	apu.write(base + SnesDsp.V_VOLL, pan ^ 127)
	apu.write(base + SnesDsp.V_VOLR, pan)
	var pitch := SnesSong.dsp_pitch(ch.t_pitch + _pitch_base[ch.sample])
	apu.write(base + SnesDsp.V_PITCHL, pitch & 0xFF)
	apu.write(base + SnesDsp.V_PITCHH, (pitch >> 8) & 0x3F)
	apu.write(base + SnesDsp.V_ADSR1, 0)
	apu.write(base + SnesDsp.V_GAIN, gain)
	ch.gain = gain if gain < 0x80 else 0


## Channel_ProcessEnvelope. Returns the envelope level, 0 to 255.
func _envelope(ch: _Channel, index: int) -> int:
	var nodes: Array = _env[index]
	if nodes.is_empty():
		if not ch.keyon:
			ch.fade = true
		return 255
	var node: Array = nodes[ch.env_node]
	if ch.env_tick == 0:
		ch.env_y = int(node[0]) << 8
	else:
		var v := (ch.env_y + int(node[2])) & 0xFFFF
		if v & 0x8000:
			ch.env_y = 0
		elif (v >> 8) >= 64:
			ch.env_y = 64 << 8
		else:
			ch.env_y = v
	var t_env := mini(ch.env_y >> 6, 255)
	if ch.keyon and ch.env_node == _sustain[index]:
		return t_env
	ch.env_tick += 1
	if ch.env_tick < int(node[1]):
		return t_env
	ch.env_tick = 0
	if ch.env_node == nodes.size() - 1:
		ch.fade = true
	else:
		ch.env_node += 1
	return t_env


## Current volume of a channel, 0 to 15, for meters.
func get_channel_volume(channel: int) -> int:
	return roundi(_ch[channel].gain / 126.0 * 15.0)


func find_position(song_row: int) -> int:
	return clampi(song_row, 0, maxi(song.row_count - 1, 0))


class _Channel:
	extends RefCounted

	var cell: Dictionary = {}
	var pending: Dictionary = {}
	var has_data := false
	var instrument := 0
	var sample := 0
	var pitch := 0
	var volume := 0
	var t_pitch := 0
	var t_volume := 0
	var keyon := false
	var fade := false
	var fadeout := 255
	var env_node := 0
	var env_tick := 0
	var env_y := 0
	var cmem := 0
	var start := false
	var gain := 0

	func clear() -> void:
		cell = {}
		pending = {}
		has_data = false
		instrument = 0
		sample = 0
		pitch = 0
		volume = 0
		keyon = false
		fade = false
		fadeout = 255
		env_node = 0
		env_tick = 0
		env_y = 0
		cmem = 0
		gain = 0
