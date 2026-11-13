class_name NesApu
extends RefCounted
## The NES / Famicom sound hardware (the Ricoh 2A03's APU), emulated for
## previews.
##
## Two pulse channels, the triangle and the noise channel, mixed through the
## console's non-linear DACs and its output filters. A sound driver writes
## registers with [method write], exactly as it would on the console, and
## [method render] mixes the result into a mono buffer.
##
## Accuracy is at the register level, not the cycle level: register writes
## take effect at the start of the next rendered block, which is how a driver
## uses them (once per frame). Volumes are the constant-volume mode that
## FamiStudio's sound engine uses; the hardware envelopes, length counters and
## sweep units are not emulated, and neither is the DPCM channel.

## NTSC CPU clock.
const CPU_HZ := 1789773.0
## NTSC frame rate (the NMI that drives the sound engine).
const FRAME_HZ := 60.0988

const PULSE1_VOL := 0x4000
const PULSE1_SWEEP := 0x4001
const PULSE1_LO := 0x4002
const PULSE1_HI := 0x4003
const PULSE2_VOL := 0x4004
const PULSE2_SWEEP := 0x4005
const PULSE2_LO := 0x4006
const PULSE2_HI := 0x4007
const TRI_LINEAR := 0x4008
const TRI_LO := 0x400A
const TRI_HI := 0x400B
const NOISE_VOL := 0x400C
const NOISE_LO := 0x400E
const NOISE_HI := 0x400F
const STATUS := 0x4015

const DUTY := [0.125, 0.25, 0.5, 0.75]
## Noise timer periods in CPU cycles (NTSC), by the 4-bit period index.
const NOISE_PERIODS := [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]
## The triangle's 32-step output sequence.
const TRIANGLE_STEPS := [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

var mix_rate := 44100.0
## Per-channel gain for previews (mutes and adaptive fades). 1 is as the
## hardware plays it.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])

var _regs := PackedByteArray()
var _enabled := 0
# Per channel: phase (0 to 1 of a waveform cycle, or of a noise step).
var _phase := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _lfsr := 1
var _noise_out := 0.0
# Output filters: two high-passes (90 Hz and 440 Hz) and a 14 kHz low-pass,
# as on the console's board.
var _hp1_k := 0.0
var _hp2_k := 0.0
var _lp_k := 0.0
var _hp1_prev_in := 0.0
var _hp1_prev_out := 0.0
var _hp2_prev_in := 0.0
var _hp2_prev_out := 0.0
var _lp_out := 0.0
# Scratch buffers, one per channel, holding 0 to 15 levels.
var _levels: Array[PackedFloat32Array] = []


func _init(rate := 44100.0) -> void:
	mix_rate = rate
	_hp1_k = _rc(90.0)
	_hp2_k = _rc(440.0)
	_lp_k = 1.0 - exp(-TAU * 14000.0 / mix_rate)
	for i in 4:
		_levels.append(PackedFloat32Array())
	reset()


func _rc(cutoff: float) -> float:
	var rc := 1.0 / (TAU * cutoff)
	var dt := 1.0 / mix_rate
	return rc / (rc + dt)


## Silences every channel, as at power on.
func reset() -> void:
	_regs.resize(0x18)
	_regs.fill(0)
	_enabled = 0
	_phase = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	_lfsr = 1
	_noise_out = 0.0


func read(address: int) -> int:
	if address < 0x4000 or address > 0x4017:
		return 0
	return _regs[address - 0x4000]


## Writes a sound register. Writing a pulse channel's high period byte
## restarts its duty cycle, as on the hardware (which is why drivers only
## write it when it changes).
func write(address: int, value: int) -> void:
	if address < 0x4000 or address > 0x4017:
		return
	value &= 0xFF
	_regs[address - 0x4000] = value
	match address:
		PULSE1_HI:
			_phase[0] = 0.0
		PULSE2_HI:
			_phase[1] = 0.0
		STATUS:
			_enabled = value & 0x0F


func pulse_period(index: int) -> int:
	var base := 0x4000 + index * 4
	return _regs[base + 2 - 0x4000] | ((_regs[base + 3 - 0x4000] & 7) << 8)


func triangle_period() -> int:
	return _regs[TRI_LO - 0x4000] | ((_regs[TRI_HI - 0x4000] & 7) << 8)


## Current 4-bit volume of a channel (0 when it is silent), for meters. The
## triangle has no volume control: it reads 15 while it plays.
func get_channel_volume(index: int) -> int:
	if not (_enabled & (1 << index)):
		return 0
	match index:
		0, 1:
			if pulse_period(index) < 8:
				return 0
			return _regs[index * 4] & 0x0F
		2:
			return 15 if (_regs[TRI_LINEAR - 0x4000] & 0x7F) != 0 and triangle_period() >= 2 else 0
		3:
			return _regs[NOISE_VOL - 0x4000] & 0x0F
	return 0


## Mixes [param count] samples into [param out] from [param offset] on
## (overwriting what is there).
func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	for i in 4:
		if _levels[i].size() < count:
			_levels[i].resize(count)
	_render_pulse(0, count)
	_render_pulse(1, count)
	_render_triangle(count)
	_render_noise(count)
	var p1 := _levels[0]
	var p2 := _levels[1]
	var tri := _levels[2]
	var noise := _levels[3]
	var hp1_k := _hp1_k
	var hp2_k := _hp2_k
	var lp_k := _lp_k
	var hp1_in := _hp1_prev_in
	var hp1_out := _hp1_prev_out
	var hp2_in := _hp2_prev_in
	var hp2_out := _hp2_prev_out
	var lp := _lp_out
	for i in count:
		# The 2A03's two non-linear DACs (nesdev's mixer formulas).
		var pulse := p1[i] + p2[i]
		var s := 0.0
		if pulse > 0.0:
			s = 95.88 / (8128.0 / pulse + 100.0)
		var tnd := tri[i] / 8227.0 + noise[i] / 12241.0
		if tnd > 0.0:
			s += 159.79 / (1.0 / tnd + 100.0)
		var a := hp1_k * (hp1_out + s - hp1_in)
		hp1_in = s
		hp1_out = a
		var b := hp2_k * (hp2_out + a - hp2_in)
		hp2_in = a
		hp2_out = b
		lp += (b - lp) * lp_k
		out[offset + i] = lp
	_hp1_prev_in = hp1_in
	_hp1_prev_out = hp1_out
	_hp2_prev_in = hp2_in
	_hp2_prev_out = hp2_out
	_lp_out = lp


func _render_pulse(index: int, count: int) -> void:
	var buf := _levels[index]
	var period := pulse_period(index)
	var volume := float(_regs[index * 4] & 0x0F) * channel_gain[index]
	if not (_enabled & (1 << index)) or period < 8 or volume <= 0.0:
		for i in count:
			buf[i] = 0.0
		return
	var freq := CPU_HZ / (16.0 * (period + 1))
	var inc := minf(freq / mix_rate, 0.5)
	var duty: float = DUTY[_regs[index * 4] >> 6]
	var phase := _phase[index]
	for i in count:
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		var sq := 1.0 if phase < duty else 0.0
		sq += 0.5 * _blep(phase, inc)
		var t2 := phase - duty
		if t2 < 0.0:
			t2 += 1.0
		sq -= 0.5 * _blep(t2, inc)
		buf[i] = clampf(sq, 0.0, 1.0) * volume
	_phase[index] = phase


func _render_triangle(count: int) -> void:
	var buf := _levels[2]
	var period := triangle_period()
	var phase := _phase[2]
	var gain := channel_gain[2]
	var running := (_enabled & 4) != 0 and (_regs[TRI_LINEAR - 0x4000] & 0x7F) != 0 and period >= 2
	if not running:
		# A halted triangle holds its current step: no click.
		var held := float(TRIANGLE_STEPS[int(phase * 32.0) & 31]) * gain
		for i in count:
			buf[i] = held
		return
	var inc := CPU_HZ / (32.0 * (period + 1)) / mix_rate
	for i in count:
		phase += inc
		while phase >= 1.0:
			phase -= 1.0
		# Average the two neighbouring steps by position: cheap smoothing
		# that keeps high notes from aliasing harshly.
		var pos := phase * 32.0
		var k := int(pos)
		var frac := pos - k
		var a: float = TRIANGLE_STEPS[k & 31]
		var b: float = TRIANGLE_STEPS[(k + 1) & 31]
		buf[i] = (a + (b - a) * frac) * gain
	_phase[2] = phase


func _render_noise(count: int) -> void:
	var buf := _levels[3]
	var volume := float(_regs[NOISE_VOL - 0x4000] & 0x0F) * channel_gain[3]
	if not (_enabled & 8) or volume <= 0.0:
		for i in count:
			buf[i] = 0.0
		return
	var lo := _regs[NOISE_LO - 0x4000]
	var short := (lo & 0x80) != 0
	var clock := CPU_HZ / float(NOISE_PERIODS[lo & 0x0F])
	var inc := clock / mix_rate
	var lfsr := _lfsr
	var out := _noise_out
	var phase := _phase[3]
	var tap := 6 if short else 1
	for i in count:
		phase += inc
		if phase >= 1.0:
			# Average every LFSR step within this sample: a box filter that
			# keeps high noise rates from aliasing.
			var sum := 0.0
			var steps := 0
			while phase >= 1.0:
				phase -= 1.0
				var bit := (lfsr ^ (lfsr >> tap)) & 1
				lfsr = (lfsr >> 1) | (bit << 14)
				sum += float(~lfsr & 1)
				steps += 1
			out = sum / steps
		buf[i] = out * volume
	_lfsr = lfsr
	_noise_out = out
	_phase[3] = phase


static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0
