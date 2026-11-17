class_name SnesDsp
extends RefCounted
## The SNES's sound chip, the S-DSP, as a sound driver sees it: eight voices
## playing BRR samples through its registers, a main volume and the echo
## unit (delay, feedback and an 8-tap filter).
##
## Voices play samples decoded ahead of time ([method set_source]), stepping
## through them at the pitch register's rate with 4-point Gaussian-style
## interpolation, and scale them by the envelope (GAIN modes: direct,
## linear up and down) and their left and right volumes. The chip runs at
## its own 32 kHz; [method render] resamples that to the output rate.
## Previews are mono, so left and right are mixed.

const DSP_HZ := 32000
const VOICES := 8
# Voice registers, at voice * 0x10 plus:
const V_VOLL := 0x00
const V_VOLR := 0x01
const V_PITCHL := 0x02
const V_PITCHH := 0x03
const V_SRCN := 0x04
const V_ADSR1 := 0x05
const V_GAIN := 0x07
# Global registers.
const MVOLL := 0x0C
const MVOLR := 0x1C
const EVOLL := 0x2C
const EVOLR := 0x3C
const KON := 0x4C
const KOFF := 0x5C
const FLG := 0x6C
const EFB := 0x0D
const EON := 0x4D
const EDL := 0x7D
const FIR := 0x0F
## FLG bit that stops the echo unit writing to its buffer.
const FLG_ECEN := 0x20

## Per-voice gain for previews (mutes and fades).
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

var _rate := 44100.0
var _regs := PackedByteArray()
# Sources: srcn -> decoded sample, padded so interpolation can read ahead.
var _src_pcm: Array = []
var _src_size := PackedInt32Array()
var _src_loop := PackedInt32Array()
# Voices.
var _pcm: Array = []
var _size := PackedInt32Array()
var _loop := PackedInt32Array()
var _pos := PackedInt32Array()
var _frac := PackedInt32Array()
var _env := PackedInt32Array()
var _on := PackedByteArray()
var _release := PackedByteArray()
var _counter := PackedInt32Array()
# Echo.
var _echo := PackedInt32Array()
var _echo_pos := 0
var _fir := PackedInt32Array()
var _fir_pos := 0
# Resampling from 32 kHz.
var _phase := 0.0
var _prev := 0.0
var _next := 0.0

## Gaussian interpolation weights: for each of 256 positions between two
## samples, four weights summing to 2048, like the DSP's table.
static var _gauss := PackedInt32Array()


func _init(rate := 44100.0) -> void:
	_rate = rate
	if _gauss.is_empty():
		_build_gauss()
	for i in 256:
		_src_pcm.append(PackedInt32Array())
	_src_size.resize(256)
	_src_loop.resize(256)
	_src_loop.fill(-1)
	reset()


static func _build_gauss() -> void:
	# A Gaussian with the console's spread: at a sample exactly, its weight
	# is about 1305/2048 and each neighbour's about 372.
	var sigma := 0.63
	_gauss.resize(256 * 4)
	for f in 256:
		var x := f / 256.0
		var w := PackedFloat32Array()
		var total := 0.0
		for k in 4:
			var d := (k - 1) - x
			var v := exp(-d * d / (2.0 * sigma * sigma))
			w.append(v)
			total += v
		var sum := 0
		for k in 4:
			var g := roundi(w[k] / total * 2048.0)
			_gauss[f * 4 + k] = g
			sum += g
		_gauss[f * 4 + 1] += 2048 - sum


func reset() -> void:
	_regs = PackedByteArray()
	_regs.resize(128)
	_regs[FLG] = 0xE0
	_pcm.clear()
	for v in VOICES:
		_pcm.append(PackedInt32Array([0, 0, 0, 0]))
	_size = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	_loop = PackedInt32Array([-1, -1, -1, -1, -1, -1, -1, -1])
	_pos = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	_frac = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	_env = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	_counter = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	_on = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
	_release = PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])
	_echo = PackedInt32Array([0])
	_echo_pos = 0
	_fir = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	_fir_pos = 0
	_phase = 0.0
	_prev = 0.0
	_next = 0.0


## Loads a sample as source [param srcn], from [method SnesSamples.decoded]
## output: {pcm, loop}.
func set_source(srcn: int, decoded: Dictionary) -> void:
	var pcm: PackedInt32Array = (decoded["pcm"] as PackedInt32Array).duplicate()
	var size := pcm.size()
	var loop := int(decoded["loop"])
	for i in 4:
		pcm.append(pcm[loop + (i % maxi(size - loop, 1))] if loop >= 0 and size > 0 else 0)
	_src_pcm[srcn] = pcm
	_src_size[srcn] = size
	_src_loop[srcn] = loop


func read(address: int) -> int:
	return _regs[address & 0x7F]


func write(address: int, value: int) -> void:
	address &= 0x7F
	value &= 0xFF
	_regs[address] = value
	if address == KON:
		for v in VOICES:
			if value & (1 << v):
				_key_on(v)
	elif address == KOFF:
		for v in VOICES:
			_release[v] = 1 if value & (1 << v) else 0
	elif address == EDL:
		var length := maxi((value & 15) * 512, 1)
		if _echo.size() != length:
			_echo = PackedInt32Array()
			_echo.resize(length)
			_echo_pos = 0


func _key_on(v: int) -> void:
	var srcn := _regs[v * 0x10 + V_SRCN]
	_pcm[v] = _src_pcm[srcn]
	_size[v] = _src_size[srcn]
	_loop[v] = _src_loop[srcn]
	_pos[v] = 0
	_frac[v] = 0
	_env[v] = 0
	_counter[v] = 0
	_release[v] = 0
	_on[v] = 1 if _size[v] > 0 else 0


## Envelope level of a voice, 0 to 2047, for meters and tests.
func get_envelope(v: int) -> int:
	return _env[v] if _on[v] else 0


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	var step := DSP_HZ / _rate
	for i in count:
		_phase += step
		while _phase >= 1.0:
			_phase -= 1.0
			_prev = _next
			_next = _sample()
		out[offset + i] = _prev + (_next - _prev) * _phase


## One 32 kHz output sample, mono, -1 to 1.
func _sample() -> float:
	var main := 0
	var echo_in := 0
	var eon := _regs[EON]
	for v in VOICES:
		if not _on[v]:
			continue
		var base := v * 0x10
		# Envelope.
		var env := _env[v]
		if _release[v]:
			env -= 8
		else:
			var gain := _regs[base + V_GAIN]
			if gain < 0x80:
				env = (gain & 0x7F) << 4
			else:
				_counter[v] += 1
				if _counter[v] >= 4:
					_counter[v] = 0
					if (gain & 0xE0) == 0x80:
						env -= 32
					elif (gain & 0xE0) == 0xC0:
						env += 32
		env = clampi(env, 0, 0x7FF)
		_env[v] = env
		if _release[v] and env == 0:
			_on[v] = 0
			continue
		# Interpolated sample.
		var pcm: PackedInt32Array = _pcm[v]
		var p := _pos[v]
		var g := (_frac[v] >> 4) * 4
		var s := (_gauss[g] * pcm[p]) >> 11
		s += (_gauss[g + 1] * pcm[p + 1]) >> 11
		s += (_gauss[g + 2] * pcm[p + 2]) >> 11
		s += (_gauss[g + 3] * pcm[p + 3]) >> 11
		s = clampi(s, -32768, 32767) >> 1
		var level := (s * env) >> 11
		var vl := _regs[base + V_VOLL]
		var vr := _regs[base + V_VOLR]
		if vl >= 128:
			vl -= 256
		if vr >= 128:
			vr -= 256
		var mono := int(((level * vl >> 7) + (level * vr >> 7)) * 0.5 * channel_gain[v])
		main += mono
		if eon & (1 << v):
			echo_in += mono
		# Step through the sample.
		var pitch := (_regs[base + V_PITCHL] | (_regs[base + V_PITCHH] << 8)) & 0x3FFF
		var frac := _frac[v] + pitch
		p += frac >> 12
		_frac[v] = frac & 0xFFF
		if p >= _size[v]:
			if _loop[v] >= 0:
				var span := _size[v] - _loop[v]
				p = _loop[v] + (p - _size[v]) % maxi(span, 1)
			else:
				_on[v] = 0
		_pos[v] = p
	var mvol := _regs[MVOLL]
	if mvol >= 128:
		mvol -= 256
	var total := (main * mvol) >> 7
	# Echo: read the delayed sample, filter it, mix it in, feed it back.
	var delayed := _echo[_echo_pos]
	_fir[_fir_pos] = delayed
	var filtered := 0
	for k in 8:
		var c := _regs[FIR + k * 0x10]
		if c >= 128:
			c -= 256
		filtered += (_fir[(_fir_pos + 1 + k) & 7] * c) >> 6
	_fir_pos = (_fir_pos + 1) & 7
	filtered = clampi(filtered, -32768, 32767)
	var evol := _regs[EVOLL]
	if evol >= 128:
		evol -= 256
	total += (filtered * evol) >> 7
	if not (_regs[FLG] & FLG_ECEN):
		var efb := _regs[EFB]
		if efb >= 128:
			efb -= 256
		_echo[_echo_pos] = clampi(echo_in + ((filtered * efb) >> 7), -32768, 32767) & ~1
	_echo_pos = (_echo_pos + 1) % _echo.size()
	return clampi(total, -32768, 32767) / 32768.0
