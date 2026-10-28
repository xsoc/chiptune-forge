class_name ChipVoice
extends RefCounted
## One oscillator with an envelope, used by [ChipSongSequencer].
##
## Pitch, vibrato and the envelope run at a control rate of one update per
## [constant CONTROL_FRAMES] frames. The audio loop in between only advances
## the oscillator and ramps the volume, which keeps GDScript fast enough for
## live playback on phones and the web.

const CONTROL_FRAMES := 32

enum Wave { PULSE, TRIANGLE, SAW, SINE, NOISE, WAVETABLE }
enum Stage { IDLE, ATTACK, DECAY, SUSTAIN, RELEASE }

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
	if _wave == Wave.NOISE:
		_inc = freq * 16.0 / mix_rate
	else:
		_inc = minf(freq / mix_rate, 0.45)
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


static func _blep(t: float, dt: float) -> float:
	if t < dt:
		t /= dt
		return t + t - t * t - 1.0
	if t > 1.0 - dt:
		t = (t - 1.0) / dt
		return t * t + t + t + 1.0
	return 0.0
