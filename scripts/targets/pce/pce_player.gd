class_name PcePlayer
extends NesPlayer
## Plays a [PceSong] one video frame at a time, writing the PC Engine PSG's
## registers exactly as our C player (pce_player.c) does.
##
## Notes, durations, arpeggios and envelopes work as in [NesPlayer]. Each
## frame, for every channel in [member channel_mask], it selects the
## channel, loads the instrument's waveform if the channel holds another
## one, then writes the noise control (channels 5 and 6), the frequency and
## the volume. The pitch envelope moves the note in sixteenths of a
## semitone, measured on the frequency table.

## Channels this player may write, as a bit mask over [PceSong] channels.
var channel_mask := 0x3F
## Per channel, the waveform it holds (-1 for none yet).
var loaded_wave := PackedInt32Array([-1, -1, -1, -1, -1, -1])

var _periods := PackedInt32Array()


func _init(pce_song: PceSong, psg: Variant) -> void:
	for n in 128:
		_periods.append(PceSong.note_period(n))
	super(pce_song, psg)


func _reset_chip() -> void:
	apu.reset()
	loaded_wave = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	apu.write(PcePsg.MAIN_BALANCE, 0xFF)
	var pce := song as PceSong
	for c in PceSong.CHANNEL_COUNT:
		if channel_mask & (1 << c):
			apu.write(PcePsg.SELECT, c)
			apu.write(PcePsg.CONTROL, 0)
			apu.write(PcePsg.BALANCE, pce.balances[c])


func _output(channel: int) -> void:
	if not (channel_mask & (1 << channel)):
		return
	var ch = _ch[channel]
	write_channel(apu, song as PceSong, channel, ch.note, ch.instrument, ch.volume, ch.value("volume", 15), ch.arp_value(), ch.value("pitch", 0), loaded_wave, _periods)


## The C player's per-channel update, shared with [PceSfx]: writes channel
## [param channel]'s registers for [param note] (0 for none) played by
## [param inst] at [param volume] with the envelopes' current values.
static func write_channel(psg: Variant, pce: PceSong, channel: int, note: int, inst: Dictionary, volume: int, env_volume: int, arp: int, pitch: int, loaded: PackedInt32Array, periods: PackedInt32Array) -> void:
	psg.write(PcePsg.SELECT, channel)
	if note <= 0 or inst.is_empty():
		psg.write(PcePsg.CONTROL, PcePsg.ON)
		return
	var noise := bool(inst.get("noise", false))
	var wave := int(inst.get("wave", 0))
	if not noise and loaded[channel] != wave:
		psg.write(PcePsg.CONTROL, PcePsg.DDA)
		psg.write(PcePsg.CONTROL, 0)
		for v in pce.waves[wave]:
			psg.write(PcePsg.WAVE, int(v))
		loaded[channel] = wave
	if noise:
		psg.write(PcePsg.NOISE, 0x80 | clampi(note + arp, 0, 31))
	else:
		if channel >= 4:
			psg.write(PcePsg.NOISE, 0)
		var n := clampi(note + arp, 0, 127)
		var period := periods[n]
		if pitch != 0:
			var k := mini(n, 126)
			var step := periods[k] - periods[k + 1]
			if pitch > 0:
				period -= (step * pitch) >> 4
			else:
				period += (step * -pitch) >> 4
		period = clampi(period, 1, 4095)
		psg.write(PcePsg.FREQ_LO, period & 0xFF)
		psg.write(PcePsg.FREQ_HI, period >> 8)
	var level := SmsSong.mix_level(volume, env_volume)
	psg.write(PcePsg.CONTROL, PcePsg.ON | PceSong.volume_of_level(level))


func get_channel_volume(channel: int) -> int:
	var ch = _ch[channel]
	if ch.note <= 0:
		return 0
	return SmsSong.mix_level(ch.volume, ch.value("volume", 15))
