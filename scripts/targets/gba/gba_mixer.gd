class_name GbaMixer
extends SnesDsp
## Maxmod's software mixer on the Game Boy Advance, as [GbaPlayer] drives it
## through the same voice registers as the S-DSP (pitch, volume, gain, key on
## and off).
##
## Voices play 8-bit samples with no interpolation (Maxmod picks the nearest
## sample), and the mix comes out at [constant GbaSong.MIX_HZ], held between
## output samples, which gives the GBA's slightly gritty sound. There is no
## echo.

var _hold := 0.0
var _hold_phase := 0.0


func set_source(srcn: int, decoded: Dictionary) -> void:
	var pcm: PackedInt32Array = (decoded["pcm"] as PackedInt32Array).duplicate()
	for i in pcm.size():
		pcm[i] = clampi(roundi(pcm[i] / 256.0), -128, 127) * 256
	super(srcn, {"pcm": pcm, "loop": decoded["loop"]})


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	var step := DSP_HZ / _rate
	var hold_step := float(GbaSong.MIX_HZ) / DSP_HZ
	for i in count:
		_phase += step
		while _phase >= 1.0:
			_phase -= 1.0
			var s := _sample()
			_hold_phase += hold_step
			if _hold_phase >= 1.0:
				_hold_phase -= 1.0
				_hold = s
		out[offset + i] = _hold


func _sample() -> float:
	var main := 0
	for v in VOICES:
		if not _on[v]:
			continue
		var base := v * 0x10
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
		var pcm: PackedInt32Array = _pcm[v]
		var p := _pos[v]
		var s := pcm[p] >> 1
		var level := (s * env) >> 11
		var vl := _regs[base + V_VOLL]
		var vr := _regs[base + V_VOLR]
		if vl >= 128:
			vl -= 256
		if vr >= 128:
			vr -= 256
		main += int(((level * vl >> 7) + (level * vr >> 7)) * 0.5 * channel_gain[v])
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
	return clampi((main * mvol) >> 7, -32768, 32767) / 32768.0
