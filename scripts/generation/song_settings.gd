class_name SongSettings
extends RefCounted
## Everything the user picked on the Generate screen. With the seed, these
## settings always produce the same song.

## Song forms the user can pick. "auto" lets the style choose.
const FORMS: PackedStringArray = ["auto", "loop", "verse_chorus", "aaba", "rondo", "through", "build", "boss", "jingle"]
const ENERGY_CURVES: PackedStringArray = ["flat", "build", "wave", "peak_drop"]
## Layers in channel order, as in the mockups.
const LAYERS: PackedStringArray = ["Lead", "Harmony", "Arp", "Pad", "Bass", "Drums"]

## Up to three vibe ids, with a blend strength (0 to 100) for each.
var vibes: Array[String] = ["happy"]
var vibe_strengths: Array[float] = [100.0]
var style := "platformer"
var target := "modern"
var intensity := 60.0
var complexity := 50.0
## Beats per minute, or 0 to let the vibe and style pick.
var tempo := 0
## Pitch class 0 to 11, or -1 to let the vibe pick.
var key := -1
## Mode name from MusicTheory.SCALES, or "" to let the vibe pick.
var mode := ""
var length_seconds := 60.0
var form := "auto"
var energy_curve := "flat"
var intro := true
var outro := true
var loop := true
var seed_text := "1"
## Bumped per layer by "Regenerate unlocked parts", so only those layers change.
var variations: Dictionary = {}


func get_seed() -> int:
	return Pcg32.seed_from_text(seed_text)


func get_variation(layer: String) -> int:
	return int(variations.get(layer, 0))


func to_dict() -> Dictionary:
	return {
		"vibes": vibes.duplicate(),
		"vibe_strengths": vibe_strengths.duplicate(),
		"style": style,
		"target": target,
		"intensity": intensity,
		"complexity": complexity,
		"tempo": tempo,
		"key": key,
		"mode": mode,
		"length_seconds": length_seconds,
		"form": form,
		"energy_curve": energy_curve,
		"intro": intro,
		"outro": outro,
		"loop": loop,
		"seed": seed_text,
		"variations": variations.duplicate(),
	}


static func from_dict(dict: Dictionary) -> SongSettings:
	var s := SongSettings.new()
	s.vibes.clear()
	for v in dict.get("vibes", ["happy"]):
		s.vibes.append(str(v))
	s.vibe_strengths.clear()
	for v in dict.get("vibe_strengths", []):
		s.vibe_strengths.append(float(v))
	while s.vibe_strengths.size() < s.vibes.size():
		s.vibe_strengths.append(100.0)
	s.style = str(dict.get("style", s.style))
	s.target = str(dict.get("target", s.target))
	s.intensity = float(dict.get("intensity", s.intensity))
	s.complexity = float(dict.get("complexity", s.complexity))
	s.tempo = int(dict.get("tempo", s.tempo))
	s.key = int(dict.get("key", s.key))
	s.mode = str(dict.get("mode", s.mode))
	s.length_seconds = float(dict.get("length_seconds", s.length_seconds))
	s.form = str(dict.get("form", s.form))
	s.energy_curve = str(dict.get("energy_curve", s.energy_curve))
	s.intro = bool(dict.get("intro", s.intro))
	s.outro = bool(dict.get("outro", s.outro))
	s.loop = bool(dict.get("loop", s.loop))
	s.seed_text = str(dict.get("seed", s.seed_text))
	s.variations = dict.get("variations", {}).duplicate()
	return s


func duplicate_settings() -> SongSettings:
	return SongSettings.from_dict(to_dict())
