extends "res://tests/test_case.gd"
## Importing jsfxr settings.

## Made with jsfxr's packing (wave byte, then float32 little-endian p_ fields
## in its params_order, base58): a saw at start pitch 0.6.
const CODE := "4iUdYFPi2XwUfe1bfufg82a92Bi9JTvRLRnYqrx5ENvasqCyVkZb5WTNEUz8HztrL2gbCYAF8Z2sSvkwCTfnbitencR7cnekKpznokhiC75FN5ULwTZ81wE2b"


func test_share_code() -> void:
	var result := JsfxrImport.parse(CODE)
	check(not result.has("error"), str(result.get("error", "")))
	var p: Dictionary = result["params"]
	check_eq(p["wave"], "saw")
	check_near(p["attack"], 0.1, 0.0001)
	check_near(p["sustain"], 0.25, 0.0001)
	check_near(p["base_freq"], 0.6, 0.0001)
	check_near(p["freq_ramp"], -0.3, 0.0001)
	check_near(p["lpf_freq"], 0.8, 0.0001)
	check_near(p["hpf_freq"], 0.05, 0.0001)
	var link := JsfxrImport.parse("https://sfxr.me/#" + CODE)
	check_eq(link["params"], p, "a share link works too")


func test_round_trip() -> void:
	var params := {"wave": "noise", "base_freq": 0.2, "decay": 0.7, "pha_ramp": -0.5}
	var code := JsfxrImport.b58_encode(JsfxrImport.to_bytes(params))
	var back: Dictionary = JsfxrImport.parse(code)["params"]
	check_eq(back["wave"], "noise")
	check_near(back["decay"], 0.7, 0.0001)
	check_near(back["pha_ramp"], -0.5, 0.0001)
	check_eq(JsfxrImport.b58_encode(JsfxrImport.b58_decode(CODE)), CODE)


func test_json_forms() -> void:
	var jsfxr := JsfxrImport.parse('{"oldParams": true, "wave_type": 2, "p_env_decay": 0.3, "p_base_freq": 0.45, "p_freq_ramp": 2.0, "sound_vol": 0.25, "sample_rate": 44100}')
	check_eq(jsfxr["params"]["wave"], "sine")
	check_near(jsfxr["params"]["decay"], 0.3, 0.0001)
	check_eq(jsfxr["params"]["freq_ramp"], 1.0, "clamped")
	check_eq(jsfxr["params"]["volume"], 0.25)
	var own := JsfxrImport.parse('{"format": "chipforge-sfx", "version": 1, "params": {"wave": "triangle", "base_freq": 0.5, "bogus": 3}}')
	check_eq(own["params"], {"wave": "triangle", "base_freq": 0.5})


func test_bad_input() -> void:
	check(JsfxrImport.parse("").has("error"))
	check(JsfxrImport.parse("not0valid").has("error"), "0 is not base58")
	check(JsfxrImport.parse("abc").has("error"), "too short")
	check(JsfxrImport.parse("{\"x\": 1}").has("error"))
	check(JsfxrImport.parse("[1, 2]").has("error"))


func test_imported_sound_renders() -> void:
	var p: Dictionary = JsfxrImport.parse(CODE)["params"]
	var sfx := ChipSfx.from_params(ChipSfxSynth.with_defaults(p), "imported")
	check(sfx.render(22050).size() > 1000)
