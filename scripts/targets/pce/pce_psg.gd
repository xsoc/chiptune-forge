class_name PcePsg
extends RefCounted
## The PC Engine's sound generator (in the HuC6280 CPU): six channels that
## each play a 32-step, 5-bit waveform, channels 5 and 6 can play noise
## instead, with a 5-bit volume and 4-bit left and right balance per
## channel and a main balance, in 1.5 dB steps.
##
## Registers are written as the CPU does, at $0800 to $0809 (here 0 to 9):
## 0 selects the channel the next writes go to, 1 is the main balance, 2 and
## 3 the 12-bit frequency divider, 4 the channel's on, DDA and volume bits,
## 5 its balance, 6 its waveform data and 7 its noise control. The LFO (8
## and 9) and DDA playback are not emulated: our player does not use them.
## Mixes to mono.

const CLOCK := 3579545.0
const CHANNELS := 6
const SELECT := 0
const MAIN_BALANCE := 1
const FREQ_LO := 2
const FREQ_HI := 3
const CONTROL := 4
const BALANCE := 5
const WAVE := 6
const NOISE := 7
## Control register bits.
const ON := 0x80
const DDA := 0x40
## Output level of a full-scale sample from one channel at full volume.
const CHANNEL_LEVEL := 0.18
## Balance nibbles as volume steps (Mednafen's scale table).
const SCALE := [0x00, 0x03, 0x05, 0x07, 0x09, 0x0B, 0x0D, 0x0F, 0x11, 0x13, 0x15, 0x17, 0x19, 0x1B, 0x1D, 0x1F]

var rate := 44100.0
## Per-channel gain for previews.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

var _select := 0
var _main_balance := 0
var _period := PackedInt32Array()
var _control := PackedInt32Array()
var _balance := PackedInt32Array()
var _noise := PackedInt32Array()
var _waves: Array[PackedInt32Array] = []
var _write_index := PackedInt32Array()
var _phase := PackedFloat64Array()
var _noise_phase := PackedFloat64Array()
var _lfsr := PackedInt32Array()
var _noise_out := PackedInt32Array()
## Volume for each attenuation step, 1.5 dB apart; step 31 is silent.
var _db := PackedFloat32Array()
var _lowpass := 0.0
var _lowpass_k := 0.0


func _init(mix_rate := 44100.0) -> void:
	rate = mix_rate
	for i in 32:
		_db.append(0.0 if i == 31 else pow(10.0, -1.5 * i / 20.0))
	# A gentle low-pass, like the console's output stage, which also tames
	# the aliasing of high notes.
	_lowpass_k = 1.0 - exp(-TAU * 12000.0 / rate)
	reset()


func reset() -> void:
	_select = 0
	_main_balance = 0
	_period = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_control = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_balance = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_noise = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_write_index = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_phase = PackedFloat64Array([0, 0, 0, 0, 0, 0])
	_noise_phase = PackedFloat64Array([0, 0, 0, 0, 0, 0])
	_lfsr = PackedInt32Array([1, 1, 1, 1, 1, 1])
	_noise_out = PackedInt32Array([0, 0, 0, 0, 0, 0])
	_waves.clear()
	for c in CHANNELS:
		var wave := PackedInt32Array()
		wave.resize(32)
		_waves.append(wave)
	_lowpass = 0.0


func write(reg: int, value: int) -> void:
	value &= 0xFF
	var c := _select
	match reg:
		SELECT:
			_select = value & 7
		MAIN_BALANCE:
			_main_balance = value
		FREQ_LO:
			if c < CHANNELS:
				_period[c] = (_period[c] & 0xF00) | value
		FREQ_HI:
			if c < CHANNELS:
				_period[c] = (_period[c] & 0xFF) | ((value & 15) << 8)
		CONTROL:
			if c < CHANNELS:
				# DDA on with the channel off resets the waveform write index.
				if (value & (ON | DDA)) == DDA:
					_write_index[c] = 0
				_control[c] = value
		BALANCE:
			if c < CHANNELS:
				_balance[c] = value
		WAVE:
			if c < CHANNELS and not (_control[c] & ON):
				_waves[c][_write_index[c]] = value & 0x1F
				_write_index[c] = (_write_index[c] + 1) & 31
		NOISE:
			if c >= 4 and c < CHANNELS:
				_noise[c] = value


## What the PSG holds, for tests: {period, control, balance, noise, wave}
## for [param channel].
func channel_state(channel: int) -> Dictionary:
	return {"period": _period[channel], "control": _control[channel], "balance": _balance[channel], "noise": _noise[channel], "wave": _waves[channel].duplicate()}


## The volume of a channel after its volume and both balances, 0 to 1 per
## side. Returns Vector2(left, right).
func channel_volume(channel: int) -> Vector2:
	var vol := _control[channel] & 0x1F
	var left: int = (0x1F - SCALE[(_balance[channel] >> 4) & 15]) + (0x1F - vol) + (0x1F - SCALE[(_main_balance >> 4) & 15])
	var right: int = (0x1F - SCALE[_balance[channel] & 15]) + (0x1F - vol) + (0x1F - SCALE[_main_balance & 15])
	return Vector2(_db[mini(left, 31)], _db[mini(right, 31)])


## Writes [param count] samples into [param out] from [param offset]
## (assigning, not adding).
func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	var cycles := CLOCK / rate
	var levels := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var active := PackedByteArray([0, 0, 0, 0, 0, 0])
	var steps := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var noise_steps := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	for c in CHANNELS:
		var control := _control[c]
		if not (control & ON) or (control & DDA):
			continue
		var vol := channel_volume(c)
		levels[c] = (vol.x + vol.y) * 0.5 * CHANNEL_LEVEL / 16.0 * channel_gain[c]
		if levels[c] <= 0.0:
			continue
		active[c] = 1
		var period := _period[c] if _period[c] > 0 else 4096
		steps[c] = cycles / period
		if _noise[c] & 0x80:
			var n := (_noise[c] & 0x1F) ^ 0x1F
			noise_steps[c] = cycles / (n * 64 if n > 0 else 32)
	for i in count:
		var mix := 0.0
		for c in CHANNELS:
			if not active[c]:
				continue
			var sample: int
			if noise_steps[c] > 0.0:
				_noise_phase[c] += noise_steps[c]
				while _noise_phase[c] >= 1.0:
					_noise_phase[c] -= 1.0
					var l := _lfsr[c]
					var bit := (l ^ (l >> 1) ^ (l >> 11) ^ (l >> 12) ^ (l >> 17)) & 1
					_lfsr[c] = (l >> 1) | (bit << 17)
					_noise_out[c] = 0x1F if (_lfsr[c] & 1) else 0
				sample = _noise_out[c]
			else:
				_phase[c] += steps[c]
				if _phase[c] >= 32.0:
					_phase[c] = fmod(_phase[c], 32.0)
				sample = _waves[c][int(_phase[c])]
			mix += (sample - 16) * levels[c]
		_lowpass += (mix - _lowpass) * _lowpass_k
		out[offset + i] = _lowpass
