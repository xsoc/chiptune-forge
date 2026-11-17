class_name AyPsg
extends RefCounted
## The General Instrument AY-3-8910 (and Yamaha's YM2149 copy), the sound
## chip of the MSX and the ZX Spectrum 128, emulated for previews.
##
## Three square-wave tone channels and one noise generator that the mixer
## (register 7) can switch into any of them, each channel with a 4-bit
## logarithmic volume. A driver writes registers with [method write], as it
## would through the chip's address and data ports, and [method render]
## mixes the result into a mono buffer. Writes take effect at the start of
## the next rendered block, which is how a driver uses them (once per
## frame).
##
## The hardware envelope generator (registers 11 to 13) is not emulated:
## our player never uses it.

## MSX clock (half the 3.58 MHz colour clock). A tone period N makes a
## square wave of CLOCK / (16 N).
const CLOCK_MSX := 1789772.5
## ZX Spectrum 128 clock.
const CLOCK_ZX := 1773400.0
const REGISTER_COUNT := 14
const MIXER := 7
const NOISE := 6
## Output level for each volume step (0 silent, 15 full), as measured on
## the chip.
const LEVELS: PackedFloat32Array = [0.0, 0.0106, 0.0150, 0.0222, 0.0320, 0.0466, 0.0665, 0.1039, 0.1237, 0.1986, 0.2803, 0.3548, 0.4702, 0.6090, 0.7949, 1.0]

var clock := CLOCK_MSX
var mix_rate := 44100.0
## Per-part gain for previews (mutes and adaptive fades), indexed by the
## song's four channels: lead, accompaniment, bass and drums. Channel B
## takes the drums' gain while the mixer gives it noise.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])

var regs := PackedInt32Array()
var _lfsr := 1
var _noise_out := 0.0
var _noise_phase := 0.0
var _phase := PackedFloat64Array([0.0, 0.0, 0.0])
var _hp_k := 0.0
var _hp_in := 0.0
var _hp_out := 0.0
var _noise_buf := PackedFloat32Array()


func _init(rate := 44100.0, chip_clock := CLOCK_MSX) -> void:
	mix_rate = rate
	clock = chip_clock
	var rc := 1.0 / (TAU * 20.0)
	var dt := 1.0 / mix_rate
	_hp_k = rc / (rc + dt)
	reset()


## Silences every channel, as at power on.
func reset() -> void:
	regs = PackedInt32Array()
	regs.resize(REGISTER_COUNT)
	regs[MIXER] = 0xBF
	_lfsr = 1
	_noise_out = 0.0


func write(reg: int, value: int) -> void:
	if reg >= 0 and reg < REGISTER_COUNT:
		regs[reg] = value & 0xFF


func tone_period(channel: int) -> int:
	return regs[channel * 2] | ((regs[channel * 2 + 1] & 0x0F) << 8)


func volume(channel: int) -> int:
	return regs[8 + channel] & 0x0F


func tone_on(channel: int) -> bool:
	return (regs[MIXER] & (1 << channel)) == 0


func noise_on(channel: int) -> bool:
	return (regs[MIXER] & (8 << channel)) == 0


## Current loudness of a channel as 0 to 15, for meters.
func get_channel_volume(channel: int) -> int:
	if not tone_on(channel) and not noise_on(channel):
		return 0
	return volume(channel)


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	for i in count:
		out[offset + i] = 0.0
	var any_noise := false
	for c in 3:
		if noise_on(c) and volume(c) > 0:
			any_noise = true
	if any_noise:
		_make_noise(count)
	for c in 3:
		_render_channel(c, out, offset, count)
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


func _gain_of(channel: int) -> float:
	if channel == 1 and noise_on(1):
		return channel_gain[3]
	return channel_gain[[0, 1, 2][channel]]


func _render_channel(c: int, out: PackedFloat32Array, offset: int, count: int) -> void:
	var tone := tone_on(c)
	var noise := noise_on(c)
	var level: float = LEVELS[volume(c)] * _gain_of(c) * 0.3
	if level <= 0.0 or (not tone and not noise):
		return
	var period := tone_period(c)
	var inc := 0.0
	if tone:
		if period < 1:
			period = 1
		inc = clock / (16.0 * period) / mix_rate
		if inc >= 0.5:
			# Above what the output can carry: the chip's output just sits at
			# its average.
			tone = false
	var phase := _phase[c]
	if tone and not noise:
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
	elif noise and not tone:
		for i in count:
			out[offset + i] += (_noise_buf[i] * 2.0 - 1.0) * level
	else:
		# Tone and noise together: the channel is on only while both are.
		for i in count:
			phase += inc
			if phase >= 1.0:
				phase -= 1.0
			var gate := 1.0 if phase < 0.5 else 0.0
			out[offset + i] += (gate * _noise_buf[i] * 2.0 - 1.0) * level
	_phase[c] = phase


## Fills the noise buffer: a 17-bit shift register (taps on bits 0 and 3)
## stepping at CLOCK / (16 N), averaged over each sample so high rates do
## not alias.
func _make_noise(count: int) -> void:
	if _noise_buf.size() < count:
		_noise_buf.resize(count)
	var np := maxi(regs[NOISE] & 0x1F, 1)
	var inc := clock / (16.0 * np) / mix_rate
	var phase := _noise_phase
	var lfsr := _lfsr
	var held := _noise_out
	for i in count:
		phase += inc
		if phase >= 1.0:
			var sum := 0.0
			var steps := 0
			while phase >= 1.0:
				phase -= 1.0
				var bit := lfsr & 1
				lfsr = (lfsr >> 1) | ((bit ^ ((lfsr >> 3) & 1)) << 16)
				sum += float(bit)
				steps += 1
			held = sum / steps
		_noise_buf[i] = held
	_noise_phase = phase
	_lfsr = lfsr
	_noise_out = held
