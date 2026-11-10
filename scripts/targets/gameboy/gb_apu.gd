class_name GbApu
extends RefCounted
## The Game Boy's sound hardware, emulated for previews.
##
## Two pulse channels (the first with a frequency sweep), the wave channel
## and the noise channel, with their length counters, volume envelopes,
## stereo switches, master volume and the output high-pass filter. A sound
## driver writes registers with [method write], exactly as it would on the
## console, and [method render] mixes the result into stereo buffers.
##
## Accuracy is at the register level, not the cycle level: register writes
## take effect at the start of the next rendered block, which is how the
## driver uses them (once per tick).

const CPU_HZ := 4194304.0

const NR10 := 0xFF10
const NR11 := 0xFF11
const NR12 := 0xFF12
const NR13 := 0xFF13
const NR14 := 0xFF14
const NR21 := 0xFF16
const NR22 := 0xFF17
const NR23 := 0xFF18
const NR24 := 0xFF19
const NR30 := 0xFF1A
const NR31 := 0xFF1B
const NR32 := 0xFF1C
const NR33 := 0xFF1D
const NR34 := 0xFF1E
const NR41 := 0xFF20
const NR42 := 0xFF21
const NR43 := 0xFF22
const NR44 := 0xFF23
const NR50 := 0xFF24
const NR51 := 0xFF25
const NR52 := 0xFF26
const WAVE_RAM := 0xFF30

const DUTY := [0.125, 0.25, 0.5, 0.75]

var mix_rate := 44100.0
## Per-channel gain for previews (mutes and adaptive fades). 1 is as the
## hardware plays it.
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])

var _regs := PackedByteArray()
var _ch: Array[_Channel] = []

# Channel 1 sweep.
var _sweep_on := false
var _sweep_shadow := 0
var _sweep_timer := 0

# Channel 3: the 32 samples as analog levels for the current volume code.
var _wave_levels := PackedFloat32Array()
var _wave_dirty := true

# Channel 4.
var _lfsr := 0x7FFF
var _noise_out := 0.0

# Frame sequencer (512 Hz) and the output filter.
var _fs_step := 0
var _fs_left := 0.0
var _fs_frames := 0.0
var _hpf_charge := 0.996
var _cap_l := 0.0
var _cap_r := 0.0


func _init(rate := 44100.0) -> void:
	mix_rate = rate
	_fs_frames = mix_rate / 512.0
	_fs_left = _fs_frames
	# The console's output capacitor, charged once per output sample.
	_hpf_charge = pow(0.999958, CPU_HZ / mix_rate)
	reset()


## Powers the APU on with everything silent, as after NR52 = 0x80.
func reset() -> void:
	_regs.resize(0x30)
	_regs.fill(0)
	_ch.clear()
	for i in 4:
		_ch.append(_Channel.new())
	_regs[NR52 - NR10] = 0x80
	_wave_levels.resize(32)
	_wave_dirty = true
	_lfsr = 0x7FFF
	_noise_out = 0.0
	_sweep_on = false
	_cap_l = 0.0
	_cap_r = 0.0


func read(address: int) -> int:
	if address < NR10 or address > 0xFF3F:
		return 0xFF
	return _regs[address - NR10]


## Writes a sound register, with the side effects the hardware has: a write
## with bit 7 set to NRx4 triggers the channel, NRx2 controls its DAC, and so
## on.
func write(address: int, value: int) -> void:
	if address < NR10 or address > 0xFF3F:
		return
	value &= 0xFF
	_regs[address - NR10] = value
	if address >= WAVE_RAM:
		_wave_dirty = true
		return
	match address:
		NR11, NR21, NR41:
			var ch := _ch[_index_of(address)]
			ch.duty = value >> 6
			ch.length = 64 - (value & 0x3F)
		NR31:
			_ch[2].length = 256 - value
		NR12, NR22, NR42:
			var ch := _ch[_index_of(address)]
			ch.dac = (value & 0xF8) != 0
			if not ch.dac:
				ch.on = false
		NR30:
			_ch[2].dac = (value & 0x80) != 0
			if not _ch[2].dac:
				_ch[2].on = false
		NR32:
			_wave_dirty = true
		NR13, NR23, NR33:
			var ch := _ch[_index_of(address)]
			ch.period = (ch.period & 0x700) | value
		NR14, NR24, NR34, NR44:
			var index := _index_of(address)
			var ch := _ch[index]
			if index < 3:
				ch.period = (ch.period & 0xFF) | ((value & 7) << 8)
			ch.length_on = (value & 0x40) != 0
			if value & 0x80:
				_trigger(index)


func is_channel_on(index: int) -> bool:
	return _ch[index].on


## Current 4-bit volume of a channel (0 when it is off), for meters.
func get_channel_volume(index: int) -> int:
	var ch := _ch[index]
	if not ch.on:
		return 0
	if index == 2:
		var code := (_regs[NR32 - NR10] >> 5) & 3
		return [0, 15, 8, 4][code]
	return ch.volume


## Mixes [param count] frames into the buffers from [param offset] on.
func render(left: PackedFloat32Array, right: PackedFloat32Array, offset: int, count: int) -> void:
	var pos := offset
	var end := offset + count
	while pos < end:
		var n := mini(end - pos, maxi(int(ceilf(_fs_left)), 1))
		_render_block(left, right, pos, n)
		pos += n
		_fs_left -= n
		if _fs_left <= 0.0:
			_fs_left += _fs_frames
			_frame_sequencer()


func _index_of(address: int) -> int:
	if address <= NR14:
		return 0
	if address <= NR24:
		return 1
	if address <= NR34:
		return 2
	return 3


func _trigger(index: int) -> void:
	var ch := _ch[index]
	ch.on = ch.dac
	if ch.length == 0:
		ch.length = 256 if index == 2 else 64
	if index == 2:
		ch.phase = 0.0
		return
	var env := _regs[[NR12, NR22, 0, NR42][index] - NR10]
	ch.volume = env >> 4
	ch.env_up = (env & 0x08) != 0
	ch.env_pace = env & 7
	ch.env_timer = ch.env_pace
	if index == 3:
		_lfsr = 0x7FFF
	if index == 0:
		var sweep := _regs[NR10 - NR10]
		var pace := (sweep >> 4) & 7
		var shift := sweep & 7
		_sweep_shadow = ch.period
		_sweep_timer = pace if pace > 0 else 8
		_sweep_on = pace > 0 or shift > 0
		if shift > 0 and _sweep_next() > 2047:
			ch.on = false


func _sweep_next() -> int:
	var sweep := _regs[NR10 - NR10]
	var delta := _sweep_shadow >> (sweep & 7)
	return _sweep_shadow - delta if sweep & 0x08 else _sweep_shadow + delta


func _frame_sequencer() -> void:
	var step := _fs_step
	_fs_step = (_fs_step + 1) & 7
	if step % 2 == 0:
		for ch in _ch:
			if ch.length_on and ch.length > 0:
				ch.length -= 1
				if ch.length == 0:
					ch.on = false
	if step == 2 or step == 6:
		_clock_sweep()
	if step == 7:
		for i in [0, 1, 3]:
			var ch := _ch[i]
			if ch.env_pace == 0:
				continue
			ch.env_timer -= 1
			if ch.env_timer <= 0:
				ch.env_timer = ch.env_pace
				if ch.env_up and ch.volume < 15:
					ch.volume += 1
				elif not ch.env_up and ch.volume > 0:
					ch.volume -= 1


func _clock_sweep() -> void:
	_sweep_timer -= 1
	if _sweep_timer > 0:
		return
	var sweep := _regs[NR10 - NR10]
	var pace := (sweep >> 4) & 7
	_sweep_timer = pace if pace > 0 else 8
	if not _sweep_on or pace == 0:
		return
	var next := _sweep_next()
	if next > 2047:
		_ch[0].on = false
		return
	if sweep & 7:
		_sweep_shadow = next
		_ch[0].period = next
		_regs[NR13 - NR10] = next & 0xFF
		_regs[NR14 - NR10] = (_regs[NR14 - NR10] & 0xF8) | (next >> 8)
		if _sweep_next() > 2047:
			_ch[0].on = false


func _render_block(left: PackedFloat32Array, right: PackedFloat32Array, start: int, count: int) -> void:
	var nr50 := _regs[NR50 - NR10]
	var nr51 := _regs[NR51 - NR10]
	var vol_l := (((nr50 >> 4) & 7) + 1) / 8.0 * 0.25
	var vol_r := ((nr50 & 7) + 1) / 8.0 * 0.25
	var end := start + count
	for index in 4:
		var ch := _ch[index]
		if not ch.dac:
			continue
		var g := channel_gain[index]
		var gl := g * vol_l * float((nr51 >> (index + 4)) & 1)
		var gr := g * vol_r * float((nr51 >> index) & 1)
		if gl == 0.0 and gr == 0.0:
			continue
		if not ch.on:
			# An enabled DAC with a silent channel still outputs its "zero"
			# level, which the high-pass filter removes.
			for pos in range(start, end):
				left[pos] -= gl
				right[pos] -= gr
			continue
		match index:
			0, 1:
				_render_pulse(ch, left, right, start, end, gl, gr)
			2:
				_render_wave(ch, left, right, start, end, gl, gr)
			3:
				_render_noise(ch, left, right, start, end, gl, gr)
	# Output high-pass filter (the console's coupling capacitor).
	var charge := _hpf_charge
	var cap_l := _cap_l
	var cap_r := _cap_r
	for pos in range(start, end):
		var in_l := left[pos]
		var out_l := in_l - cap_l
		cap_l = in_l - out_l * charge
		left[pos] = out_l
		var in_r := right[pos]
		var out_r := in_r - cap_r
		cap_r = in_r - out_r * charge
		right[pos] = out_r
	_cap_l = cap_l
	_cap_r = cap_r


func _render_pulse(ch: _Channel, left: PackedFloat32Array, right: PackedFloat32Array, start: int, end: int, gl: float, gr: float) -> void:
	var freq := 131072.0 / (2048 - ch.period)
	var inc := minf(freq / mix_rate, 0.5)
	var duty: float = DUTY[ch.duty]
	var amp := ch.volume / 7.5
	var phase := ch.phase
	for pos in range(start, end):
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		var sq := 1.0 if phase < duty else 0.0
		sq += 0.5 * _blep(phase, inc)
		var t2 := phase - duty
		if t2 < 0.0:
			t2 += 1.0
		sq -= 0.5 * _blep(t2, inc)
		var s := amp * sq - 1.0
		left[pos] += s * gl
		right[pos] += s * gr
	ch.phase = phase


func _render_wave(ch: _Channel, left: PackedFloat32Array, right: PackedFloat32Array, start: int, end: int, gl: float, gr: float) -> void:
	if _wave_dirty:
		_rebuild_wave()
	var freq := 65536.0 / (2048 - ch.period)
	var inc := freq / mix_rate
	var levels := _wave_levels
	var phase := ch.phase
	for pos in range(start, end):
		phase += inc
		while phase >= 1.0:
			phase -= 1.0
		var s := levels[int(phase * 32.0) & 31]
		left[pos] += s * gl
		right[pos] += s * gr
	ch.phase = phase


func _rebuild_wave() -> void:
	var code := (_regs[NR32 - NR10] >> 5) & 3
	var shift: int = [4, 0, 1, 2][code]
	for i in 32:
		var byte := _regs[WAVE_RAM - NR10 + (i >> 1)]
		var nibble := (byte >> 4) if i % 2 == 0 else (byte & 0x0F)
		_wave_levels[i] = (nibble >> shift) / 7.5 - 1.0
	_wave_dirty = false


func _render_noise(ch: _Channel, left: PackedFloat32Array, right: PackedFloat32Array, start: int, end: int, gl: float, gr: float) -> void:
	var poly := _regs[NR43 - NR10]
	var shift := poly >> 4
	var divisor := poly & 7
	var clock := 0.0
	if shift < 14:
		clock = 262144.0 / (0.5 if divisor == 0 else float(divisor)) / float(1 << shift)
	var inc := clock / mix_rate
	var narrow := (poly & 0x08) != 0
	var amp := ch.volume / 7.5
	var lfsr := _lfsr
	var out := _noise_out
	var phase := ch.phase
	for pos in range(start, end):
		phase += inc
		if phase >= 1.0:
			# Average every LFSR step within this sample: a box filter that
			# keeps high noise rates from aliasing.
			var sum := 0.0
			var steps := 0
			while phase >= 1.0:
				phase -= 1.0
				var bit := (lfsr ^ (lfsr >> 1)) & 1
				lfsr = (lfsr >> 1) | (bit << 14)
				if narrow:
					lfsr = (lfsr & ~0x40) | (bit << 6)
				sum += float(~lfsr & 1)
				steps += 1
			out = sum / steps
		var s := amp * out - 1.0
		left[pos] += s * gl
		right[pos] += s * gr
	_lfsr = lfsr
	_noise_out = out
	ch.phase = phase


static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0


class _Channel:
	extends RefCounted

	var on := false
	var dac := false
	var length := 0
	var length_on := false
	var period := 0
	var duty := 2
	var volume := 0
	var env_up := false
	var env_pace := 0
	var env_timer := 0
	var phase := 0.0
