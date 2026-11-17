class_name Opl
extends RefCounted
## Yamaha's FM chips from PC sound cards, emulated for previews: the YM3812
## (OPL2) of the AdLib and Sound Blaster, and the YMF262 (OPL3) of the
## Sound Blaster 16.
##
## Nine two-operator channels (eighteen on the OPL3, in two register
## banks), with feedback, both connections, multipliers, key scaling of
## rate and level, total level, the attack, decay, sustain and release
## envelope with its sustain switch, the four waveforms (eight on the
## OPL3), tremolo and vibrato, and the rhythm mode's five drums. A driver
## writes registers with [method write], exactly as through ports $388 and
## $389 (and $38A and $38B for the OPL3's second bank), and
## [method render] adds the result to a left and a right buffer.
##
## It follows the chip's arithmetic where that is audible: the phase
## increment from F-number, block and multiplier, the envelope's timing
## table, 0.75 dB total-level steps and 3 dB sustain steps, how far one
## operator moves another's phase, and the rhythm mode's phase tricks and
## noise. To keep previews fast in GDScript the envelope and LFOs are worked
## out every 32 samples and eased in between, and the waves come from
## tables. Not emulated: the OPL3's four-operator modes, the timers and CSM
## mode.

## The chips run from a 14.318 MHz crystal divided by four (3.58 MHz) and
## make one sample every 72 clocks.
const CLOCK := 3579545.0
const CHIP_RATE := CLOCK / 72.0
## Envelope attenuation in 0.1875 dB steps: 0 is full volume, 511 silent.
const EG_MAX := 511.0
const SUB_BLOCK := 32
const WAVE_LEN := 1024
## A full-scale operator moves the next one's phase by four cycles.
const MOD_CYCLES := 4.0
## Output of one channel at full scale, in the preview mix.
const CHANNEL_LEVEL := 0.16
## Multiplier register values, as multiples of the note's frequency.
const MULT := [0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15]
## Key scale level: attenuation in dB at block 7 for each F-number top
## nibble. It falls 6 dB per block below that.
const KSL_ROM := [0.0, 9.0, 12.0, 13.875, 15.0, 16.125, 16.875, 17.625, 18.0, 18.75, 19.125, 19.5, 19.875, 20.25, 20.625, 21.0]
## KSL register value to the fraction of [constant KSL_ROM] it applies:
## off, 3, 1.5 and 6 dB per octave.
const KSL_SHIFT := [0.0, 0.5, 0.25, 1.0]
## The register offset of each operator, in channel order: modulator at
## [code]OP_OFFSET[ch][/code], carrier three above.
const OP_OFFSET := [0, 1, 2, 8, 9, 10, 16, 17, 18]
## Register offset to operator slot (0 to 17), or -1.
const SLOT_OF := [0, 1, 2, 3, 4, 5, -1, -1, 6, 7, 8, 9, 10, 11, -1, -1, 12, 13, 14, 15, 16, 17, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1]
## Times in milliseconds for an attack from silence and a decay from full
## to silence at effective rate 4, from Yamaha's data sheet. Each step of
## the effective rate (0 to 63) makes them 2^(1/4) shorter.
const ATTACK_MS := 2826.24
const DECAY_MS := 39280.64

enum { ATTACK, DECAY, SUSTAIN, RELEASE, OFF }

static var WAVES := _make_waves()

var mix_rate := 44100.0
## True for the OPL3: two banks, eight waveforms and stereo.
var opl3 := false
## Per-channel gain for previews (mutes and fades), 18 channels.
var channel_gain := PackedFloat32Array()

var _regs := PackedByteArray()
# Per channel (18).
var _fnum := PackedInt32Array()
var _block := PackedInt32Array()
var _keyon := PackedByteArray()
var _fb := PackedInt32Array()
var _cnt := PackedInt32Array()
var _pan_l := PackedFloat32Array()
var _pan_r := PackedFloat32Array()
var _fb1 := PackedFloat32Array()
var _fb2 := PackedFloat32Array()
# Per operator (36): two per channel, modulator then carrier.
var _am := PackedByteArray()
var _vib := PackedByteArray()
var _egt := PackedByteArray()
var _ksr := PackedByteArray()
var _mult := PackedInt32Array()
var _ksl := PackedInt32Array()
var _tl := PackedInt32Array()
var _ar := PackedInt32Array()
var _dr := PackedInt32Array()
var _sl := PackedInt32Array()
var _rr := PackedInt32Array()
var _ws := PackedInt32Array()
var _key := PackedByteArray()
var _state := PackedInt32Array()
var _att := PackedFloat32Array()
var _phase := PackedFloat64Array()
var _inc := PackedFloat64Array()
# Globals.
var _wse := false
var _new := false
var _nts := 0
var _am_deep := false
var _vib_deep := false
var _rhythm := false
var _drum_keys := 0
var _lfo_time := 0.0
var _noise := 1


func _init(rate := 44100.0, is_opl3 := false) -> void:
	mix_rate = rate
	opl3 = is_opl3
	channel_gain.resize(18)
	channel_gain.fill(1.0)
	reset()


static func _make_waves() -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for w in 8:
		var table := PackedFloat32Array()
		table.resize(WAVE_LEN)
		for i in WAVE_LEN:
			var x := (i + 0.5) / WAVE_LEN
			var s := sin(TAU * x)
			var v := 0.0
			match w:
				0:
					v = s
				1:
					v = maxf(s, 0.0)
				2:
					v = absf(s)
				3:
					# Rising quarters of a sine, twice per cycle.
					v = absf(s) if fmod(x, 0.5) < 0.25 else 0.0
				4:
					v = sin(TAU * 2.0 * x) if x < 0.5 else 0.0
				5:
					v = absf(sin(TAU * 2.0 * x)) if x < 0.5 else 0.0
				6:
					v = 1.0 if x < 0.5 else -1.0
				7:
					# The "derived square": an exponential ramp each half.
					var y := fmod(x, 0.5) * 2.0
					v = pow(2.0, -y * 12.0) * (1.0 if x < 0.5 else -1.0)
			table[i] = v
		out.append(table)
	return out


## Every channel silent and every register cleared, as at power on.
func reset() -> void:
	_regs.resize(512)
	_regs.fill(0)
	for arr in [_fnum, _block, _fb, _cnt]:
		arr.resize(18)
		arr.fill(0)
	_keyon.resize(18)
	_keyon.fill(0)
	for arr in [_fb1, _fb2]:
		arr.resize(18)
		arr.fill(0.0)
	for arr in [_pan_l, _pan_r]:
		arr.resize(18)
		arr.fill(1.0)
	for arr in [_am, _vib, _egt, _ksr, _key]:
		arr.resize(36)
		arr.fill(0)
	for arr in [_mult, _ksl, _tl, _ar, _dr, _sl, _rr, _ws, _state]:
		arr.resize(36)
		arr.fill(0)
	_state.fill(OFF)
	_att.resize(36)
	_att.fill(EG_MAX)
	_phase.resize(36)
	_phase.fill(0.0)
	_inc.resize(36)
	_inc.fill(0.0)
	_wse = false
	_new = false
	_nts = 0
	_am_deep = false
	_vib_deep = false
	_rhythm = false
	_drum_keys = 0
	_noise = 1


## Writes [param value] to register [param reg] of bank [param bank] (0, or
## 1 for the OPL3's registers $100 to $1FF).
func write(bank: int, reg: int, value: int) -> void:
	reg &= 0xFF
	value &= 0xFF
	bank = bank & 1 if opl3 else 0
	_regs[bank * 256 + reg] = value
	if bank == 1 and reg == 0x05:
		_new = value & 1 != 0
		_update_pans()
		return
	if bank == 0:
		match reg:
			0x01:
				_wse = value & 0x20 != 0
				return
			0x08:
				_nts = (value >> 6) & 1
				return
			0xBD:
				_am_deep = value & 0x80 != 0
				_vib_deep = value & 0x40 != 0
				_set_rhythm(value & 0x20 != 0, value & 0x1F)
				return
	if reg >= 0x20 and reg < 0xA0:
		var slot: int = SLOT_OF[reg & 0x1F]
		if slot < 0:
			return
		var ch: int = slot % 3 + (slot / 6) * 3
		var op := ch * 2 + (slot / 3) % 2 + bank * 18
		match reg & 0xE0:
			0x20:
				_am[op] = (value >> 7) & 1
				_vib[op] = (value >> 6) & 1
				_egt[op] = (value >> 5) & 1
				_ksr[op] = (value >> 4) & 1
				_mult[op] = value & 15
				_update_channel(op / 2)
			0x40:
				_ksl[op] = value >> 6
				_tl[op] = value & 0x3F
			0x60:
				_ar[op] = value >> 4
				_dr[op] = value & 15
			0x80:
				var level := value >> 4
				_sl[op] = 496 if level == 15 else level * 16
				_rr[op] = value & 15
		return
	if reg >= 0xE0 and reg <= 0xF5:
		var slot: int = SLOT_OF[reg - 0xE0]
		if slot < 0:
			return
		var ch: int = slot % 3 + (slot / 6) * 3
		_ws[ch * 2 + (slot / 3) % 2 + bank * 18] = value & 7
		return
	var c := reg & 0x0F
	if c > 8:
		return
	var channel := c + bank * 9
	match reg & 0xF0:
		0xA0:
			_fnum[channel] = (_fnum[channel] & 0x300) | value
			_update_channel(channel)
		0xB0:
			_fnum[channel] = (_fnum[channel] & 0xFF) | ((value & 3) << 8)
			_block[channel] = (value >> 2) & 7
			_update_channel(channel)
			var on := (value >> 5) & 1
			if on != _keyon[channel]:
				_keyon[channel] = on
				if not (_rhythm and bank == 0 and channel >= 6):
					_key_op(channel * 2, on)
					_key_op(channel * 2 + 1, on)
		0xC0:
			_fb[channel] = (value >> 1) & 7
			_cnt[channel] = value & 1
			_update_pans()


func _update_pans() -> void:
	for ch in 18:
		if opl3 and _new:
			var c := _regs[(ch / 9) * 256 + 0xC0 + ch % 9]
			_pan_l[ch] = 1.0 if c & 0x10 else 0.0
			_pan_r[ch] = 1.0 if c & 0x20 else 0.0
		else:
			_pan_l[ch] = 1.0
			_pan_r[ch] = 1.0


func _set_rhythm(on: bool, keys: int) -> void:
	_rhythm = on
	if not on:
		keys = 0
	# BD keys both of channel 6's operators; HH, SD, TOM and CYM one each.
	var ops := [[4, [12, 13]], [3, [15]], [2, [16]], [1, [17]], [0, [14]]]
	for entry in ops:
		var bit := 1 << int(entry[0])
		var was := _drum_keys & bit
		var now := keys & bit
		if was != now:
			for op in entry[1]:
				_key_op(int(op), 1 if now else 0)
	_drum_keys = keys


func _key_op(op: int, on: int) -> void:
	if on and not _key[op]:
		_phase[op] = 0.0
		_state[op] = ATTACK
		if _rate(op, _ar[op]) >= 60:
			_att[op] = 0.0
			_state[op] = DECAY
	elif not on and _key[op]:
		_state[op] = RELEASE
	_key[op] = on


## Key code: block and one F-number bit (bit 9, or bit 8 with NTS set).
func _keycode(channel: int) -> int:
	return (_block[channel] << 1) | ((_fnum[channel] >> (9 - _nts)) & 1)


## Effective envelope rate (0 to 63) for a 4-bit register rate.
func _rate(op: int, value: int) -> int:
	if value <= 0:
		return 0
	var kc := _keycode(op / 2)
	return mini(value * 4 + (kc if _ksr[op] else kc >> 2), 63)


func _update_channel(channel: int) -> void:
	var hz := _fnum[channel] * CHIP_RATE / pow(2.0, 20 - _block[channel])
	for k in 2:
		var op := channel * 2 + k
		_inc[op] = hz * float(MULT[_mult[op]]) / mix_rate * WAVE_LEN


## Envelope steps per second at an effective rate, for a decay or release.
static func decay_speed(rate: int) -> float:
	if rate < 4:
		return 0.0
	var ms := DECAY_MS / pow(2.0, (mini(rate, 60) - 4) / 4.0)
	return 512.0 / (ms / 1000.0)


## Seconds an attack takes from silence to full at an effective rate.
static func attack_seconds(rate: int) -> float:
	if rate < 4:
		return INF
	if rate >= 60:
		return 0.0
	return ATTACK_MS / pow(2.0, (rate - 4) / 4.0) / 1000.0


func _advance(op: int, seconds: float) -> void:
	match _state[op]:
		ATTACK:
			var t := attack_seconds(_rate(op, _ar[op]))
			if t <= 0.0:
				_att[op] = 0.0
			elif t < INF:
				# An exponential approach that reaches full volume in time t.
				var keep := pow(1.0 / 33.0, seconds / t)
				_att[op] = (_att[op] + 16.0) * keep - 16.0
			if _att[op] <= 0.0:
				_att[op] = 0.0
				_state[op] = DECAY
		DECAY:
			_att[op] += decay_speed(_rate(op, _dr[op])) * seconds
			if _att[op] >= _sl[op]:
				_att[op] = float(_sl[op])
				_state[op] = SUSTAIN
		SUSTAIN:
			# Without the sustain switch the sound fades at the release rate.
			if not _egt[op]:
				_att[op] += decay_speed(_rate(op, _rr[op])) * seconds
				if _att[op] >= EG_MAX:
					_att[op] = EG_MAX
					_state[op] = OFF
		RELEASE:
			_att[op] += decay_speed(_rate(op, _rr[op])) * seconds
			if _att[op] >= EG_MAX:
				_att[op] = EG_MAX
				_state[op] = OFF


## Linear gain of an operator now: envelope, total level, key scaling and
## tremolo.
func _gain(op: int, tremolo: float) -> float:
	if _state[op] == OFF:
		return 0.0
	var channel := op / 2
	var ksl_db: float = maxf(KSL_ROM[_fnum[channel] >> 6] - 6.0 * (7 - _block[channel]), 0.0) * KSL_SHIFT[_ksl[op]]
	var att := _att[op] + _tl[op] * 4.0 + ksl_db / 0.1875
	if _am[op]:
		att += tremolo
	if att >= EG_MAX:
		return 0.0
	return pow(2.0, -att * 0.1875 / 6.0206)


func _wave(op: int) -> int:
	if opl3 and _new:
		return _ws[op]
	return _ws[op] & 3 if (_wse or opl3) else 0


func is_channel_silent(channel: int) -> bool:
	for k in 2:
		if _state[channel * 2 + k] != OFF:
			return false
	return true


## Current loudness of a channel, 0 to 1, for meters.
func get_channel_level(channel: int) -> float:
	return _gain(channel * 2 + 1, 0.0)


## Adds [param count] samples to [param left] and [param right].
func render(left: PackedFloat32Array, right: PackedFloat32Array, offset: int, count: int) -> void:
	var done := 0
	var channels := 18 if opl3 else 9
	while done < count:
		var n := mini(SUB_BLOCK, count - done)
		var seconds := n / mix_rate
		# Tremolo: 1 or 4.8 dB at 3.7 Hz. Vibrato: 7 or 14 cents at 6.1 Hz.
		var trem := (0.5 - 0.5 * cos(TAU * 3.7 * _lfo_time)) * (4.8 if _am_deep else 1.0) / 0.1875
		var vib := sin(TAU * 6.07 * _lfo_time) * (14.0 if _vib_deep else 7.0)
		var vib_ratio := pow(2.0, vib / 1200.0)
		for ch in channels:
			if _rhythm and ch >= 6 and ch <= 8:
				continue
			if is_channel_silent(ch):
				continue
			_render_channel(ch, left, right, offset + done, n, trem, vib_ratio, seconds)
		if _rhythm:
			_render_rhythm(left, right, offset + done, n, trem, seconds)
		_lfo_time += seconds
		done += n


func _render_channel(ch: int, left: PackedFloat32Array, right: PackedFloat32Array, at: int, n: int, trem: float, vib_ratio: float, seconds: float) -> void:
	var m := ch * 2
	var c := m + 1
	var g1 := _gain(m, trem)
	var g2 := _gain(c, trem)
	_advance(m, seconds)
	_advance(c, seconds)
	var d1 := (_gain(m, trem) - g1) / n
	var d2 := (_gain(c, trem) - g2) / n
	var w1 := WAVES[_wave(m)]
	var w2 := WAVES[_wave(c)]
	var i1 := _inc[m] * (vib_ratio if _vib[m] else 1.0)
	var i2 := _inc[c] * (vib_ratio if _vib[c] else 1.0)
	var p1 := _phase[m]
	var p2 := _phase[c]
	var f1 := _fb1[ch]
	var f2 := _fb2[ch]
	var fb := _fb[ch]
	var fbk := pow(2.0, fb - 7) * WAVE_LEN if fb > 0 else 0.0
	var depth := MOD_CYCLES * WAVE_LEN
	var additive := _cnt[ch] == 1
	var mask := WAVE_LEN - 1
	var level := CHANNEL_LEVEL * channel_gain[ch]
	var gl := level * _pan_l[ch]
	var gr := level * _pan_r[ch]
	for k in n:
		var o1 := w1[int(p1 + (f1 + f2) * fbk) & mask] * g1
		f2 = f1
		f1 = o1
		var s: float
		if additive:
			s = o1 + w2[int(p2) & mask] * g2
		else:
			s = w2[int(p2 + o1 * depth) & mask] * g2
		left[at + k] += s * gl
		right[at + k] += s * gr
		p1 += i1
		p2 += i2
		g1 += d1
		g2 += d2
	_phase[m] = fmod(p1, WAVE_LEN)
	_phase[c] = fmod(p2, WAVE_LEN)
	_fb1[ch] = f1
	_fb2[ch] = f2


## The rhythm mode: bass drum on channel 6's two operators; hi-hat and
## snare on channel 7's; tom and cymbal on channel 8's. The hi-hat, snare
## and cymbal build their phase from bits of two operators' phases and the
## noise generator, as the chip does.
func _render_rhythm(left: PackedFloat32Array, right: PackedFloat32Array, at: int, n: int, trem: float, seconds: float) -> void:
	var g := PackedFloat32Array()
	var d := PackedFloat32Array()
	g.resize(6)
	d.resize(6)
	for k in 6:
		g[k] = _gain(12 + k, trem)
	for k in 6:
		_advance(12 + k, seconds)
		d[k] = (_gain(12 + k, trem) - g[k]) / n
	var level := CHANNEL_LEVEL * 2.0
	var mask := WAVE_LEN - 1
	var depth := MOD_CYCLES * WAVE_LEN
	var w_bd1 := WAVES[_wave(12)]
	var w_bd2 := WAVES[_wave(13)]
	var w_hh := WAVES[_wave(14)]
	var w_sd := WAVES[_wave(15)]
	var w_tom := WAVES[_wave(16)]
	var w_cym := WAVES[_wave(17)]
	var p := PackedFloat64Array()
	p.resize(6)
	for k in 6:
		p[k] = _phase[12 + k]
	var f1 := _fb1[6]
	var f2 := _fb2[6]
	var fbk := pow(2.0, _fb[6] - 7) * WAVE_LEN if _fb[6] > 0 else 0.0
	var bd_add := _cnt[6] == 1
	var noise := _noise
	var noise_steps := CHIP_RATE / mix_rate
	var noise_acc := 0.0
	var gains := [channel_gain[6], channel_gain[7], channel_gain[8]]
	for k in n:
		# Bass drum: an ordinary two-operator voice.
		var o1 := w_bd1[int(p[0] + (f1 + f2) * fbk) & mask] * g[0]
		f2 = f1
		f1 = o1
		var bd := (o1 + w_bd2[int(p[1]) & mask] * g[1]) if bd_add else w_bd2[int(p[1] + o1 * depth) & mask] * g[1]
		# Noise: a 23-bit generator stepped at the chip's rate.
		noise_acc += noise_steps
		while noise_acc >= 1.0:
			noise_acc -= 1.0
			var bit := ((noise >> 22) ^ (noise >> 8) ^ (noise >> 7) ^ noise) & 1
			noise = ((noise << 1) | bit) & 0x7FFFFF
		var nbit := noise & 1
		var ph13 := int(p[2]) & mask
		var ph17 := int(p[5]) & mask
		var res := (((ph13 >> 2) ^ (ph13 >> 7)) | (ph13 >> 3)) & 1
		if ((ph17 >> 3) ^ (ph17 >> 5)) & 1:
			res = 1
		var hh_phase := 0
		if res:
			hh_phase = 0x200 | 0xD0 if nbit else 0x200 | (0xD0 >> 2)
		else:
			hh_phase = 0xD0 >> 2 if nbit else 0xD0
		var hh := w_hh[hh_phase & mask] * g[2]
		var sd_phase := 0x200 if (ph13 >> 8) & 1 else 0x100
		if nbit:
			sd_phase ^= 0x100
		var sd := w_sd[sd_phase & mask] * g[3]
		var tom := w_tom[int(p[4]) & mask] * g[4]
		var cym := w_cym[(0x300 if res else 0x100) & mask] * g[5]
		var s: float = (bd * gains[0] + (hh + sd) * gains[1] + (tom + cym) * gains[2]) * level
		left[at + k] += s * _pan_l[6]
		right[at + k] += s * _pan_r[6]
		for j in 6:
			p[j] += _inc[12 + j]
			g[j] += d[j]
	for k in 6:
		_phase[12 + k] = fmod(p[k], WAVE_LEN)
	_fb1[6] = f1
	_fb2[6] = f2
	_noise = noise
