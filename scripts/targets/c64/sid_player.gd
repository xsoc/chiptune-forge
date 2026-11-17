class_name SidPlayer
extends NesPlayer
## Plays a [SidSong] one frame at a time, setting the SID's registers.
##
## Notes, durations, arpeggios and pitch and duty envelopes work as in
## [NesPlayer]; loudness comes from each instrument's hardware ADSR. Each
## frame it works out all 25 registers and writes them, which is what our
## 6502 player does with the exported data: [SidWriter] records these
## register values frame by frame.
##
## Voice 1 plays the lead and voice 3 the bass. Voice 2 plays the drums
## while a drum sounds, and the accompaniment the rest of the time. The
## accompaniment takes voice 2 back in the middle of a note only when it
## has time to sound, so it never turns into a stutter of short blips
## between drum hits.
##
## Every new note starts with a "hard restart", as C64 music drivers do:
## for [constant HARD_RESTART] frames before it, its voice's gate goes off
## with the fastest release (attack, decay, sustain and release all 0), and
## on the note's own frame the gate goes on. The SID's envelope generator
## has a well-known flaw (the "ADSR bug"): when its rate gets faster while
## the rate counter is already past the new period, the counter has to wrap
## all the way round its 15 bits first, freezing the envelope for up to
## 33 ms. Two frames of the fastest rate before every gate-on use that
## time up, so each note starts on time. To know a note is coming, the
## player works [constant HARD_RESTART] frames ahead of what it outputs.
##
## Low noise on the drums (a kick's falling noise) sounds like a gurgle on
## the SID, whose noise is sampled and held. After a hit's first frame,
## noise below [constant THUMP_BELOW] plays as a pulse instead, the usual
## C64 kick: a click of noise, then a falling thump.

## Frames of hard restart before each new note.
const HARD_RESTART := 2
## The accompaniment takes voice 2 back from a drum in the middle of a note
## only if it then keeps the voice for at least this many frames.
const RECLAIM_FRAMES := 6
## Drum noise below this frequency register value plays as a pulse after
## the hit's first frame.
const THUMP_BELOW := 0x0800
const THUMP_WIDTH := 0x0800

## Parts this player may play, as a bit mask over the song's four channels.
## A sound effect plays only its own.
var channel_mask := 0x0F
## Hard restarts before notes. Sound effects play without (our 6502 player
## starts them over the music, so their first frame keeps the gate off to
## restart the envelope instead).
var hard_restart := true
## Low drum noise turns into a pulse thump (songs only).
var pitched_drums := true
## The register values output on the last frame.
var regs := PackedInt32Array()

## The registers as worked out for the frame [constant HARD_RESTART] ahead.
var _raw := PackedInt32Array()
var _retrigger := PackedInt32Array([0, 0, 0, 0])
var _owner := -1
## Frames since each part's note started.
var _age := PackedInt32Array([0, 0, 0, 0])
## The row each part's current note ends on.
var _end_row := PackedInt32Array([0, 0, 0, 0])
## Frames worked out ahead of the output: {"regs", "start" (per voice)}.
var _ahead: Array[Dictionary] = []


## Starts playback at [param from_row], working out the first frames ahead.
func start(from_row := 0) -> void:
	super(from_row)
	if hard_restart:
		for k in HARD_RESTART:
			super.tick()


func tick() -> void:
	super()
	if not hard_restart or _ahead.is_empty():
		return
	var cur: Dictionary = _ahead.pop_front()
	var out: PackedInt32Array = (cur["regs"] as PackedInt32Array).duplicate()
	for v in 3:
		if cur["start"][v]:
			continue
		var soon := false
		for k in mini(HARD_RESTART, _ahead.size()):
			if _ahead[k]["start"][v]:
				soon = true
		if soon:
			out[v * 7 + 4] &= 0xFE
			out[v * 7 + 5] = 0
			out[v * 7 + 6] = 0
	_write(out)


func _reset_chip() -> void:
	apu.reset()
	_raw = PackedInt32Array()
	_raw.resize(SidChip.REGISTER_COUNT)
	_raw[24] = 0x0F
	regs = _raw.duplicate()
	_retrigger = PackedInt32Array([0, 0, 0, 0])
	_age = PackedInt32Array([0, 0, 0, 0])
	_owner = -1
	_ahead.clear()


func _attack(channel: int, n: Dictionary) -> void:
	super(channel, n)
	_retrigger[channel] = 1
	_age[channel] = 0
	var first := int(n["row"])
	var end := mini(first + int(n["length"]), song.row_count)
	for r in range(first + 1, end):
		if _starts[channel].has(r):
			end = r
			break
	_end_row[channel] = end


func _output(channel: int) -> void:
	if channel == _count - 1:
		_update()


func _update() -> void:
	var start := [false, false, false]
	if channel_mask & (1 << SidSong.LEAD):
		start[0] = _voice(SidSong.LEAD, 0, _retrigger[SidSong.LEAD] != 0)
	if channel_mask & (1 << SidSong.BASS):
		start[2] = _voice(SidSong.BASS, 2, _retrigger[SidSong.BASS] != 0)
	if channel_mask & ((1 << SidSong.ACCOMP) | (1 << SidSong.DRUMS)):
		var drums := _ch[SidSong.DRUMS]
		var owner := -1
		if (channel_mask & (1 << SidSong.DRUMS)) and drums.note > 0 and drums.value("volume", 15) > 0:
			owner = SidSong.DRUMS
		elif channel_mask & (1 << SidSong.ACCOMP):
			owner = SidSong.ACCOMP
			# Mid-note, the accompaniment takes the voice back only if it
			# has time to sound before its note ends or the next drum.
			if _owner == SidSong.DRUMS and _retrigger[SidSong.ACCOMP] == 0 and _accomp_room() < RECLAIM_FRAMES:
				owner = SidSong.DRUMS
		if owner >= 0:
			# A part taking voice 2 over starts its note afresh.
			start[1] = _voice(owner, 1, _retrigger[owner] != 0 or owner != _owner)
		else:
			_raw[11] &= 0xFE
		_owner = owner
	_retrigger = PackedInt32Array([0, 0, 0, 0])
	for c in 4:
		_age[c] += 1
	if hard_restart:
		_ahead.append({"regs": _raw.duplicate(), "start": start})
	else:
		_write(_raw)


func _write(values: PackedInt32Array) -> void:
	regs = values.duplicate()
	for r in SidChip.REGISTER_COUNT:
		apu.write(r, regs[r])


## Frames the accompaniment could play on voice 2 from now: until its note
## ends or the next drum hit, whichever comes first.
func _accomp_room() -> int:
	var now := song.frames_before(row) + frame
	var until := song.frames_before(_end_row[SidSong.ACCOMP]) - now
	for r in range(row + 1, _end_row[SidSong.ACCOMP]):
		if _starts[SidSong.DRUMS].has(r):
			until = mini(until, song.frames_before(r) - now)
			break
	return until


## Sets voice [param voice] for the part on [param channel]. With
## [param restart] the note starts afresh: the gate goes on now after a
## hard restart, or (without hard restarts) stays off this frame. Returns
## whether a note starts on this frame.
func _voice(channel: int, voice: int, restart: bool) -> bool:
	var ch := _ch[channel]
	var base := voice * 7
	if ch.note <= 0:
		_raw[base + 4] &= 0xFE
		return false
	var inst := ch.instrument
	var wave := str(inst.get("wave", "pulse"))
	var freq := 0
	var pw := int(inst.get("pw", -1))
	var bits := {"pulse": SidChip.PULSE, "saw": SidChip.SAW, "triangle": SidChip.TRIANGLE, "noise": SidChip.NOISE}.get(wave, SidChip.PULSE) as int
	if wave == "noise":
		var index := ((ch.note + ch.arp_value()) & 0x0F) ^ 0x0F
		freq = SidSong.noise_freq(index)
		if pitched_drums and _age[channel] > 0 and freq < THUMP_BELOW:
			bits = SidChip.PULSE
			pw = THUMP_WIDTH
	else:
		var midi := clampi(ch.note + ch.arp_value(), 0, 127)
		freq = SidSong.note_freq(midi)
		var bend := ch.value("pitch", 0)
		if bend != 0:
			# Pitch envelopes are in NES period steps: scale the frequency
			# as the NES period would move.
			var period := float(NesSong.note_period(clampi(midi - 23, NesSong.FIRST_NOTE, NesSong.LAST_NOTE)))
			freq = clampi(roundi(freq * (period + 1.0) / maxf(period + 1.0 + bend, 1.0)), 1, 65535)
	_raw[base] = freq & 0xFF
	_raw[base + 1] = freq >> 8
	if pw < 0:
		pw = SidSong.DUTY_WIDTHS[ch.value("duty", 2) & 3]
	_raw[base + 2] = pw & 0xFF
	_raw[base + 3] = pw >> 8
	_raw[base + 4] = bits | (0 if restart and not hard_restart else SidChip.GATE)
	_raw[base + 5] = int(inst.get("ad", 0))
	var sr := int(inst.get("sr", 0xF0))
	var sustain := roundi((sr >> 4) * clampi(ch.volume, 0, 15) / 15.0)
	_raw[base + 6] = (sustain << 4) | (sr & 0x0F)
	return restart


func get_channel_volume(channel: int) -> int:
	var voice: int = SidSong.VOICE_OF[channel]
	if channel == SidSong.ACCOMP and _owner == SidSong.DRUMS:
		return 0
	if channel == SidSong.DRUMS and _owner != SidSong.DRUMS:
		return 0
	return apu.get_channel_volume(voice) if apu.has_method("get_channel_volume") else 0
