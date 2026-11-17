class_name SidChip
extends RefCounted
## The Commodore 64's sound chip, the MOS 6581/8580 SID, emulated for
## previews.
##
## Three voices, each an oscillator (triangle, sawtooth, pulse with a 12-bit
## width, or noise) shaped by its own ADSR envelope generator, mixed at the
## master volume. A driver writes the 25 registers ($D400-$D418) with
## [method write] and [method render] mixes the result into a mono buffer.
## Writes take effect at the start of the next rendered block, which is how
## a driver uses them (once per frame).
##
## The envelope generator follows the chip's documented behaviour (rate
## counter periods, the exponential decay steps, attack restarting from the
## current level), including its "ADSR bug": when a write makes the rate
## faster while the 15-bit rate counter is already past the new period, the
## counter wraps all the way round first and the envelope freezes for up to
## 33 ms. [SidPlayer]'s hard restarts keep notes clear of it. The filter, ring modulation, sync and combined waveforms
## are not emulated: our player never uses them.

## PAL clock.
const CLOCK := 985248.0
const REGISTER_COUNT := 25
const GATE := 0x01
const TEST := 0x08
const TRIANGLE := 0x10
const SAW := 0x20
const PULSE := 0x40
const NOISE := 0x80
## Clock cycles per envelope step for each attack, decay and release rate.
## The rate counter is 15 bits.
const RATE_COUNTER_WRAP := 32768.0
const RATE_PERIODS: PackedInt32Array = [9, 32, 63, 95, 149, 220, 267, 313, 392, 977, 1954, 3126, 3907, 11720, 19532, 31251]

var mix_rate := 44100.0
## Per-part gain for previews (mutes and adaptive fades), indexed by the
## song's four channels: lead, accompaniment, bass and drums. Voice 2 takes
## the drums' gain while it plays noise.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var regs := PackedInt32Array()

var _phase := PackedFloat64Array([0.0, 0.0, 0.0])
var _level := PackedInt32Array([0, 0, 0])
## Envelope state per voice: 0 attack, 1 decay/sustain, 2 release.
var _state := PackedInt32Array([2, 2, 2])
var _env_cycles := PackedFloat64Array([0.0, 0.0, 0.0])
## The rate counter's period on the last block, per voice.
var _period := PackedInt32Array([9, 9, 9])
var _exp_count := PackedInt32Array([0, 0, 0])
var _gate := PackedInt32Array([0, 0, 0])
var _lfsr := PackedInt32Array([0x7FFFF8, 0x7FFFF8, 0x7FFFF8])
var _noise_out := PackedFloat32Array([0.0, 0.0, 0.0])
var _hp_k := 0.0
var _hp_in := 0.0
var _hp_out := 0.0


func _init(rate := 44100.0) -> void:
	mix_rate = rate
	var rc := 1.0 / (TAU * 16.0)
	var dt := 1.0 / mix_rate
	_hp_k = rc / (rc + dt)
	reset()


func reset() -> void:
	regs = PackedInt32Array()
	regs.resize(REGISTER_COUNT)
	for v in 3:
		_level[v] = 0
		_state[v] = 2
		_gate[v] = 0
		_env_cycles[v] = 0.0
		_period[v] = 9


func write(reg: int, value: int) -> void:
	if reg < 0 or reg >= REGISTER_COUNT:
		return
	regs[reg] = value & 0xFF


func frequency(voice: int) -> int:
	return regs[voice * 7] | (regs[voice * 7 + 1] << 8)


func pulse_width(voice: int) -> int:
	return regs[voice * 7 + 2] | ((regs[voice * 7 + 3] & 0x0F) << 8)


func control(voice: int) -> int:
	return regs[voice * 7 + 4]


func envelope_level(voice: int) -> int:
	return _level[voice]


## Current loudness of a voice as 0 to 15, for meters.
func get_channel_volume(voice: int) -> int:
	return _level[voice] >> 4


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	for i in count:
		out[offset + i] = 0.0
	var master := (regs[24] & 0x0F) / 15.0
	for v in 3:
		_render_voice(v, out, offset, count, master)
	var k := _hp_k
	var x0 := _hp_in
	var y := _hp_out
	for i in count:
		var x := out[offset + i]
		y = k * (y + x - x0)
		x0 = x
		out[offset + i] = y
	_hp_in = x0
	_hp_out = y


func _render_voice(v: int, out: PackedFloat32Array, offset: int, count: int, master: float) -> void:
	var ctrl := control(v)
	var gate := ctrl & GATE
	if gate != _gate[v]:
		_state[v] = 0 if gate else 2
		_gate[v] = gate
	var ad := regs[v * 7 + 5]
	var sr := regs[v * 7 + 6]
	var periods := [RATE_PERIODS[ad >> 4], RATE_PERIODS[ad & 0x0F], RATE_PERIODS[sr & 0x0F]]
	var sustain := (sr >> 4) * 17
	var cycles_per_sample := CLOCK / mix_rate
	var inc := frequency(v) * cycles_per_sample / 16777216.0
	var pw := pulse_width(v) / 4096.0
	var gain := channel_gain[3] if v == 1 and (ctrl & NOISE) else channel_gain[[0, 1, 2][v]]
	var scale := master * gain * 0.3 / 255.0
	var wave := ctrl & 0xF0
	var test := (ctrl & TEST) != 0
	var phase := _phase[v]
	var level := _level[v]
	var state := _state[v]
	var env := _env_cycles[v]
	# The ADSR bug: a counter already past a new, shorter period counts on
	# to 0x7FFF and wraps before the envelope steps again.
	var start_period: int = periods[mini(state, 2)]
	if start_period != _period[v] and env >= start_period:
		env -= RATE_COUNTER_WRAP
	var exp_count := _exp_count[v]
	var lfsr := _lfsr[v]
	var noise := _noise_out[v]
	for i in count:
		# Envelope.
		env += cycles_per_sample
		var period: int = periods[mini(state, 2)]
		while env >= period:
			env -= period
			if state == 0:
				level += 1
				if level >= 255:
					level = 255
					state = 1
			else:
				exp_count += 1
				if exp_count >= _exp_period(level):
					exp_count = 0
					if state == 1:
						if level > sustain:
							level -= 1
					elif level > 0:
						level -= 1
			if state != 0:
				period = periods[mini(state, 2)]
		# Oscillator.
		var s := 0.0
		if test or wave == 0:
			s = 0.0
		else:
			var prev := phase
			phase += inc
			var wrapped := phase >= 1.0
			if wrapped:
				phase -= 1.0
			if wave & NOISE:
				# The shift register steps on every rise of bit 19: 16 times
				# a cycle.
				var steps := int(floor((prev + (1.0 if wrapped else 0.0)) * 16.0)) - int(floor(prev * 16.0))
				for k in steps:
					var bit := ((lfsr >> 22) ^ (lfsr >> 17)) & 1
					lfsr = ((lfsr << 1) | bit) & 0x7FFFFF
				if steps > 0:
					var bits := ((lfsr >> 20) & 1) << 7 | ((lfsr >> 18) & 1) << 6 | ((lfsr >> 14) & 1) << 5 | ((lfsr >> 11) & 1) << 4 \
						| ((lfsr >> 9) & 1) << 3 | ((lfsr >> 5) & 1) << 2 | ((lfsr >> 2) & 1) << 1 | (lfsr & 1)
					noise = bits / 127.5 - 1.0
				s = noise
			elif wave & PULSE:
				s = 1.0 if phase >= pw else -1.0
				if inc < 0.5:
					s -= NesApu._blep(phase, inc)
					var t2 := phase - pw
					if t2 < 0.0:
						t2 += 1.0
					s += NesApu._blep(t2, inc)
			elif wave & SAW:
				s = 2.0 * phase - 1.0
				if inc < 0.5:
					s -= NesApu._blep(phase, inc)
			else:
				s = 1.0 - 4.0 * absf(phase - 0.5)
		out[offset + i] += s * level * scale
	_phase[v] = phase
	_level[v] = level
	_state[v] = state
	_env_cycles[v] = env
	_period[v] = periods[mini(state, 2)]
	_exp_count[v] = exp_count
	_lfsr[v] = lfsr
	_noise_out[v] = noise


static func _exp_period(level: int) -> int:
	if level >= 93:
		return 1
	if level >= 54:
		return 2
	if level >= 26:
		return 4
	if level >= 14:
		return 8
	if level >= 6:
		return 16
	return 30
