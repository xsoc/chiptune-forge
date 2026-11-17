class_name ChipVoice
extends RefCounted
## One oscillator with an envelope, used by [ChipSongSequencer].
##
## Pitch, vibrato and the envelope run at a control rate of one update per
## [constant CONTROL_FRAMES] frames. The audio loop in between only advances
## the oscillator and ramps the volume, which keeps GDScript fast enough for
## live playback on phones and the web.
##
## An instrument's "engine" key picks the synth: "chip" (or none) for the
## classic oscillators, or "analog", "fm", "wavetable" or "sampled", whose
## tables and samples come from [ChipEngines].

const CONTROL_FRAMES := 32

enum Wave { PULSE, TRIANGLE, SAW, SINE, NOISE, WAVETABLE }
enum Stage { IDLE, ATTACK, DECAY, SUSTAIN, RELEASE }
enum SynthEngine { CHIP, ANALOG, FM, WAVETABLE, SAMPLED }

const ENGINE_NAMES := {
	"chip": SynthEngine.CHIP,
	"analog": SynthEngine.ANALOG,
	"fm": SynthEngine.FM,
	"wavetable": SynthEngine.WAVETABLE,
	"sampled": SynthEngine.SAMPLED,
}

const WAVE_NAMES := {
	"pulse": Wave.PULSE,
	"square": Wave.PULSE,
	"triangle": Wave.TRIANGLE,
	"saw": Wave.SAW,
	"sine": Wave.SINE,
	"noise": Wave.NOISE,
	"wave": Wave.WAVETABLE,
}

var mix_rate := 44100.0
var stage := Stage.IDLE
## Current envelope level, 0 to 1. Useful for meters.
var level := 0.0
var pitch := 60.0
var age := 0

var _wave := Wave.PULSE
var _duty := 0.5
var _table := PackedFloat32Array()
var _tri_steps := 0
var _noise_short := false
var _attack_rate := 1.0
var _decay_rate := 1.0
var _sustain := 1.0
var _release_rate := 1.0
var _volume := 1.0
var _velocity := 1.0
var _vib_depth := 0.0
var _vib_rate := 0.0
var _vib_delay := 0.0
var _drop := 0.0
var _drop_time := 0.05
var _slide := 0.0
var _glide := 0.0
var _arp := PackedFloat32Array()
var _arp_rate := 30.0
var _echo := 0.0

var _phase := 0.0
var _lfsr := 1
var _noise_out := 1.0
var _target_pitch := 60.0
var _time := 0.0
var _gate := 0
var _control_left := 0
var _inc := 0.0
var _gain_from := 0.0
var _gain_to := 0.0

var _engine := SynthEngine.CHIP
# Analog: two detuned oscillators and a state-variable low-pass filter.
var _detune := 1.0
var _phase2 := 0.0
var _cutoff := 2000.0
var _damping := 1.0
var _env_amount := 0.0
var _filter_decay := 0.2
var _key_track := 0.5
var _svf_f := 0.5
var _low := 0.0
var _band := 0.0
# FM: a modulator at a ratio of the carrier, with a decaying index.
var _ratio := 1.0
var _index := 1.0
var _index_end := 0.0
var _index_decay := 0.3
var _feedback := 0.0
var _mod_phase := 0.0
var _mod_inc := 0.0
var _index_now := 0.0
var _fb_prev := 0.0
# Wavetable: a sweep through a bank's frames.
var _bank: Array[PackedFloat32Array] = []
var _wt_from := 0.0
var _wt_to := 1.0
var _wt_time := 0.5
var _frame_a := 0
var _frame_mix := 0.0
# Sampled.
var _sample := PackedFloat32Array()
var _sample_pos := 0.0
var _sample_step := 0.0
var _loop_start := -1
var _loop_end := -1
var _pitch_follow := 1.0


func _init(rate: float) -> void:
	mix_rate = rate


func is_active() -> bool:
	return stage != Stage.IDLE


## Starts a note. [param gate_frames] is how long the key is held before the
## release stage begins.
func note_on(note_pitch: float, gate_frames: int, instrument: Dictionary, velocity: float, arp: PackedFloat32Array) -> void:
	_configure(instrument)
	if _glide > 0.0 and stage != Stage.IDLE:
		_target_pitch = note_pitch
	else:
		pitch = note_pitch
		_target_pitch = note_pitch
		_phase = 0.0
		_phase2 = 0.37
		_mod_phase = 0.0
		_fb_prev = 0.0
		_low = 0.0
		_band = 0.0
		_sample_pos = 0.0
	if arp.size() > 0:
		_arp = arp
	_velocity = velocity
	_gate = maxi(gate_frames, 1)
	_time = 0.0
	age = 0
	stage = Stage.ATTACK
	_control_left = 0


func release() -> void:
	if stage != Stage.IDLE:
		stage = Stage.RELEASE


func kill() -> void:
	stage = Stage.IDLE
	level = 0.0
	_gain_from = 0.0
	_gain_to = 0.0


func _configure(inst: Dictionary) -> void:
	_wave = WAVE_NAMES.get(str(inst.get("wave", "pulse")), Wave.PULSE)
	_duty = clampf(float(inst.get("duty", 0.5)), 0.05, 0.95)
	_tri_steps = int(inst.get("steps", 0))
	_noise_short = bool(inst.get("short", false))
	var table: Array = inst.get("table", [])
	_table.resize(table.size())
	for i in table.size():
		_table[i] = float(table[i]) / 7.5 - 1.0
	if _wave == Wave.WAVETABLE and _table.is_empty():
		_wave = Wave.TRIANGLE
	_attack_rate = 1.0 / maxf(float(inst.get("attack", 0.002)) * mix_rate, 1.0)
	_decay_rate = 1.0 / maxf(float(inst.get("decay", 0.1)) * mix_rate, 1.0)
	_sustain = clampf(float(inst.get("sustain", 0.7)), 0.0, 1.0)
	_release_rate = 1.0 / maxf(float(inst.get("release", 0.05)) * mix_rate, 1.0)
	_volume = float(inst.get("volume", 0.8))
	_vib_depth = float(inst.get("vibrato_depth", 0.0))
	_vib_rate = float(inst.get("vibrato_rate", 5.5))
	_vib_delay = float(inst.get("vibrato_delay", 0.2))
	_drop = float(inst.get("pitch_drop", 0.0))
	_drop_time = maxf(float(inst.get("pitch_drop_time", 0.05)), 0.001)
	_slide = float(inst.get("slide", 0.0))
	_glide = float(inst.get("glide", 0.0))
	_arp_rate = float(inst.get("arp_rate", 30.0))
	_echo = float(inst.get("echo", 0.0))
	var arp: Array = inst.get("arp", [])
	_arp.resize(arp.size())
	for i in arp.size():
		_arp[i] = float(arp[i])
	_engine = ENGINE_NAMES.get(str(inst.get("engine", "chip")), SynthEngine.CHIP)
	match _engine:
		SynthEngine.ANALOG:
			_detune = pow(2.0, float(inst.get("detune", 8.0)) / 1200.0)
			_cutoff = clampf(float(inst.get("cutoff", 1200.0)), 40.0, 12000.0)
			_damping = 2.0 * (1.0 - clampf(float(inst.get("resonance", 0.3)), 0.0, 0.92))
			_env_amount = float(inst.get("env_amount", 2.0))
			_filter_decay = maxf(float(inst.get("filter_decay", 0.25)), 0.005)
			_key_track = float(inst.get("key_track", 0.5))
			if _wave != Wave.PULSE:
				_wave = Wave.SAW
		SynthEngine.FM:
			_ratio = maxf(float(inst.get("ratio", 1.0)), 0.25)
			_index = float(inst.get("index", 2.0))
			_index_end = float(inst.get("index_end", 0.5))
			_index_decay = maxf(float(inst.get("index_decay", 0.3)), 0.005)
			_feedback = clampf(float(inst.get("feedback", 0.0)), 0.0, 1.5)
		SynthEngine.WAVETABLE:
			_bank = ChipEngines.bank(str(inst.get("bank", "bright")))
			_wt_from = clampf(float(inst.get("wt_from", 0.0)), 0.0, 1.0)
			_wt_to = clampf(float(inst.get("wt_to", 1.0)), 0.0, 1.0)
			_wt_time = maxf(float(inst.get("wt_time", 0.5)), 0.005)
		SynthEngine.SAMPLED:
			var sample_name := str(inst.get("sample", "pluck"))
			_sample = ChipEngines.sample(sample_name)
			var loop: Array = ChipEngines.LOOPED.get(sample_name, [])
			_loop_start = int(loop[0]) if loop.size() == 2 else -1
			_loop_end = mini(int(loop[1]), _sample.size() - 1) if loop.size() == 2 else -1
			if sample_name in ChipEngines.UNPITCHED:
				_pitch_follow = 0.0
			elif sample_name == "tom":
				_pitch_follow = 0.5
			else:
				_pitch_follow = 1.0


## Updates pitch and envelope for the next control block. Returns the block
## length in frames.
func _control(max_frames: int) -> int:
	var frames := mini(CONTROL_FRAMES, max_frames)
	var dt := frames / mix_rate
	# Envelope, advanced by a whole block.
	var env := level
	var block := float(frames)
	match stage:
		Stage.ATTACK:
			env += _attack_rate * block
			if env >= 1.0:
				env = 1.0
				stage = Stage.DECAY
		Stage.DECAY:
			env -= _decay_rate * block * (1.0 - _sustain + 0.0001)
			if env <= _sustain:
				env = _sustain
				stage = Stage.SUSTAIN
		Stage.RELEASE:
			env -= _release_rate * block
			if env <= 0.0:
				env = 0.0
				stage = Stage.IDLE
	if stage != Stage.RELEASE and stage != Stage.IDLE:
		_gate -= frames
		if _gate <= 0:
			stage = Stage.RELEASE
	level = env
	_gain_from = _gain_to
	_gain_to = env * _volume * _velocity
	# Pitch.
	if _glide > 0.0 and pitch != _target_pitch:
		var step := dt / _glide * 12.0
		pitch = move_toward(pitch, _target_pitch, step)
	pitch += _slide * dt
	var p := pitch
	if _drop != 0.0:
		p += _drop * exp(-_time / _drop_time)
	if _vib_depth > 0.0 and _time > _vib_delay:
		p += _vib_depth * sin(TAU * _vib_rate * (_time - _vib_delay))
	if _arp.size() > 0:
		p += _arp[int(_time * _arp_rate) % _arp.size()]
	var freq := 440.0 * pow(2.0, (p - 69.0) / 12.0)
	if _wave == Wave.NOISE and _engine == SynthEngine.CHIP:
		_inc = freq * 16.0 / mix_rate
	else:
		_inc = minf(freq / mix_rate, 0.45)
	match _engine:
		SynthEngine.ANALOG:
			var octaves := _key_track * (p - 60.0) / 12.0 + _env_amount * exp(-_time / _filter_decay)
			var fc := minf(_cutoff * pow(2.0, octaves), mix_rate / 6.0)
			_svf_f = 2.0 * sin(PI * fc / mix_rate)
		SynthEngine.FM:
			_mod_inc = minf(_inc * _ratio, 0.49)
			_index_now = _index_end + (_index - _index_end) * exp(-_time / _index_decay)
		SynthEngine.WAVETABLE:
			var pos := lerpf(_wt_from, _wt_to, minf(_time / _wt_time, 1.0)) * (ChipEngines.FRAMES - 1)
			_frame_a = mini(int(pos), ChipEngines.FRAMES - 2)
			_frame_mix = pos - _frame_a
		SynthEngine.SAMPLED:
			var semis := (p - ChipEngines.SAMPLE_ROOT) * _pitch_follow
			_sample_step = ChipEngines.SAMPLE_RATE / mix_rate * pow(2.0, semis / 12.0)
	_time += dt
	age += frames
	return frames


## Adds this voice's output to the buffers. [param pan_l] and [param pan_r]
## are channel gains; [param send] collects the echo send.
func render(left: PackedFloat32Array, right: PackedFloat32Array, send: PackedFloat32Array, offset: int, count: int, pan_l: float, pan_r: float) -> void:
	var pos := offset
	var end := offset + count
	while pos < end and stage != Stage.IDLE:
		var frames := _control(end - pos)
		var g := _gain_from
		var g_step := (_gain_to - _gain_from) / float(frames)
		var phase := _phase
		var inc := _inc
		var stop := pos + frames
		var echo := _echo
		if _engine != SynthEngine.CHIP:
			_render_engine(left, right, send, pos, stop, g, g_step, pan_l, pan_r)
			pos = stop
			continue
		match _wave:
			Wave.PULSE:
				var duty := _duty
				while pos < stop:
					phase += inc
					if phase >= 1.0:
						phase -= 1.0
					var s := 1.0 if phase < duty else -1.0
					s += _blep(phase, inc)
					var t2 := phase - duty
					if t2 < 0.0:
						t2 += 1.0
					s -= _blep(t2, inc)
					s *= g * 0.5
					left[pos] += s * pan_l
					right[pos] += s * pan_r
					send[pos] += s * echo
					g += g_step
					pos += 1
			Wave.SAW:
				while pos < stop:
					phase += inc
					if phase >= 1.0:
						phase -= 1.0
					var s := (2.0 * phase - 1.0 - _blep(phase, inc)) * g * 0.45
					left[pos] += s * pan_l
					right[pos] += s * pan_r
					send[pos] += s * echo
					g += g_step
					pos += 1
			Wave.TRIANGLE:
				var steps := float(_tri_steps)
				while pos < stop:
					phase += inc
					if phase >= 1.0:
						phase -= 1.0
					var s := 1.0 - 4.0 * absf(phase - 0.5)
					if steps > 0.0:
						s = roundf(s * steps * 0.5) / (steps * 0.5)
					s *= g * 0.7
					left[pos] += s * pan_l
					right[pos] += s * pan_r
					send[pos] += s * echo
					g += g_step
					pos += 1
			Wave.SINE:
				while pos < stop:
					phase += inc
					if phase >= 1.0:
						phase -= 1.0
					var s := sin(phase * TAU) * g * 0.7
					left[pos] += s * pan_l
					right[pos] += s * pan_r
					send[pos] += s * echo
					g += g_step
					pos += 1
			Wave.WAVETABLE:
				var table := _table
				var size := table.size()
				while pos < stop:
					phase += inc
					if phase >= 1.0:
						phase -= 1.0
					var s := table[int(phase * size)] * g * 0.5
					left[pos] += s * pan_l
					right[pos] += s * pan_r
					send[pos] += s * echo
					g += g_step
					pos += 1
			Wave.NOISE:
				var lfsr := _lfsr
				var out := _noise_out
				var tap := 6 if _noise_short else 1
				while pos < stop:
					phase += inc
					while phase >= 1.0:
						phase -= 1.0
						var bit := (lfsr ^ (lfsr >> tap)) & 1
						lfsr = (lfsr >> 1) | (bit << 14)
						out = 1.0 if (lfsr & 1) == 0 else -1.0
					var s := out * g * 0.4
					left[pos] += s * pan_l
					right[pos] += s * pan_r
					send[pos] += s * echo
					g += g_step
					pos += 1
				_lfsr = lfsr
				_noise_out = out
		_phase = phase
	if stage == Stage.IDLE:
		level = 0.0


## The audio loop for the engines other than "chip".
func _render_engine(left: PackedFloat32Array, right: PackedFloat32Array, send: PackedFloat32Array, pos: int, stop: int, g: float, g_step: float, pan_l: float, pan_r: float) -> void:
	var echo := _echo
	var phase := _phase
	var inc := _inc
	match _engine:
		SynthEngine.ANALOG:
			var phase2 := _phase2
			var inc2 := minf(inc * _detune, 0.45)
			var f := _svf_f
			var q := _damping
			var low := _low
			var band := _band
			var pulse := _wave == Wave.PULSE
			var duty := _duty
			while pos < stop:
				phase += inc
				if phase >= 1.0:
					phase -= 1.0
				phase2 += inc2
				if phase2 >= 1.0:
					phase2 -= 1.0
				var x: float
				if pulse:
					var t1 := phase - duty
					if t1 < 0.0:
						t1 += 1.0
					var t2 := phase2 - duty
					if t2 < 0.0:
						t2 += 1.0
					x = (1.0 if phase < duty else -1.0) + _blep(phase, inc) - _blep(t1, inc)
					x += (1.0 if phase2 < duty else -1.0) + _blep(phase2, inc2) - _blep(t2, inc2)
				else:
					x = 2.0 * phase - 1.0 - _blep(phase, inc) + 2.0 * phase2 - 1.0 - _blep(phase2, inc2)
				low += f * band
				var high := x - low - q * band
				band += f * high
				var s := low * g * 0.3
				left[pos] += s * pan_l
				right[pos] += s * pan_r
				send[pos] += s * echo
				g += g_step
				pos += 1
			_phase2 = phase2
			_low = low
			_band = band
		SynthEngine.FM:
			var mod_phase := _mod_phase
			var mod_inc := _mod_inc
			var index := _index_now
			var fb := _feedback
			var prev := _fb_prev
			while pos < stop:
				phase += inc
				if phase >= 1.0:
					phase -= 1.0
				mod_phase += mod_inc
				if mod_phase >= 1.0:
					mod_phase -= 1.0
				var m := sin(TAU * mod_phase + fb * prev)
				prev = m
				var s := sin(TAU * phase + index * m) * g * 0.6
				left[pos] += s * pan_l
				right[pos] += s * pan_r
				send[pos] += s * echo
				g += g_step
				pos += 1
			_mod_phase = mod_phase
			_fb_prev = prev
		SynthEngine.WAVETABLE:
			var a := _bank[_frame_a]
			var b := _bank[_frame_a + 1]
			var mix := _frame_mix
			var size := ChipEngines.TABLE_SIZE
			while pos < stop:
				phase += inc
				if phase >= 1.0:
					phase -= 1.0
				var x := phase * size
				var i0 := int(x)
				var i1 := (i0 + 1) % size
				var frac := x - i0
				var va := a[i0] + (a[i1] - a[i0]) * frac
				var vb := b[i0] + (b[i1] - b[i0]) * frac
				var s := (va + (vb - va) * mix) * g * 0.55
				left[pos] += s * pan_l
				right[pos] += s * pan_r
				send[pos] += s * echo
				g += g_step
				pos += 1
		SynthEngine.SAMPLED:
			var data := _sample
			var spos := _sample_pos
			var step := _sample_step
			var last := data.size() - 1
			var loop_start := float(_loop_start)
			var loop_end := float(_loop_end)
			var looped := _loop_start >= 0
			while pos < stop:
				if looped and spos >= loop_end:
					spos -= loop_end - loop_start
				if spos >= last:
					stage = Stage.IDLE
					break
				var i0 := int(spos)
				var frac := spos - i0
				var s := (data[i0] + (data[i0 + 1] - data[i0]) * frac) * g * 0.6
				left[pos] += s * pan_l
				right[pos] += s * pan_r
				send[pos] += s * echo
				spos += step
				g += g_step
				pos += 1
			_sample_pos = spos
	_phase = phase


static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0
