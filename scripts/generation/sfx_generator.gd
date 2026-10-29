class_name SfxGenerator
extends RefCounted
## Rolls sound effects from presets, mutates them and applies the simple
## sliders. Every result is reproducible from its preset and seed.

## Simple sliders from the mockups, with their neutral values.
const TWEAK_DEFAULTS := {
	"pitch": 0.0, # -1 to 1
	"length": 1.0, # 0.25 to 2, a multiplier
	"slide": 0.0, # -1 to 1
	"punch": -1.0, # 0 to 1, or -1 to keep the preset's
	"wobble": 0.0, # 0 to 1
	"crunch": 0.0, # 0 to 1
	"steps": 0.0, # 0 to 1
	"echo": 0.0, # 0 to 1
}

## Parameters that [method mutate] may nudge, with how far.
const MUTABLE := {
	"base_freq": 0.06, "freq_ramp": 0.05, "freq_dramp": 0.02, "sustain": 0.04, "decay": 0.05,
	"punch": 0.05, "duty": 0.08, "duty_ramp": 0.03, "vib_strength": 0.04, "vib_speed": 0.04,
	"arp_mod": 0.05, "lpf_freq": 0.05, "hpf_freq": 0.03, "pha_offset": 0.05,
}

const SIGNED := ["freq_ramp", "freq_dramp", "duty_ramp", "arp_mod", "lpf_ramp", "hpf_ramp", "pha_offset", "pha_ramp"]


## Rolls one variation of [param preset]. Seed 0 gives the preset's base.
static func roll(preset: SfxPreset, seed_value: int) -> Dictionary:
	var params := preset.base.duplicate()
	if seed_value != 0:
		var ranges := preset.ranges.duplicate()
		var waves := preset.waves
		var variant := variant_index(preset, seed_value)
		if variant > 0:
			var v: Dictionary = preset.variants[variant - 1]
			params.merge(v.get("base", {}), true)
			ranges.merge(v.get("ranges", {}), true)
			if v.has("waves"):
				waves = PackedStringArray(v["waves"])
		var rng := Pcg32.for_stream(seed_value, "sfx:" + preset.id)
		_apply_ranges(params, ranges, rng)
		if waves.size() > 1:
			params["wave"] = waves[rng.range_int(0, waves.size() - 1)]
		params["noise_seed"] = rng.range_int(1, 0x7FFFFFFF)
	return _clamp_all(params)


## Which baseline [param seed_value] uses: 0 for the preset's base, or 1 and
## up for its [member SfxPreset.variants]. It has its own stream, so a seed
## that lands on the base sounds the same as before variants existed.
static func variant_index(preset: SfxPreset, seed_value: int) -> int:
	if seed_value == 0 or preset.variants.is_empty():
		return 0
	return Pcg32.for_stream(seed_value, "sfxv:" + preset.id).range_int(0, preset.variants.size())


## The name of the baseline [param seed_value] uses, such as "No arpeggio".
static func variant_name(preset: SfxPreset, seed_value: int) -> String:
	var variant := variant_index(preset, seed_value)
	return "Classic" if variant == 0 else str(preset.variants[variant - 1].get("name", "Variant %d" % variant))


static func roll_layer2(preset: SfxPreset, seed_value: int) -> Dictionary:
	if preset.layer2.is_empty():
		return {}
	var params := preset.layer2.duplicate()
	if seed_value != 0:
		_apply_ranges(params, preset.layer2_ranges, Pcg32.for_stream(seed_value, "sfx2:" + preset.id))
	return _clamp_all(params)


## A small random change to an existing sound ("Mutate a little").
static func mutate(params: Dictionary, seed_value: int, amount := 1.0) -> Dictionary:
	var rng := Pcg32.for_stream(seed_value, "mutate")
	var out := params.duplicate()
	var keys := MUTABLE.keys()
	keys.sort()
	for key in keys:
		if not out.has(key) and not ChipSfxSynth.DEFAULTS.has(key):
			continue
		if rng.chance(0.5):
			var current := float(out.get(key, ChipSfxSynth.DEFAULTS[key]))
			out[key] = current + rng.range_float(-1.0, 1.0) * float(MUTABLE[key]) * amount
	out["noise_seed"] = rng.range_int(1, 0x7FFFFFFF)
	return _clamp_all(out)


## Applies the simple sliders on top of rolled parameters.
static func apply_tweaks(params: Dictionary, tweaks: Dictionary) -> Dictionary:
	var t := TWEAK_DEFAULTS.duplicate()
	t.merge(tweaks, true)
	var full := ChipSfxSynth.with_defaults(params)
	var out := params.duplicate()
	out["base_freq"] = float(full["base_freq"]) + float(t["pitch"]) * 0.25
	if float(full["freq_limit"]) > 0.0:
		out["freq_limit"] = maxf(float(full["freq_limit"]) + float(t["pitch"]) * 0.2, 0.0)
	# Envelope stages are squared into time, so scale by the square root.
	var stretch := sqrt(clampf(float(t["length"]), 0.25, 2.0))
	for key in ["attack", "sustain", "decay"]:
		out[key] = float(full[key]) * stretch
	out["freq_ramp"] = float(full["freq_ramp"]) + float(t["slide"]) * 0.3
	if float(t["punch"]) >= 0.0:
		out["punch"] = float(t["punch"])
	if float(t["wobble"]) > 0.0:
		out["vib_strength"] = maxf(float(full["vib_strength"]), float(t["wobble"]) * 0.6)
		out["vib_speed"] = maxf(float(full["vib_speed"]), 0.3 + float(t["wobble"]) * 0.3)
	if float(t["crunch"]) > 0.0:
		out["crush"] = maxf(float(full["crush"]), float(t["crunch"]))
	if float(t["steps"]) > 0.0:
		out["arp_mod"] = 0.2 + float(t["steps"]) * 0.4 if float(full["arp_mod"]) >= 0.0 else float(full["arp_mod"])
		out["arp_speed"] = maxf(float(full["arp_speed"]), 0.55)
		out["repeat_speed"] = maxf(float(full["repeat_speed"]), float(t["steps"]) * 0.7)
	if float(t["echo"]) > 0.0:
		out["echo"] = maxf(float(full["echo"]), float(t["echo"]))
	return _clamp_all(out)


## Builds a [ChipSfx] for a preset, seed and slider set.
static func make_sfx(preset: SfxPreset, seed_value: int, tweaks := {}) -> ChipSfx:
	var params := apply_tweaks(roll(preset, seed_value), tweaks)
	var sfx := ChipSfx.from_params(params, preset.display_name, roll_layer2(preset, seed_value))
	sfx.data["meta"]["preset"] = preset.id
	sfx.data["meta"]["seed"] = seed_value
	sfx.data["meta"]["variant"] = variant_name(preset, seed_value)
	sfx.data["meta"]["license"] = SongGenerator.LICENSE.replace("music", "sound")
	return sfx


## C-style id for kits and console exports, such as "SFX_COIN_STREAK".
static func c_id(sound_name: String) -> String:
	var out := ""
	for c in sound_name.to_upper():
		out += c if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return "SFX_" + out.strip_edges().trim_prefix("_").trim_suffix("_")


static func _apply_ranges(params: Dictionary, ranges: Dictionary, rng: Pcg32) -> void:
	var keys := ranges.keys()
	keys.sort()
	for key in keys:
		var span: Array = ranges[key]
		var base := float(params.get(key, ChipSfxSynth.DEFAULTS.get(key, 0.0)))
		params[key] = base + rng.range_float(float(span[0]), float(span[1]))


static func _clamp_all(params: Dictionary) -> Dictionary:
	for key in params:
		if key == "wave" or key == "noise_seed" or key == "echo_delay":
			continue
		var lo := -1.0 if key in SIGNED else 0.0
		params[key] = snappedf(clampf(float(params[key]), lo, 1.0), 0.0001)
	return params
