class_name ChipSfxSynth
extends RefCounted
## Renders sound effect parameters to audio.
##
## The model follows sfxr by DrPetter (MIT licence): a single oscillator with
## an attack, sustain-with-punch and decay envelope, pitch slide, vibrato,
## arpeggio jump, duty sweep, retrigger, phaser and resonant filters. It adds
## a triangle wave, a short-period noise, bit-crush and echo.
##
## Parameters use sfxr's 0 to 1 (or -1 to 1) ranges, so sfxr and jsfxr
## settings carry over. Missing keys take the defaults in [constant DEFAULTS].

const DEFAULT_RATE := 44100
const MAX_SECONDS := 6.0
const OVERSAMPLE := 8

const WAVES: PackedStringArray = ["square", "saw", "sine", "noise", "triangle", "noise_short"]

const DEFAULTS := {
	"wave": "square",
	"attack": 0.0,
	"sustain": 0.3,
	"punch": 0.0,
	"decay": 0.4,
	"base_freq": 0.3,
	"freq_limit": 0.0,
	"freq_ramp": 0.0,
	"freq_dramp": 0.0,
	"vib_strength": 0.0,
	"vib_speed": 0.0,
	"arp_mod": 0.0,
	"arp_speed": 0.0,
	"duty": 0.0,
	"duty_ramp": 0.0,
	"repeat_speed": 0.0,
	"pha_offset": 0.0,
	"pha_ramp": 0.0,
	"lpf_freq": 1.0,
	"lpf_ramp": 0.0,
	"lpf_resonance": 0.0,
	"hpf_freq": 0.0,
	"hpf_ramp": 0.0,
	"crush": 0.0,
	"echo": 0.0,
	"echo_delay": 0.12,
	"volume": 0.5,
	"noise_seed": 1,
}


## Fills in every missing parameter with its default.
static func with_defaults(params: Dictionary) -> Dictionary:
	var full := DEFAULTS.duplicate()
	for key in params:
		full[key] = params[key]
	return full


## Renders [param params] to mono samples at [param mix_rate].
static func render(params: Dictionary, mix_rate := DEFAULT_RATE) -> PackedFloat32Array:
	var p := with_defaults(params)
	var state := _State.new()
	state.setup(p)
	# sfxr runs its oscillator at 44.1 kHz times the oversample factor. At
	# other rates, scale the step so pitch and timing stay the same.
	var rate_scale := float(DEFAULT_RATE) / float(mix_rate)
	var max_frames := int(MAX_SECONDS * mix_rate)
	var out := PackedFloat32Array()
	out.resize(max_frames)
	var frames := 0
	var acc := 0.0
	while frames < max_frames and state.playing:
		acc += rate_scale
		var sample := 0.0
		var steps := 0
		while acc >= 1.0:
			acc -= 1.0
			sample += state.tick()
			steps += 1
			if not state.playing:
				break
		if steps > 0:
			sample /= float(steps)
		out[frames] = sample
		frames += 1
	out.resize(frames)
	_apply_crush(out, float(p["crush"]))
	_apply_echo(out, float(p["echo"]), float(p["echo_delay"]), mix_rate)
	var gain := 2.0 * float(p["volume"])
	for i in out.size():
		out[i] = clampf(out[i] * gain, -1.0, 1.0)
	_fade_tail(out, mix_rate)
	return out


static func _apply_crush(samples: PackedFloat32Array, amount: float) -> void:
	if amount <= 0.0:
		return
	var levels := pow(2.0, lerpf(12.0, 3.0, amount))
	var hold := 1 + int(amount * amount * 12.0)
	var held := 0.0
	for i in samples.size():
		if i % hold == 0:
			held = roundf(samples[i] * levels) / levels
		samples[i] = held


static func _apply_echo(samples: PackedFloat32Array, amount: float, delay: float, mix_rate: int) -> void:
	if amount <= 0.0:
		return
	var delay_frames := maxi(1, int(delay * mix_rate))
	var feedback := 0.25 + amount * 0.4
	var tail := int(delay_frames * 4)
	var old_size := samples.size()
	samples.resize(old_size + tail)
	for i in range(old_size, samples.size()):
		samples[i] = 0.0
	for i in range(delay_frames, samples.size()):
		samples[i] += samples[i - delay_frames] * feedback * amount


static func _fade_tail(samples: PackedFloat32Array, mix_rate: int) -> void:
	var fade := mini(samples.size(), int(0.004 * mix_rate))
	for i in fade:
		samples[samples.size() - 1 - i] *= float(i) / float(fade)


class _State:
	extends RefCounted

	var playing := true
	var p: Dictionary
	var wave := 0
	var phase := 0
	var fperiod := 0.0
	var fmaxperiod := 0.0
	var fslide := 0.0
	var fdslide := 0.0
	var period := 8
	var square_duty := 0.5
	var square_slide := 0.0
	var env_stage := 0
	var env_time := 0
	var env_length: PackedFloat32Array = [0.0, 0.0, 0.0]
	var env_vol := 0.0
	var fphase := 0.0
	var fdphase := 0.0
	var iphase := 0
	var phaser_buffer := PackedFloat32Array()
	var ipp := 0
	var noise_buffer := PackedFloat32Array()
	var fltp := 0.0
	var fltdp := 0.0
	var fltw := 0.0
	var fltw_d := 0.0
	var fltdmp := 0.0
	var fltphp := 0.0
	var flthp := 0.0
	var flthp_d := 0.0
	var vib_phase := 0.0
	var vib_speed := 0.0
	var vib_amp := 0.0
	var rep_time := 0
	var rep_limit := 0
	var arp_time := 0
	var arp_limit := 0
	var arp_mod := 0.0
	var punch := 0.0
	var lpf_on := true
	var tri_mix := false
	var noise_seed := 1

	func setup(params: Dictionary) -> void:
		p = params
		wave = maxi(0, WAVES.find(str(p["wave"])))
		noise_seed = int(p["noise_seed"]) | 1
		phaser_buffer.resize(1024)
		phaser_buffer.fill(0.0)
		noise_buffer.resize(32)
		_reset(true)

	func _noise() -> float:
		# Small xorshift so a sound renders the same every time.
		noise_seed ^= (noise_seed << 13) & 0xFFFFFFFF
		noise_seed ^= noise_seed >> 17
		noise_seed ^= (noise_seed << 5) & 0xFFFFFFFF
		noise_seed &= 0xFFFFFFFF
		return float(noise_seed) / 2147483647.5 - 1.0

	func _refill_noise() -> void:
		if wave == 5:
			# Short-period noise: a repeating 4-value cycle, metallic and tonal.
			for i in 32:
				noise_buffer[i] = noise_buffer[i % 4] if i >= 4 else _noise()
		else:
			for i in 32:
				noise_buffer[i] = _noise()

	func _reset(full: bool) -> void:
		var base := float(p["base_freq"])
		var limit := float(p["freq_limit"])
		fperiod = 100.0 / (base * base + 0.001)
		period = int(fperiod)
		fmaxperiod = 100.0 / (limit * limit + 0.001)
		fslide = 1.0 - pow(float(p["freq_ramp"]), 3.0) * 0.01
		fdslide = -pow(float(p["freq_dramp"]), 3.0) * 0.000001
		square_duty = 0.5 - float(p["duty"]) * 0.5
		square_slide = -float(p["duty_ramp"]) * 0.00005
		var a := float(p["arp_mod"])
		arp_mod = 1.0 - a * a * 0.9 if a >= 0.0 else 1.0 + a * a * 10.0
		arp_time = 0
		var arp_speed := float(p["arp_speed"])
		arp_limit = int(pow(1.0 - arp_speed, 2.0) * 20000.0 + 32.0)
		if arp_speed == 1.0:
			arp_limit = 0
		if not full:
			return
		phase = 0
		fltp = 0.0
		fltdp = 0.0
		var lpf := float(p["lpf_freq"])
		lpf_on = lpf < 1.0
		fltw = pow(lpf, 3.0) * 0.1
		fltw_d = 1.0 + float(p["lpf_ramp"]) * 0.0001
		var res := float(p["lpf_resonance"])
		fltdmp = minf(5.0 / (1.0 + res * res * 20.0) * (0.01 + fltw), 0.8)
		fltphp = 0.0
		flthp = pow(float(p["hpf_freq"]), 2.0) * 0.1
		flthp_d = 1.0 + float(p["hpf_ramp"]) * 0.0003
		vib_phase = 0.0
		vib_speed = pow(float(p["vib_speed"]), 2.0) * 0.01
		vib_amp = float(p["vib_strength"]) * 0.5
		env_vol = 0.0
		env_stage = 0
		env_time = 0
		env_length[0] = maxf(1.0, pow(float(p["attack"]), 2.0) * 100000.0)
		env_length[1] = maxf(1.0, pow(float(p["sustain"]), 2.0) * 100000.0)
		env_length[2] = maxf(1.0, pow(float(p["decay"]), 2.0) * 100000.0)
		punch = float(p["punch"])
		var po := float(p["pha_offset"])
		fphase = po * po * 1020.0 * signf(po)
		var pr := float(p["pha_ramp"])
		fdphase = pr * pr * signf(pr)
		iphase = absi(int(fphase))
		ipp = 0
		phaser_buffer.fill(0.0)
		_refill_noise()
		rep_time = 0
		var repeat := float(p["repeat_speed"])
		rep_limit = int(pow(1.0 - repeat, 2.0) * 20000.0 + 32.0)
		if repeat == 0.0:
			rep_limit = 0

	## Advances one output sample of the 44.1 kHz model and returns it.
	func tick() -> float:
		rep_time += 1
		if rep_limit != 0 and rep_time >= rep_limit:
			rep_time = 0
			_reset(false)
		arp_time += 1
		if arp_limit != 0 and arp_time >= arp_limit:
			arp_limit = 0
			fperiod *= arp_mod
		fslide += fdslide
		fperiod *= fslide
		if fperiod > fmaxperiod:
			fperiod = fmaxperiod
			if float(p["freq_limit"]) > 0.0:
				playing = false
		var rfperiod := fperiod
		if vib_amp > 0.0:
			vib_phase += vib_speed
			rfperiod = fperiod * (1.0 + sin(vib_phase) * vib_amp)
		period = maxi(int(rfperiod), 8)
		square_duty = clampf(square_duty + square_slide, 0.0, 0.5)
		env_time += 1
		if env_time > env_length[env_stage]:
			env_time = 0
			env_stage += 1
			if env_stage == 3:
				playing = false
				return 0.0
		match env_stage:
			0:
				env_vol = env_time / env_length[0]
			1:
				env_vol = 1.0 + (1.0 - env_time / env_length[1]) * 2.0 * punch
			_:
				env_vol = 1.0 - env_time / env_length[2]
		fphase += fdphase
		iphase = mini(absi(int(fphase)), 1023)
		if flthp_d != 1.0:
			flthp = clampf(flthp * flthp_d, 0.00001, 0.1)
		var ssample := 0.0
		for _i in OVERSAMPLE:
			phase += 1
			if phase >= period:
				phase %= period
				if wave == 3 or wave == 5:
					_refill_noise()
			var fp := float(phase) / float(period)
			var sample := 0.0
			match wave:
				0:
					sample = 0.5 if fp < square_duty else -0.5
				1:
					sample = 1.0 - fp * 2.0
				2:
					sample = sin(fp * TAU)
				4:
					sample = 1.0 - 4.0 * absf(fp - 0.5)
				_:
					sample = noise_buffer[phase * 32 / period]
			var pp := fltp
			fltw = clampf(fltw * fltw_d, 0.0, 0.1)
			if lpf_on:
				fltdp += (sample - fltp) * fltw
				fltdp -= fltdp * fltdmp
			else:
				fltp = sample
				fltdp = 0.0
			fltp += fltdp
			fltphp += fltp - pp
			fltphp -= fltphp * flthp
			sample = fltphp
			phaser_buffer[ipp & 1023] = sample
			sample += phaser_buffer[(ipp - iphase + 1024) & 1023]
			ipp = (ipp + 1) & 1023
			ssample += sample * env_vol
		return ssample / float(OVERSAMPLE)
