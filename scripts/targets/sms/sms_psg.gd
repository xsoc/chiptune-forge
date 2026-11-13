class_name SmsPsg
extends RefCounted
## The Master System and Game Gear sound chip (the SN76489 PSG inside the
## VDP), emulated for previews.
##
## Three square-wave tone channels and a noise channel, each with a 4-bit
## attenuation in 2 dB steps. A driver writes bytes with [method write],
## exactly as it would to port $7F on the console, and [method render] mixes
## the result into a mono buffer. Writes take effect at the start of the next
## rendered block, which is how a driver uses them (once per frame).
##
## Noise uses Sega's 16-bit shift register (taps on bits 0 and 3). Game Gear
## stereo is not emulated: every channel plays in the middle.

## NTSC master clock. The chip divides it by 16, and a tone counter of
## period N makes a square wave of CLOCK / (32 N).
const CLOCK := 3579545.0
## Output level for each attenuation step: 2 dB per step, 15 is silent.
static var LEVELS := _make_levels()

var mix_rate := 44100.0
## Per-channel gain for previews (mutes and adaptive fades). 1 is as the
## hardware plays it.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])

## Tone periods (10 bits) for channels 0 to 2.
var _period := PackedInt32Array([0, 0, 0])
## Attenuation (0 loudest, 15 silent) for channels 0 to 3.
var _att := PackedInt32Array([15, 15, 15, 15])
## Noise control: bit 2 is white noise, bits 0 and 1 the rate (3 follows
## tone channel 2).
var _noise := 0
var _latch := 0
var _lfsr := 0x8000
# Per channel: phase (0 to 1 of a waveform cycle, or of a noise step).
var _phase := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _noise_out := 0.0
var _hp_k := 0.0
var _hp_in := 0.0
var _hp_out := 0.0


func _init(rate := 44100.0) -> void:
	mix_rate = rate
	# The console's output is AC coupled; this keeps the mix centred.
	var rc := 1.0 / (TAU * 20.0)
	var dt := 1.0 / mix_rate
	_hp_k = rc / (rc + dt)
	reset()


static func _make_levels() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 16:
		out.append(0.0 if i == 15 else pow(10.0, -i / 10.0))
	return out


## Silences every channel and clears the registers, as at power on.
func reset() -> void:
	_period = PackedInt32Array([0, 0, 0])
	_att = PackedInt32Array([15, 15, 15, 15])
	_noise = 0
	_latch = 0
	_lfsr = 0x8000
	_noise_out = 0.0


## Writes one byte to the chip. A latch byte (bit 7 set) picks a register and
## sets its low 4 bits; a data byte sets the high 6 bits of a tone period, or
## the whole of any other register.
func write(value: int) -> void:
	value &= 0xFF
	if value & 0x80:
		_latch = (value >> 4) & 7
		_store(value & 0x0F, true)
	else:
		_store(value & 0x3F, false)


func _store(bits: int, low: bool) -> void:
	var channel := _latch >> 1
	if _latch & 1:
		_att[channel] = bits & 0x0F
	elif channel < 3:
		if low:
			_period[channel] = (_period[channel] & 0x3F0) | (bits & 0x0F)
		else:
			_period[channel] = (_period[channel] & 0x0F) | ((bits & 0x3F) << 4)
	else:
		# Any write to the noise register restarts the shift register.
		_noise = bits & 0x07
		_lfsr = 0x8000


func tone_period(channel: int) -> int:
	return _period[channel]


func attenuation(channel: int) -> int:
	return _att[channel]


func noise_control() -> int:
	return _noise


## Current loudness of a channel as 0 to 15 (15 is full), for meters.
func get_channel_volume(channel: int) -> int:
	return 15 - _att[channel]


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	for i in count:
		out[offset + i] = 0.0
	for c in 3:
		_render_tone(c, out, offset, count)
	_render_noise(out, offset, count)
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


func _render_tone(channel: int, out: PackedFloat32Array, offset: int, count: int) -> void:
	var period := _period[channel]
	var level: float = LEVELS[_att[channel]] * channel_gain[channel] * 0.25
	if period < 2 or level <= 0.0:
		return
	var inc := minf(CLOCK / (32.0 * period) / mix_rate, 0.5)
	var phase := _phase[channel]
	for i in count:
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		var sq := 1.0 if phase < 0.5 else -1.0
		sq += NesApu._blep(phase, inc)
		var t2 := phase - 0.5
		if t2 < 0.0:
			t2 += 1.0
		sq -= NesApu._blep(t2, inc)
		out[offset + i] += sq * level
	_phase[channel] = phase


func _render_noise(out: PackedFloat32Array, offset: int, count: int) -> void:
	var level: float = LEVELS[_att[3]] * channel_gain[3] * 0.25
	if level <= 0.0:
		return
	var rate := _noise & 3
	var period := _period[2] if rate == 3 else (16 << rate)
	if period < 1:
		return
	# The shift register steps once per cycle of its counter.
	var inc := CLOCK / (32.0 * period) / mix_rate
	var white := (_noise & 4) != 0
	var lfsr := _lfsr
	var held := _noise_out
	var phase := _phase[3]
	for i in count:
		phase += inc
		if phase >= 1.0:
			# Average every step within this sample: a box filter that keeps
			# high noise rates from aliasing.
			var sum := 0.0
			var steps := 0
			while phase >= 1.0:
				phase -= 1.0
				var bit := lfsr & 1
				var feedback := (bit ^ ((lfsr >> 3) & 1)) if white else bit
				lfsr = (lfsr >> 1) | (feedback << 15)
				sum += float(bit)
				steps += 1
			held = sum / steps
		out[offset + i] += (held * 2.0 - 1.0) * level
	_lfsr = lfsr
	_noise_out = held
	_phase[3] = phase
