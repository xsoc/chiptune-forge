class_name SnesSamples
extends RefCounted
## The samples SNES songs play: short looped waves for the tonal parts and
## one-shot drums, all made here from recipes, so every song carries the
## same small bank.
##
## Each sample is 16-bit PCM plus a loop, and plays the pitch it was made
## for at Impulse Tracker note 60 (MIDI middle C) when played back at its
## [code]c5[/code] rate. Loops are whole BRR blocks (16 samples), so smconv
## takes them as they are. The BRR encoding of every sample is stored in
## [constant BRR_DIR] (written by tools/snes_samples.gd), because encoding
## is slow in GDScript; [method brr] encodes on the spot if a file is
## missing.

const BRR_DIR := "res://assets/snes/samples/"
## MIDI middle C, in Hz: what note 60 plays.
const C5_HZ := 261.6256
## Peak level of the waves, leaving room for the DSP's interpolation.
const WAVE_LEVEL := 0.6

## name -> {kind, ...}: "wave" (one cycle of [code]cycle[/code] samples),
## "pad" (two detuned waves over a long loop) or "drum".
const RECIPES := {
	"pulse12": {"kind": "wave", "shape": "pulse", "duty": 0.125, "cycle": 32},
	"pulse25": {"kind": "wave", "shape": "pulse", "duty": 0.25, "cycle": 32},
	"square": {"kind": "wave", "shape": "pulse", "duty": 0.5, "cycle": 32},
	"saw": {"kind": "wave", "shape": "saw", "cycle": 32},
	"triangle": {"kind": "wave", "shape": "triangle", "cycle": 32},
	"sine": {"kind": "wave", "shape": "sine", "cycle": 32},
	"bass_triangle": {"kind": "wave", "shape": "triangle", "cycle": 64},
	"bass_saw": {"kind": "wave", "shape": "soft_saw", "cycle": 64},
	"bass_square": {"kind": "wave", "shape": "pulse", "duty": 0.5, "cycle": 64},
	"pad_saw": {"kind": "pad", "shape": "saw"},
	"pad_square": {"kind": "pad", "shape": "pulse"},
	"kick": {"kind": "drum", "rate": 12000, "seconds": 0.22},
	"snare": {"kind": "drum", "rate": 16000, "seconds": 0.2},
	"tom": {"kind": "drum", "rate": 12000, "seconds": 0.3},
	"hat": {"kind": "drum", "rate": 16000, "seconds": 0.06},
	"open_hat": {"kind": "drum", "rate": 16000, "seconds": 0.3},
	"crash": {"kind": "drum", "rate": 12000, "seconds": 0.7},
	"ride": {"kind": "drum", "rate": 16000, "seconds": 0.35},
}
## A pad's loop: [constant PAD_CYCLES] cycles of one wave against one more
## of the other, about a quarter of a semitone apart.
const PAD_LOOP := 2048
const PAD_CYCLES := 64

static var _cache := {}
static var _brr_cache := {}


## The sample [param sample_name]: {name, pcm: PackedInt32Array, loop_start,
## loop_length (0 for one-shots), c5: playback rate for note 60}.
static func get_sample(sample_name: String) -> Dictionary:
	if _cache.has(sample_name):
		return _cache[sample_name]
	var recipe: Dictionary = RECIPES[sample_name]
	var out := {"name": sample_name}
	match str(recipe["kind"]):
		"wave":
			var cycle := int(recipe["cycle"])
			out["pcm"] = _wave(str(recipe["shape"]), float(recipe.get("duty", 0.5)), cycle)
			out["loop_start"] = 0
			out["loop_length"] = cycle
			out["c5"] = roundi(C5_HZ * cycle)
		"pad":
			out["pcm"] = _pad(str(recipe["shape"]))
			out["loop_start"] = 0
			out["loop_length"] = PAD_LOOP
			out["c5"] = roundi(C5_HZ * PAD_LOOP / (PAD_CYCLES + 0.5))
		"drum":
			var rate := int(recipe["rate"])
			out["pcm"] = _drum(sample_name, rate, float(recipe["seconds"]))
			out["loop_start"] = 0
			out["loop_length"] = 0
			out["c5"] = rate
	_cache[sample_name] = out
	return out


## The sample's BRR encoding: {data, loop}.
static func brr(sample_name: String) -> Dictionary:
	if _brr_cache.has(sample_name):
		return _brr_cache[sample_name]
	var sample := get_sample(sample_name)
	var encoded := {}
	var path := BRR_DIR + sample_name + ".brr"
	if FileAccess.file_exists(path):
		encoded = {"data": FileAccess.get_file_as_bytes(path), "loop": int(sample["loop_start"]) / 16 * SnesBrr.BLOCK_BYTES}
	else:
		encoded = encode(sample_name)
	_brr_cache[sample_name] = encoded
	return encoded


static func encode(sample_name: String) -> Dictionary:
	var sample := get_sample(sample_name)
	return SnesBrr.encode(sample["pcm"], int(sample["loop_start"]), int(sample["loop_length"]))


## The decoded sample as the DSP plays it: {pcm, loop}. The loop plays a
## second pass so the filters settle as they do on the console.
static func decoded(sample_name: String) -> Dictionary:
	var key := "dec:" + sample_name
	if _cache.has(key):
		return _cache[key]
	var encoded := brr(sample_name)
	var out := SnesBrr.decode(encoded["data"], int(encoded["loop"]), 1)
	_cache[key] = out
	return out


## smconv's pitch base for a sample: semitones from 8363 Hz, in 1/64ths.
static func pitch_base(sample_name: String) -> int:
	var c5 := float(get_sample(sample_name)["c5"])
	return int(floor(log(c5 / 8363.0) / log(2.0) * 768.0 + 0.5))


## Bytes of audio RAM the sample takes as BRR.
static func brr_size(sample_name: String) -> int:
	var sample := get_sample(sample_name)
	var length: int = (sample["pcm"] as PackedInt32Array).size()
	if int(sample["loop_length"]) > 0:
		length = int(sample["loop_start"]) + int(sample["loop_length"])
	return int(ceil(length / 16.0)) * SnesBrr.BLOCK_BYTES


static func _level(x: float) -> int:
	return clampi(roundi(x * 32767.0), -32768, 32767)


static func _shape(shape: String, phase: float, duty: float) -> float:
	match shape:
		"pulse":
			return 1.0 if phase < duty else -1.0
		"saw":
			return 1.0 - 2.0 * phase
		"soft_saw":
			# A saw with its top harmonics rolled off: rounder in the bass.
			var v := 0.0
			for k in range(1, 9):
				v += sin(TAU * k * phase) / k * (1.0 - (k - 1) / 9.0)
			return v * 0.6
		"triangle":
			return 4.0 * phase - 1.0 if phase < 0.5 else 3.0 - 4.0 * phase
		"sine":
			return sin(TAU * phase)
	return 0.0


static func _wave(shape: String, duty: float, cycle: int) -> PackedInt32Array:
	var pcm := PackedInt32Array()
	pcm.resize(cycle)
	for i in cycle:
		pcm[i] = _level(_shape(shape, float(i) / cycle, duty) * WAVE_LEVEL)
	return pcm


static func _pad(shape: String) -> PackedInt32Array:
	var pcm := PackedInt32Array()
	pcm.resize(PAD_LOOP)
	for i in PAD_LOOP:
		var a := fmod(float(i) * PAD_CYCLES / PAD_LOOP, 1.0)
		var b := fmod(float(i) * (PAD_CYCLES + 1) / PAD_LOOP, 1.0)
		var v := (_shape(shape, a, 0.5) + _shape(shape, b, 0.5)) * 0.5
		pcm[i] = _level(v * WAVE_LEVEL)
	return pcm


## Drum sounds: pitch-swept sines for the kick and tom, noise for the rest.
static func _drum(drum: String, rate: int, seconds: float) -> PackedInt32Array:
	var count := int(rate * seconds)
	count -= count % 16
	var pcm := PackedInt32Array()
	pcm.resize(count)
	var seed := 0x1234
	var phase := 0.0
	var last := 0.0
	var smooth := 0.0
	for i in count:
		var t := float(i) / rate
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
		var noise := float(seed >> 15) / 32768.0 * 2.0 - 1.0
		# High-passed noise for cymbals: the difference of neighbours.
		var bright := (noise - last) * 0.5
		last = noise
		smooth += (noise - smooth) * 0.35
		var v := 0.0
		match drum:
			"kick":
				var hz := 45.0 + 105.0 * exp(-t * 28.0)
				phase += hz / rate
				v = sin(TAU * phase) * exp(-t * 14.0) + noise * 0.15 * exp(-t * 300.0)
			"snare":
				phase += 190.0 / rate
				v = noise * 0.75 * exp(-t * 16.0) + sin(TAU * phase) * 0.5 * exp(-t * 30.0)
			"tom":
				var hz := 90.0 + 70.0 * exp(-t * 18.0)
				phase += hz / rate
				v = sin(TAU * phase) * exp(-t * 9.0) + smooth * 0.1 * exp(-t * 60.0)
			"hat":
				v = bright * exp(-t * 70.0)
			"open_hat":
				v = bright * exp(-t * 9.0)
			"crash":
				v = (bright * 0.7 + smooth * 0.3) * exp(-t * 4.5)
			"ride":
				phase += 3200.0 / rate
				v = (bright * 0.5 + sin(TAU * phase) * 0.25 + sin(TAU * phase * 1.48) * 0.2) * exp(-t * 7.0)
		# A short fade at the end, so the sample stops without a click.
		var tail := clampf((count - i) / (rate * 0.01), 0.0, 1.0)
		pcm[i] = _level(clampf(v * tail, -1.0, 1.0) * 0.8)
	return pcm
