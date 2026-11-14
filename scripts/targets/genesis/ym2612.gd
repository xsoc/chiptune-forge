class_name Ym2612
extends RefCounted
## The Mega Drive's FM sound chip (Yamaha YM2612, OPN2), emulated for
## previews.
##
## Six channels of four operators each, with the chip's eight algorithms,
## operator 1 feedback, multipliers, detune, total level, key scaling and its
## attack, decay, sustain and release envelope. A driver writes registers
## with [method write], exactly as it would through ports $4000 to $4003 on
## the console, and [method render] adds the result to a mono buffer.
##
## It follows the chip's own arithmetic where that is audible: the phase
## increment ((F-number << block) >> 1, plus detune, times the multiplier),
## the envelope's rate table and 0.094 dB steps, and how far one operator
## moves another's phase. To keep previews fast in GDScript, the envelope is
## worked out every 32 output samples and eased in between, and the sine is
## read from a table. Not emulated: the LFO, channel 3's special mode,
## SSG-EG, the DAC (channel 6 PCM) and stereo panning (every channel plays in
## the middle).

## NTSC master clock. The chip makes one sample every 144 clocks.
const CLOCK := 7670453.0
const CHIP_RATE := CLOCK / 144.0
## The envelope generator steps once every three chip samples.
const EG_RATE := CHIP_RATE / 3.0
## Envelope attenuation is 10 bits: 0 is full volume, 1023 silent.
const EG_MAX := 1023.0
## Samples between envelope updates.
const SUB_BLOCK := 32
## Sine table length. Phases are kept in table steps.
const SINE_LEN := 4096
## How far a full-scale operator output moves the next operator's phase:
## four cycles, as on the chip (a 14-bit output, halved, against a 10-bit
## phase).
const MOD_CYCLES := 4.0
## Output level of one channel at full scale, in the preview mix.
const CHANNEL_LEVEL := 0.22

## Detune, in phase increment steps, for detune 1 to 3 and each key code.
const DT_TABLE := [
	[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 8, 8, 8, 8],
	[1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 8, 8, 9, 10, 11, 12, 13, 14, 16, 16, 16, 16],
	[2, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 8, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 20, 22, 22, 22, 22],
]
## Which operators feed which, per algorithm: [2 from 1, 3 from 1, 3 from 2,
## 4 from 1, 4 from 2, 4 from 3], and which operators are heard (carriers).
## Operators are numbered 1 to 4 as in Yamaha's diagrams.
const ROUTES := [
	[[1, 0, 1, 0, 0, 1], [0, 0, 0, 1]],
	[[0, 1, 1, 0, 0, 1], [0, 0, 0, 1]],
	[[0, 0, 1, 1, 0, 1], [0, 0, 0, 1]],
	[[1, 0, 0, 0, 1, 1], [0, 0, 0, 1]],
	[[1, 0, 0, 0, 0, 1], [0, 1, 0, 1]],
	[[1, 1, 0, 1, 0, 0], [0, 1, 1, 1]],
	[[1, 0, 0, 0, 0, 0], [0, 1, 1, 1]],
	[[0, 0, 0, 0, 0, 0], [1, 1, 1, 1]],
]
## Register slot order: the offsets +0, +4, +8 and +C are operators 1, 3,
## 2 and 4.
const SLOT_OPERATOR := [0, 2, 1, 3]

enum { ATTACK, DECAY, SUSTAIN, RELEASE, OFF }

static var SINE := _make_sine()

var mix_rate := 44100.0
## Per-channel gain for previews (mutes and fades). 1 is as the chip plays.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

# Per channel.
var _fnum := PackedInt32Array()
var _block := PackedInt32Array()
var _latch := PackedInt32Array()
var _algorithm := PackedInt32Array()
var _feedback := PackedInt32Array()
var _fb1 := PackedFloat32Array()
var _fb2 := PackedFloat32Array()
# Per operator: index channel * 4 + operator (0 to 3 for operators 1 to 4).
var _mul := PackedInt32Array()
var _dt := PackedInt32Array()
var _tl := PackedInt32Array()
var _ks := PackedInt32Array()
var _ar := PackedInt32Array()
var _d1r := PackedInt32Array()
var _d2r := PackedInt32Array()
var _sl := PackedInt32Array()
var _rr := PackedInt32Array()
var _key := PackedByteArray()
var _state := PackedInt32Array()
var _att := PackedFloat32Array()
var _phase := PackedFloat64Array()
var _inc := PackedFloat64Array()
var _dirty := PackedByteArray()
var _sample_ratio := 1.0


func _init(rate := 44100.0) -> void:
	mix_rate = rate
	_sample_ratio = CHIP_RATE / mix_rate
	reset()


static func _make_sine() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SINE_LEN)
	for i in SINE_LEN:
		out[i] = sin(TAU * (i + 0.5) / SINE_LEN)
	return out


## Every channel silent and every register cleared, as at power on.
func reset() -> void:
	for arr in [_fnum, _block, _latch, _algorithm, _feedback]:
		arr.resize(6)
		arr.fill(0)
	for arr in [_fb1, _fb2]:
		arr.resize(6)
		arr.fill(0.0)
	for arr in [_mul, _dt, _tl, _ks, _ar, _d1r, _d2r, _sl, _rr, _state]:
		arr.resize(24)
		arr.fill(0)
	_state.fill(OFF)
	_key.resize(24)
	_key.fill(0)
	_dirty.resize(6)
	_dirty.fill(1)
	_att.resize(24)
	_att.fill(EG_MAX)
	_phase.resize(24)
	_phase.fill(0.0)
	_inc.resize(24)
	_inc.fill(0.0)


## Writes register [param reg] in bank [param port] (0 for channels 1 to 3
## and the global registers, 1 for channels 4 to 6).
func write(port: int, reg: int, value: int) -> void:
	reg &= 0xFF
	value &= 0xFF
	if reg < 0x30:
		if port == 0 and reg == 0x28:
			_key_event(value)
		return
	var ch := reg & 3
	if ch == 3:
		return
	var channel := ch + 3 * (port & 1)
	if reg < 0xA0:
		var op: int = channel * 4 + SLOT_OPERATOR[(reg >> 2) & 3]
		match reg & 0xF0:
			0x30:
				_dt[op] = (value >> 4) & 7
				_mul[op] = value & 15
			0x40:
				_tl[op] = value & 0x7F
			0x50:
				_ks[op] = value >> 6
				_ar[op] = value & 31
			0x60:
				_d1r[op] = value & 31
			0x70:
				_d2r[op] = value & 31
			0x80:
				var level := value >> 4
				_sl[op] = 1023 if level == 15 else level * 32
				_rr[op] = value & 15
		_dirty[channel] = 1
		return
	match reg & 0xFC:
		0xA0:
			_fnum[channel] = ((_latch[channel] & 7) << 8) | value
			_block[channel] = (_latch[channel] >> 3) & 7
			_dirty[channel] = 1
		0xA4:
			# The high byte waits in a latch until the low byte is written.
			_latch[channel] = value & 0x3F
		0xB0:
			_algorithm[channel] = value & 7
			_feedback[channel] = (value >> 3) & 7


func _key_event(value: int) -> void:
	var code := value & 7
	if code == 3 or code == 7:
		return
	var channel := code if code < 3 else code - 1
	for op in 4:
		# Bits 4 to 7 key operators 1, 2, 3 and 4.
		var on := (value >> (4 + op)) & 1
		var i := channel * 4 + op
		if on and not _key[i]:
			_phase[i] = 0.0
			_state[i] = ATTACK
			if _rate(i, _ar[i] * 2) >= 62:
				_att[i] = 0.0
				_state[i] = DECAY
		elif not on and _key[i]:
			_state[i] = RELEASE
		_key[i] = on
	if value & 0xF0:
		_fb1[channel] = 0.0
		_fb2[channel] = 0.0


## The chip's key code for a channel: block and the top F-number bits.
func _keycode(channel: int) -> int:
	var f := _fnum[channel]
	var f11 := (f >> 10) & 1
	var n3 := (f11 & (((f >> 9) | (f >> 8) | (f >> 7)) & 1)) | ((1 - f11) & ((f >> 9) & (f >> 8) & (f >> 7) & 1))
	return (_block[channel] << 2) | (f11 << 1) | n3


## Effective envelope rate (0 to 63) for a register rate times two.
func _rate(op: int, doubled: int) -> int:
	if doubled <= 0:
		return 0
	var ksr := _keycode(op / 4) >> (3 - _ks[op])
	return mini(doubled + ksr, 63)


## Average attenuation change per envelope step at a rate.
static func rate_step(rate: int) -> float:
	if rate < 2:
		return 0.0
	if rate < 48:
		return [0.5, 0.625, 0.75, 0.875][rate & 3] / float(1 << (11 - rate / 4))
	if rate < 60:
		return [1.0, 1.25, 1.5, 1.75][rate & 3] * float(1 << ((rate - 48) / 4))
	return 8.0


func _update_frequency(channel: int) -> void:
	var kc := _keycode(channel)
	var base := (_fnum[channel] << _block[channel]) >> 1
	for op in 4:
		var i := channel * 4 + op
		var detune: int = DT_TABLE[_dt[i] & 3][kc]
		var step := base - detune if _dt[i] & 4 else base + detune
		step &= 0x1FFFF
		var inc: float = step * _mul[i] if _mul[i] > 0 else step / 2.0
		# Chip phase steps of 1 / 2^20 cycle, per output sample, in table steps.
		_inc[i] = inc / 1048576.0 * _sample_ratio * SINE_LEN
	_dirty[channel] = 0


## Moves the envelope of operator [param i] on by [param ticks] steps.
func _advance(i: int, ticks: float) -> void:
	match _state[i]:
		ATTACK:
			var r := _rate(i, _ar[i] * 2)
			if r >= 62:
				_att[i] = 0.0
			elif r > 0:
				var keep := pow(1.0 - minf(rate_step(r), 8.0) / 16.0, ticks)
				_att[i] = (_att[i] + 1.0) * keep - 1.0
			if _att[i] <= 0.0:
				_att[i] = 0.0
				_state[i] = DECAY
		DECAY:
			_att[i] += rate_step(_rate(i, _d1r[i] * 2)) * ticks
			if _att[i] >= _sl[i]:
				_att[i] = float(_sl[i])
				_state[i] = SUSTAIN
		SUSTAIN:
			_att[i] = minf(_att[i] + rate_step(_rate(i, _d2r[i] * 2)) * ticks, EG_MAX)
		RELEASE:
			_att[i] += rate_step(_rate(i, _rr[i] * 4 + 2)) * ticks
			if _att[i] >= EG_MAX:
				_att[i] = EG_MAX
				_state[i] = OFF


## Linear gain for an operator: envelope plus total level (0.75 dB per TL
## step, eight envelope steps), with 6 dB every 64 steps.
func _gain(i: int) -> float:
	var att := _att[i] + _tl[i] * 8.0
	if att >= EG_MAX or _state[i] == OFF:
		return 0.0
	return pow(2.0, -att / 64.0)


## Current loudness of a channel, 0 to 1, for meters.
func get_channel_level(channel: int) -> float:
	var carriers: Array = ROUTES[_algorithm[channel]][1]
	var level := 0.0
	for op in 4:
		if carriers[op]:
			level = maxf(level, _gain(channel * 4 + op))
	return level


func is_channel_silent(channel: int) -> bool:
	var carriers: Array = ROUTES[_algorithm[channel]][1]
	for op in 4:
		var i := channel * 4 + op
		if carriers[op] and _state[i] != OFF and _att[i] + _tl[i] * 8.0 < EG_MAX:
			return false
	return true


## Adds [param count] samples of every channel to [param out].
func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	for channel in 6:
		if _dirty[channel]:
			_update_frequency(channel)
		if is_channel_silent(channel):
			# Envelopes still move on, so a released note stays released.
			for op in 4:
				if _state[channel * 4 + op] != OFF:
					_advance(channel * 4 + op, count * EG_RATE / mix_rate)
			continue
		_render_channel(channel, out, offset, count)


func _render_channel(channel: int, out: PackedFloat32Array, offset: int, count: int) -> void:
	var b := channel * 4
	var route: Array = ROUTES[_algorithm[channel]]
	var links: Array = route[0]
	var carriers: Array = route[1]
	var depth := MOD_CYCLES * SINE_LEN
	var m21: float = links[0] * depth
	var m31: float = links[1] * depth
	var m32: float = links[2] * depth
	var m41: float = links[3] * depth
	var m42: float = links[4] * depth
	var m43: float = links[5] * depth
	var c1: float = carriers[0]
	var c2: float = carriers[1]
	var c3: float = carriers[2]
	var fb := _feedback[channel]
	# Operator 1 feeds back the average of its last two outputs.
	var fbk := pow(2.0, fb - 7) * SINE_LEN if fb > 0 else 0.0
	var level := CHANNEL_LEVEL * channel_gain[channel]
	var sine := SINE
	var mask := SINE_LEN - 1
	var p1 := _phase[b]
	var p2 := _phase[b + 1]
	var p3 := _phase[b + 2]
	var p4 := _phase[b + 3]
	var i1 := _inc[b]
	var i2 := _inc[b + 1]
	var i3 := _inc[b + 2]
	var i4 := _inc[b + 3]
	var f1 := _fb1[channel]
	var f2 := _fb2[channel]
	var ticks_per_sample := EG_RATE / mix_rate
	var done := 0
	while done < count:
		var n := mini(SUB_BLOCK, count - done)
		var g1 := _gain(b)
		var g2 := _gain(b + 1)
		var g3 := _gain(b + 2)
		var g4 := _gain(b + 3)
		for op in 4:
			_advance(b + op, n * ticks_per_sample)
		var d1 := (_gain(b) - g1) / n
		var d2 := (_gain(b + 1) - g2) / n
		var d3 := (_gain(b + 2) - g3) / n
		var d4 := (_gain(b + 3) - g4) / n
		var at := offset + done
		for k in n:
			var o1 := sine[int(p1 + (f1 + f2) * fbk) & mask] * g1
			f2 = f1
			f1 = o1
			var o2 := sine[int(p2 + o1 * m21) & mask] * g2
			var o3 := sine[int(p3 + o1 * m31 + o2 * m32) & mask] * g3
			var o4 := sine[int(p4 + o1 * m41 + o2 * m42 + o3 * m43) & mask] * g4
			var s := o1 * c1 + o2 * c2 + o3 * c3 + o4
			out[at + k] += clampf(s, -1.0, 1.0) * level
			p1 += i1
			p2 += i2
			p3 += i3
			p4 += i4
			g1 += d1
			g2 += d2
			g3 += d3
			g4 += d4
		done += n
		p1 = fmod(p1, SINE_LEN)
		p2 = fmod(p2, SINE_LEN)
		p3 = fmod(p3, SINE_LEN)
		p4 = fmod(p4, SINE_LEN)
	_phase[b] = p1
	_phase[b + 1] = p2
	_phase[b + 2] = p3
	_phase[b + 3] = p4
	_fb1[channel] = f1
	_fb2[channel] = f2
