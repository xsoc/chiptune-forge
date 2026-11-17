class_name SongSettings
extends RefCounted
## Everything the user picked on the Generate screen. With the seed, these
## settings always produce the same song.

## Song forms the user can pick. "auto" lets the style choose.
const FORMS: PackedStringArray = ["auto", "loop", "verse_chorus", "aaba", "rondo", "through", "build", "boss", "jingle", "custom"]
## Letters a custom structure is made of: intro, four main parts, outro.
const SECTION_LETTERS: PackedStringArray = ["I", "A", "B", "C", "D", "O"]
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
## Synth engine from [constant SynthEngines.CHOICES]: "chip" (the classic
## sound), "auto" (the style's engine), or an engine by name.
var engine := "chip"
## Engines for single layers, {layer: choice}, over [member engine].
var layer_engines: Dictionary = {}
## Bumped per layer by "Regenerate unlocked parts", so only those layers change.
var variations: Dictionary = {}
## Advanced: swing from 0 to 100, or -1 to take it from the vibe and style.
var swing := -1.0
## Advanced: how far velocities and note lengths wander, 0 to 100.
var humanise := 0.0
## Advanced: {layer: volume in percent, 0 to 150}. Missing layers are 100.
var layer_volumes: Dictionary = {}
## Advanced: {layer: one of [constant SWAPS]} replacing the layer's sound.
## Drums have none.
var instrument_swaps: Dictionary = {}

## The sections of a custom structure (form "custom"), in play order, from
## [constant SECTION_LETTERS].
var custom_form: Array = []
## "Regenerate" per section: {section name: count}.
var section_variations: Dictionary = {}
## Locks as the app last had them, {layers: [...], sections: [...]}, so
## projects and the library keep them. Generation takes locks as arguments.
var locks: Dictionary = {}
## Adaptive states, as the song stores them; empty means the defaults
## ([constant SongGenerator.STATES]). Set when the user edits a state.
var states: Array = []
## Transition rules; empty means [constant SongGenerator.TRANSITIONS].
var transitions: Array = []

## Instrument swaps: id to [wave, duty].
const SWAPS := {
	"pulse12": ["pulse", 0.125],
	"pulse25": ["pulse", 0.25],
	"square": ["pulse", 0.5],
	"triangle": ["triangle", 0.5],
	"saw": ["saw", 0.5],
	"sine": ["sine", 0.5],
}
const SWAP_NAMES := {
	"pulse12": "Thin pulse (12.5%)",
	"pulse25": "Pulse (25%)",
	"square": "Square",
	"triangle": "Triangle",
	"saw": "Saw",
	"sine": "Sine",
}


func get_seed() -> int:
	return Pcg32.seed_from_text(seed_text)


func get_variation(layer: String) -> int:
	return int(variations.get(layer, 0))


func to_dict() -> Dictionary:
	var dict := {
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
	# Left out when unset, so songs from before the engines are unchanged.
	if engine != "chip":
		dict["engine"] = engine
	if not layer_engines.is_empty():
		dict["layer_engines"] = layer_engines.duplicate()
	if swing >= 0.0:
		dict["swing"] = swing
	if humanise > 0.0:
		dict["humanise"] = humanise
	if not layer_volumes.is_empty():
		dict["layer_volumes"] = layer_volumes.duplicate()
	if not instrument_swaps.is_empty():
		dict["instrument_swaps"] = instrument_swaps.duplicate()
	if not custom_form.is_empty():
		dict["custom_form"] = custom_form.duplicate()
	if not section_variations.is_empty():
		dict["section_variations"] = section_variations.duplicate()
	if not locks.is_empty():
		dict["locks"] = locks.duplicate(true)
	if not states.is_empty():
		dict["states"] = states.duplicate(true)
	if not transitions.is_empty():
		dict["transitions"] = transitions.duplicate(true)
	return dict


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
	s.engine = str(dict.get("engine", "chip"))
	s.layer_engines = dict.get("layer_engines", {}).duplicate()
	s.swing = clampf(float(dict.get("swing", -1.0)), -1.0, 100.0)
	s.humanise = clampf(float(dict.get("humanise", 0.0)), 0.0, 100.0)
	s.layer_volumes = {}
	var volumes: Variant = dict.get("layer_volumes", {})
	if volumes is Dictionary:
		for layer in volumes:
			if LAYERS.has(str(layer)):
				s.layer_volumes[str(layer)] = clampf(float(volumes[layer]), 0.0, 150.0)
	s.instrument_swaps = {}
	var swaps: Variant = dict.get("instrument_swaps", {})
	if swaps is Dictionary:
		for layer in swaps:
			if LAYERS.has(str(layer)) and str(layer) != "Drums" and SWAPS.has(str(swaps[layer])):
				s.instrument_swaps[str(layer)] = str(swaps[layer])
	s.custom_form = clean_custom_form(dict.get("custom_form", [])) if dict.has("custom_form") else []
	s.section_variations = {}
	var section_vars: Variant = dict.get("section_variations", {})
	if section_vars is Dictionary:
		for key in section_vars:
			s.section_variations[str(key)] = maxi(int(section_vars[key]), 0)
	s.locks = {}
	var given_locks: Variant = dict.get("locks", {})
	if given_locks is Dictionary:
		for key in ["layers", "sections"]:
			if given_locks.get(key) is Array and not given_locks[key].is_empty():
				s.locks[key] = given_locks[key].map(func(v: Variant) -> String: return str(v))
	s.states = clean_states(dict.get("states", []))
	s.transitions = clean_transitions(dict.get("transitions", []))
	return s


## A usable custom structure: known letters, at most 32 sections, and at
## least one main section.
static func clean_custom_form(value: Variant) -> Array:
	var out: Array = []
	if value is Array or value is PackedStringArray:
		for letter in value:
			if SECTION_LETTERS.has(str(letter)) and out.size() < 32:
				out.append(str(letter))
	var has_main := false
	for letter in out:
		if letter != "I" and letter != "O":
			has_main = true
	if not has_main:
		out.insert(out.find("O") if out.has("O") else out.size(), "A")
	return out


## Valid states only: a unique non-empty name, an intensity from 0 to 1 and
## a level per known layer.
static func clean_states(value: Variant) -> Array:
	var out: Array = []
	var names := {}
	if not value is Array:
		return out
	for state in value:
		if not state is Dictionary:
			continue
		var name := str(state.get("name", "")).strip_edges()
		if name == "" or names.has(name.to_lower()):
			continue
		names[name.to_lower()] = true
		var levels := {}
		var given: Variant = state.get("levels", {})
		for layer in LAYERS:
			var level: Variant = given.get(layer, "full") if given is Dictionary else "full"
			if level is String and str(level) in ["off", "low", "mid", "full"]:
				levels[layer] = str(level)
			elif level is float or level is int:
				levels[layer] = clampf(float(level), 0.0, 1.0)
			else:
				levels[layer] = "full"
		out.append({"name": name, "min_intensity": clampf(float(state.get("min_intensity", 1.0)), 0.0, 1.0), "levels": levels})
	return out


## Valid transition rules only.
static func clean_transitions(value: Variant) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for rule in value:
		if not rule is Dictionary or str(rule.get("to", "")) == "":
			continue
		var clean := {
			"from": str(rule.get("from", "*")),
			"to": str(rule["to"]),
			"when": str(rule.get("when", "beat")) if SongGenerator.WHEN.has(str(rule.get("when", ""))) else "beat",
			"how": str(rule.get("how", "crossfade")) if SongGenerator.HOW.has(str(rule.get("how", ""))) else "crossfade",
		}
		if clean["how"] == "stinger":
			clean["stinger"] = str(rule.get("stinger", "rise")) if SongGenerator.STINGERS.has(str(rule.get("stinger", ""))) else "rise"
		out.append(clean)
	return out


func duplicate_settings() -> SongSettings:
	return SongSettings.from_dict(to_dict())
