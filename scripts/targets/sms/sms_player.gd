class_name SmsPlayer
extends NesPlayer
## Plays an [SmsSong] one video frame at a time, writing the SN76489's port.
##
## Notes, durations, arpeggios and envelopes work as in [NesPlayer]. Each
## frame it writes only the registers that changed, in the order PSGlib's
## converter keeps them (per channel the tone, then the volume; noise last),
## so the bytes it writes are the song's PSGlib data. [PsgWriter] records
## them with a chip stand-in.

## Channels this player may write, as a bit mask. A sound effect writes only
## its own channel, so the music keeps the rest.
var channel_mask := 0x0F

# The last value written to each register, or -1 to write it next frame.
var _sent_period := PackedInt32Array([-1, -1, -1])
var _sent_level := PackedInt32Array([-1, -1, -1, -1])
var _sent_noise := -1
var _retrigger := false


func _reset_chip() -> void:
	apu.reset()
	invalidate()


## Forgets what the chip holds, so the next frame writes every register.
## Used at the loop point, where the chip may hold the song's last frame.
func invalidate() -> void:
	_sent_period = PackedInt32Array([-1, -1, -1])
	_sent_level = PackedInt32Array([-1, -1, -1, -1])
	_sent_noise = -1


func _attack(channel: int, n: Dictionary) -> void:
	super(channel, n)
	if channel == SmsSong.NOISE:
		# Restart the shift register on every hit, for a crisp attack.
		_retrigger = true


func _output(channel: int) -> void:
	if not (channel_mask & (1 << channel)):
		return
	var ch = _ch[channel]
	var level := SmsSong.mix_level(ch.volume, ch.value("volume", 15)) if ch.note > 0 else 0
	var latch := channel << 5
	if channel < 3:
		if ch.note > 0:
			var midi := clampi(ch.note + ch.arp_value(), 0, 127)
			var period := clampi(SmsSong.tone_period(midi) + ch.value("pitch", 0), 1, 1023)
			var sent := _sent_period[channel]
			if period != sent:
				apu.write(0x80 | latch | (period & 0x0F))
				if sent < 0 or (period >> 4) != (sent >> 4):
					# Data bytes carry bit 6 set, as PSGlib's tools write them.
					apu.write(0x40 | (period >> 4))
				_sent_period[channel] = period
	elif ch.note > 0:
		var rate := clampi(ch.note + ch.arp_value(), 0, 2)
		var control := ((ch.value("duty", 1) & 1) << 2) | rate
		if control != _sent_noise or _retrigger:
			apu.write(0xE0 | control)
			_sent_noise = control
		_retrigger = false
	if level != _sent_level[channel]:
		apu.write(0x90 | latch | (15 - level))
		_sent_level[channel] = level


func get_channel_volume(channel: int) -> int:
	var ch = _ch[channel]
	if ch.note <= 0:
		return 0
	return SmsSong.mix_level(ch.volume, ch.value("volume", 15))
