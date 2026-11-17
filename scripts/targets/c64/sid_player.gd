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
## A new note first turns its voice's gate off for one frame, so the ADSR
## restarts, then on. Voice 1 plays the lead and voice 3 the bass. Voice 2
## plays the drums while a drum sounds, and the accompaniment the rest of
## the time.

## Parts this player may play, as a bit mask over the song's four channels.
## A sound effect plays only its own.
var channel_mask := 0x0F
## The register values set on the last frame.
var regs := PackedInt32Array()

var _retrigger := PackedInt32Array([0, 0, 0, 0])
var _owner := -1


func _reset_chip() -> void:
	apu.reset()
	regs = PackedInt32Array()
	regs.resize(SidChip.REGISTER_COUNT)
	regs[24] = 0x0F
	_retrigger = PackedInt32Array([0, 0, 0, 0])
	_owner = -1


func _attack(channel: int, n: Dictionary) -> void:
	super(channel, n)
	_retrigger[channel] = 1


func _output(channel: int) -> void:
	if channel == _count - 1:
		_update()


func _update() -> void:
	if channel_mask & (1 << SidSong.LEAD):
		_voice(SidSong.LEAD, 0, _retrigger[SidSong.LEAD] != 0)
	if channel_mask & (1 << SidSong.BASS):
		_voice(SidSong.BASS, 2, _retrigger[SidSong.BASS] != 0)
	if channel_mask & ((1 << SidSong.ACCOMP) | (1 << SidSong.DRUMS)):
		var drums := _ch[SidSong.DRUMS]
		var owner := SidSong.ACCOMP
		if (channel_mask & (1 << SidSong.DRUMS)) and drums.note > 0 and drums.value("volume", 15) > 0:
			owner = SidSong.DRUMS
		elif not (channel_mask & (1 << SidSong.ACCOMP)):
			owner = -1
		if owner >= 0:
			# A part taking voice 2 over starts its note afresh.
			_voice(owner, 1, _retrigger[owner] != 0 or owner != _owner)
		else:
			regs[11] &= 0xFE
		_owner = owner
	_retrigger = PackedInt32Array([0, 0, 0, 0])
	for r in SidChip.REGISTER_COUNT:
		apu.write(r, regs[r])


## Sets voice [param voice] for the part on [param channel]. With
## [param restart], the gate stays off this frame.
func _voice(channel: int, voice: int, restart: bool) -> void:
	var ch := _ch[channel]
	var base := voice * 7
	if ch.note <= 0:
		regs[base + 4] &= 0xFE
		return
	var inst := ch.instrument
	var wave := str(inst.get("wave", "pulse"))
	var freq := 0
	if wave == "noise":
		var index := ((ch.note + ch.arp_value()) & 0x0F) ^ 0x0F
		freq = SidSong.noise_freq(index)
	else:
		var midi := clampi(ch.note + ch.arp_value(), 0, 127)
		freq = SidSong.note_freq(midi)
		var bend := ch.value("pitch", 0)
		if bend != 0:
			# Pitch envelopes are in NES period steps: scale the frequency
			# as the NES period would move.
			var period := float(NesSong.note_period(clampi(midi - 23, NesSong.FIRST_NOTE, NesSong.LAST_NOTE)))
			freq = clampi(roundi(freq * (period + 1.0) / maxf(period + 1.0 + bend, 1.0)), 1, 65535)
	regs[base] = freq & 0xFF
	regs[base + 1] = freq >> 8
	var pw := int(inst.get("pw", -1))
	if pw < 0:
		pw = SidSong.DUTY_WIDTHS[ch.value("duty", 2) & 3]
	regs[base + 2] = pw & 0xFF
	regs[base + 3] = pw >> 8
	var bits := {"pulse": SidChip.PULSE, "saw": SidChip.SAW, "triangle": SidChip.TRIANGLE, "noise": SidChip.NOISE}.get(wave, SidChip.PULSE) as int
	regs[base + 4] = bits | (0 if restart else SidChip.GATE)
	regs[base + 5] = int(inst.get("ad", 0))
	var sr := int(inst.get("sr", 0xF0))
	var sustain := roundi((sr >> 4) * clampi(ch.volume, 0, 15) / 15.0)
	regs[base + 6] = (sustain << 4) | (sr & 0x0F)


func get_channel_volume(channel: int) -> int:
	var voice: int = SidSong.VOICE_OF[channel]
	if channel == SidSong.ACCOMP and _owner == SidSong.DRUMS:
		return 0
	if channel == SidSong.DRUMS and _owner != SidSong.DRUMS:
		return 0
	return apu.get_channel_volume(voice) if apu.has_method("get_channel_volume") else 0
