class_name GusMixer
extends SnesDsp
## The Gravis Ultrasound's GF1 chip, as [GusPlayer] drives it through the
## same voice registers as the S-DSP (pitch, volume, gain, key on and off).
##
## Voices play 16-bit samples with linear interpolation between them, and
## each voice's pan snaps to one of the GF1's 16 positions. There is no
## echo and no Gaussian filter: the GUS sounds cleaner and brighter than the
## SNES.

var _now := 0.0
var _last := 0.0


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	var step := DSP_HZ / _rate
	var prev := _last
	for i in count:
		_phase += step
		while _phase >= 1.0:
			_phase -= 1.0
			prev = _now
			_now = _sample()
		out[offset + i] = prev + (_now - prev) * _phase
	_last = prev



func _sample() -> float:
	var left := 0.0
	var right := 0.0
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
		var frac := _frac[v]
		var a := pcm[p]
		var nxt := p + 1
		if nxt >= _size[v]:
			nxt = _loop[v] if _loop[v] >= 0 else p
		var s := a + (pcm[nxt] - a) * (frac / 4096.0)
		var level := s * env / 2048.0
		var vl := _regs[base + V_VOLL]
		var vr := _regs[base + V_VOLR]
		if vl >= 128:
			vl -= 256
		if vr >= 128:
			vr -= 256
		# The GF1 pans in 16 steps between the speakers.
		var total := absf(vl) + absf(vr)
		var pan := roundf(absf(vr) / maxf(total, 1.0) * 15.0) / 15.0
		var vol := (absf(vl) + absf(vr)) / 2.0 / 128.0 * channel_gain[v]
		left += level * vol * (1.0 - pan) * 2.0
		right += level * vol * pan * 2.0
		var pitch := (_regs[base + V_PITCHL] | (_regs[base + V_PITCHH] << 8)) & 0x3FFF
		frac += pitch
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
	return clampf((left + right) * 0.5 * mvol / 128.0 / 32768.0, -1.0, 1.0)
