class_name ChipEngines
extends RefCounted
## The tables and samples behind [ChipVoice]'s synth engines, made from
## maths when first used and kept for the session. Nothing is recorded or
## downloaded, and the integer noise generator makes every sample the same
## on every platform.
##
## Engines, set by an instrument's "engine" key:
## [br]- "chip" (or none): the classic chip oscillators.
## [br]- "analog": two detuned oscillators through a resonant low-pass
##   filter with its own envelope.
## [br]- "fm": a two-operator FM pair whose brightness decays.
## [br]- "wavetable": a sweep through a bank of single-cycle waves.
## [br]- "sampled": a sample made here (plucked string, electric piano,
##   strings, brass, bell, or drums), played at the note's pitch.

const TABLE_SIZE := 64
const FRAMES := 8
const SAMPLE_RATE := 22050.0
## The pitch every tonal sample is made at.
const SAMPLE_ROOT := 60.0
const BANKS: PackedStringArray = ["bright", "soft", "vocal", "metal"]
const SAMPLES: PackedStringArray = ["pluck", "epiano", "strings", "brass", "bell", "kick", "snare", "hat", "open_hat", "crash", "tom"]
## Samples that sustain by looping, with their loop as [start, end] in
## samples.
const LOOPED := {"strings": [4410, 22050], "brass": [4410, 22050]}
## Drum samples ignore the note's pitch (toms follow it a little).
const UNPITCHED: PackedStringArray = ["kick", "snare", "hat", "open_hat", "crash"]

static var _banks := {}
static var _samples := {}


## A bank: [constant FRAMES] waves of [constant TABLE_SIZE] samples each,
## from soft to bright.
static func bank(bank_name: String) -> Array[PackedFloat32Array]:
	if not _banks.has(bank_name):
		_banks[bank_name] = _make_bank(bank_name)
	return _banks[bank_name]


static func sample(sample_name: String) -> PackedFloat32Array:
	if not _samples.has(sample_name):
		_samples[sample_name] = _make_sample(sample_name)
	return _samples[sample_name]


static func _make_bank(bank_name: String) -> Array[PackedFloat32Array]:
	var frames: Array[PackedFloat32Array] = []
	for f in FRAMES:
		var t := f / float(FRAMES - 1)
		var table := PackedFloat32Array()
		table.resize(TABLE_SIZE)
		var peak := 0.0
		for i in TABLE_SIZE:
			var x := i / float(TABLE_SIZE)
			var s := 0.0
			for h in range(1, 17):
				var amp := _harmonic(bank_name, h, t)
				if amp != 0.0:
					s += amp * sin(TAU * h * x)
			table[i] = s
			peak = maxf(peak, absf(s))
		for i in TABLE_SIZE:
			table[i] /= maxf(peak, 0.0001)
		frames.append(table)
	return frames


## Harmonic [param h]'s level in frame position [param t] (0 soft, 1 bright).
static func _harmonic(bank_name: String, h: int, t: float) -> float:
	match bank_name:
		"soft":
			# Sine to a gentle triangle-like odd series.
			if h == 1:
				return 1.0
			return t * (1.0 / (h * h)) if h % 2 == 1 else 0.0
		"vocal":
			# A formant that moves from "oo" to "ah".
			var centre := lerpf(2.0, 7.0, t)
			return exp(-pow((h - centre) / 1.6, 2.0)) + (0.6 if h == 1 else 0.0)
		"metal":
			# Odd partials that grow strong, for a hollow, ringing tone.
			return (1.0 / h) * (1.0 if h % 2 == 1 else t * 0.3) * (1.0 + t * (h % 3))
	# "bright": sine to sawtooth.
	if h == 1:
		return 1.0
	return t / h


static func _make_sample(sample_name: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var noise := _Noise.new(sample_name.hash() & 0x7FFFFFFF)
	match sample_name:
		"pluck":
			# Karplus-Strong at the root pitch.
			var period := int(round(SAMPLE_RATE / _freq(SAMPLE_ROOT)))
			var line := PackedFloat32Array()
			line.resize(period)
			for i in period:
				line[i] = noise.next()
			out.resize(int(SAMPLE_RATE * 1.6))
			var pos := 0
			var prev := 0.0
			for i in out.size():
				var cur := line[pos]
				var next := (cur + prev) * 0.4975
				prev = cur
				line[pos] = next
				out[i] = cur
				pos = (pos + 1) % period
		"epiano":
			# Tine-like: a sine with a quickly fading bell partial.
			out.resize(int(SAMPLE_RATE * 2.0))
			var f := _freq(SAMPLE_ROOT)
			for i in out.size():
				var t := i / SAMPLE_RATE
				var body := sin(TAU * f * t + 1.2 * exp(-t * 6.0) * sin(TAU * f * t))
				var tine := 0.35 * exp(-t * 9.0) * sin(TAU * f * 14.0 * t)
				out[i] = (body + tine) * exp(-t * 1.4)
		"strings":
			# Seven detuned saws, smoothed: an ensemble that loops.
			out.resize(int(SAMPLE_RATE * 1.0))
			var f := _freq(SAMPLE_ROOT)
			var detunes := [-0.012, -0.007, -0.003, 0.0, 0.004, 0.008, 0.013]
			var phases := PackedFloat64Array([0.0, 0.31, 0.57, 0.11, 0.83, 0.42, 0.69])
			var low := 0.0
			for i in out.size():
				var s := 0.0
				for v in detunes.size():
					phases[v] = fmod(phases[v] + f * (1.0 + detunes[v]) / SAMPLE_RATE, 1.0)
					s += 2.0 * phases[v] - 1.0
				low += (s / 7.0 - low) * 0.18
				out[i] = low * minf(i / (SAMPLE_RATE * 0.15), 1.0)
		"brass":
			# A saw whose brightness swells, as a player's lips open up.
			out.resize(int(SAMPLE_RATE * 1.0))
			var f := _freq(SAMPLE_ROOT)
			var phase := 0.0
			var low := 0.0
			for i in out.size():
				var t := i / SAMPLE_RATE
				phase = fmod(phase + f / SAMPLE_RATE, 1.0)
				var k := clampf(0.04 + t * 1.2, 0.04, 0.35)
				low += ((2.0 * phase - 1.0) - low) * k
				out[i] = low * minf(t / 0.04, 1.0)
		"bell":
			out.resize(int(SAMPLE_RATE * 2.5))
			var f := _freq(SAMPLE_ROOT)
			for i in out.size():
				var t := i / SAMPLE_RATE
				out[i] = sin(TAU * f * t + 2.5 * exp(-t * 1.5) * sin(TAU * f * 3.5 * t)) * exp(-t * 1.8)
		"kick":
			out.resize(int(SAMPLE_RATE * 0.45))
			var phase := 0.0
			for i in out.size():
				var t := i / SAMPLE_RATE
				phase += (45.0 + 130.0 * exp(-t * 28.0)) / SAMPLE_RATE
				out[i] = sin(TAU * phase) * exp(-t * 7.0) + noise.next() * 0.3 * exp(-t * 200.0)
		"tom":
			out.resize(int(SAMPLE_RATE * 0.5))
			var phase := 0.0
			for i in out.size():
				var t := i / SAMPLE_RATE
				phase += _freq(SAMPLE_ROOT - 12.0) * (1.0 + 0.6 * exp(-t * 18.0)) / SAMPLE_RATE
				out[i] = sin(TAU * phase) * exp(-t * 6.0)
		"snare":
			out.resize(int(SAMPLE_RATE * 0.3))
			var band := 0.0
			var low := 0.0
			for i in out.size():
				var t := i / SAMPLE_RATE
				var n := noise.next()
				low += (n - low) * 0.5
				band = n - low
				out[i] = band * exp(-t * 16.0) + sin(TAU * 185.0 * t) * 0.6 * exp(-t * 30.0)
		"hat", "open_hat", "crash":
			var length := {"hat": 0.08, "open_hat": 0.4, "crash": 1.4}[sample_name] as float
			var rate := {"hat": 60.0, "open_hat": 9.0, "crash": 2.8}[sample_name] as float
			out.resize(int(SAMPLE_RATE * length))
			var prev := 0.0
			for i in out.size():
				var t := i / SAMPLE_RATE
				var n := noise.next()
				# A first difference keeps only the hiss.
				out[i] = (n - prev) * 0.6 * exp(-t * rate)
				prev = n
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	for i in out.size():
		out[i] /= maxf(peak, 0.0001)
	return out


static func _freq(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## A 31-bit linear congruential generator: integer maths, so it gives the
## same numbers everywhere.
class _Noise:
	var state := 1

	func _init(seed_value: int) -> void:
		state = maxi(seed_value, 1)

	func next() -> float:
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		return (state >> 15) / 32767.5 - 1.0
