class_name SpeakerSound
extends RefCounted
## The PC speaker: a square wave from the timer chip at 1.19 MHz divided by
## a 16-bit divisor, switched on or off, through a small paper cone.
##
## [SpeakerPlayer] hands it two divisors a frame, each for 1/140 s (0 is
## off). The cone's response is a gentle low-pass and a cut below 100 Hz.

## Per part (lead, bass, drums): the mute and fade gains the sequencer sets;
## the player leaves a part out while its gain is near zero.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0])
var mix_rate := 44100.0

var _slots := PackedInt32Array([0, 0])
var _pos := 0.0
var _phase := 0.0
var _lp := 0.0
var _hp_in := 0.0
var _hp_out := 0.0
var _lp_k := 0.0
var _hp_k := 0.0


func _init(rate := 44100.0) -> void:
	mix_rate = rate
	_lp_k = 1.0 - exp(-TAU * 7000.0 / rate)
	_hp_k = exp(-TAU * 100.0 / rate)


func reset() -> void:
	_slots = PackedInt32Array([0, 0])
	_pos = 0.0
	_phase = 0.0


func set_gain(channel: int, gain: float) -> void:
	channel_gain[channel] = gain


## The divisors for the next frame's two halves.
func write_frame(first: int, second: int) -> void:
	_slots = PackedInt32Array([first, second])
	_pos = 0.0


## True when the speaker is sounding now.
func is_on() -> bool:
	return _slots[0] > 0 or _slots[1] > 0


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	var half := mix_rate / (SpeakerSong.FRAME_HZ * SpeakerSong.SLOTS)
	var phase := _phase
	var lp := _lp
	var x0 := _hp_in
	var y := _hp_out
	for i in count:
		var slot := mini(int(_pos / half), SpeakerSong.SLOTS - 1)
		_pos += 1.0
		var div := _slots[slot]
		var v := 0.0
		if div > 0:
			var inc := minf(SpeakerSong.PIT_HZ / div / mix_rate, 0.5)
			phase += inc
			if phase >= 1.0:
				phase -= 1.0
			v = 1.0 if phase < 0.5 else -1.0
			v += NesApu._blep(phase, inc)
			var t2 := phase - 0.5
			if t2 < 0.0:
				t2 += 1.0
			v -= NesApu._blep(t2, inc)
			v *= 0.3
		lp += (v - lp) * _lp_k
		y = _hp_k * (y + lp - x0)
		x0 = lp
		out[offset + i] = y
	_phase = phase
	_lp = lp
	_hp_in = x0
	_hp_out = y
