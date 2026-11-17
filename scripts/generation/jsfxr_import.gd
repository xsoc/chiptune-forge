class_name JsfxrImport
extends RefCounted
## Reads sound settings from jsfxr (https://sfxr.me, MIT licence) into the
## app's sfxr-style parameters. Takes any of:
## - jsfxr's JSON ("Copy" in jsfxr), with keys such as wave_type and
##   p_env_attack;
## - jsfxr's compact base58 string, as in a share link's #hash, or the link
##   itself;
## - the app's own parameter JSON, or a whole .chipsfx.

const ALPHABET := "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
## jsfxr's wave_type numbers.
const WAVES: PackedStringArray = ["square", "saw", "sine", "noise"]
## The p_ parameters in jsfxr's declaration order, which is the order of the
## base58 form, with the app's name for each.
const FIELDS := [
	["p_env_attack", "attack"], ["p_env_sustain", "sustain"], ["p_env_punch", "punch"], ["p_env_decay", "decay"],
	["p_base_freq", "base_freq"], ["p_freq_limit", "freq_limit"], ["p_freq_ramp", "freq_ramp"], ["p_freq_dramp", "freq_dramp"],
	["p_vib_strength", "vib_strength"], ["p_vib_speed", "vib_speed"],
	["p_arp_mod", "arp_mod"], ["p_arp_speed", "arp_speed"],
	["p_duty", "duty"], ["p_duty_ramp", "duty_ramp"],
	["p_repeat_speed", "repeat_speed"],
	["p_pha_offset", "pha_offset"], ["p_pha_ramp", "pha_ramp"],
	["p_lpf_freq", "lpf_freq"], ["p_lpf_ramp", "lpf_ramp"], ["p_lpf_resonance", "lpf_resonance"],
	["p_hpf_freq", "hpf_freq"], ["p_hpf_ramp", "hpf_ramp"],
]


## {"params": {...}} on success, or {"error": "..."}.
static func parse(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return {"error": "Paste jsfxr settings first."}
	if trimmed.begins_with("{"):
		var parsed: Variant = JSON.parse_string(trimmed)
		if not parsed is Dictionary:
			return {"error": "That JSON could not be read."}
		return from_dict(parsed)
	if trimmed.contains("#"):
		trimmed = trimmed.get_slice("#", trimmed.get_slice_count("#") - 1)
	var bytes := b58_decode(trimmed)
	if bytes.is_empty():
		return {"error": "That is not jsfxr JSON or a jsfxr share code."}
	return from_bytes(bytes)


## From jsfxr's JSON, the app's own parameters, or a .chipsfx object.
static func from_dict(dict: Dictionary) -> Dictionary:
	if dict.has("params") and dict["params"] is Dictionary:
		return {"params": _clamped(dict["params"])}
	if dict.has("wave_type") or dict.has("p_base_freq"):
		var params := {}
		var wave := int(dict.get("wave_type", 0))
		params["wave"] = WAVES[wave] if wave >= 0 and wave < WAVES.size() else "square"
		for field in FIELDS:
			if dict.has(field[0]):
				params[field[1]] = float(dict[field[0]])
		if dict.has("sound_vol"):
			params["volume"] = float(dict["sound_vol"])
		return {"params": _clamped(params)}
	if dict.has("base_freq") or dict.has("wave"):
		return {"params": _clamped(dict)}
	return {"error": "That JSON has no sound settings in it."}


## From jsfxr's packed form: the wave type byte, then each p_ field as a
## little-endian float32.
static func from_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != 1 + FIELDS.size() * 4:
		return {"error": "That share code is not one jsfxr writes (%d bytes)." % bytes.size()}
	var dict := {"wave_type": bytes[0]}
	for i in FIELDS.size():
		var value := bytes.decode_float(1 + i * 4)
		if is_nan(value) or is_inf(value) or absf(value) > 1.01:
			return {"error": "That share code does not hold jsfxr settings."}
		dict[FIELDS[i][0]] = value
	return from_dict(dict)


## Bitcoin-style base58, as jsfxr uses. Empty on a bad character.
static func b58_decode(text: String) -> PackedByteArray:
	var digits := PackedByteArray() # big-endian base-256 number
	for ch in text:
		var value := ALPHABET.find(ch)
		if value < 0:
			return PackedByteArray()
		var carry := value
		for i in range(digits.size() - 1, -1, -1):
			carry += digits[i] * 58
			digits[i] = carry & 0xff
			carry >>= 8
		while carry > 0:
			digits.insert(0, carry & 0xff)
			carry >>= 8
	var zeros := 0
	while zeros < text.length() and text[zeros] == "1":
		zeros += 1
	var out := PackedByteArray()
	out.resize(zeros)
	out.append_array(digits)
	return out


static func b58_encode(bytes: PackedByteArray) -> String:
	var digits: Array[int] = []
	for byte in bytes:
		var carry := byte
		for i in range(digits.size() - 1, -1, -1):
			carry += digits[i] << 8
			digits[i] = carry % 58
			carry /= 58
		while carry > 0:
			digits.insert(0, carry % 58)
			carry /= 58
	var text := ""
	for byte in bytes:
		if byte != 0:
			break
		text += "1"
	for d in digits:
		text += ALPHABET[d]
	return text


## jsfxr's packed form of [param params], for tests and sharing.
static func to_bytes(params: Dictionary) -> PackedByteArray:
	var full := ChipSfxSynth.with_defaults(params)
	var bytes := PackedByteArray([maxi(WAVES.find(str(full["wave"])), 0)])
	bytes.resize(1 + FIELDS.size() * 4)
	for i in FIELDS.size():
		bytes.encode_float(1 + i * 4, float(full[FIELDS[i][1]]))
	return bytes


static func _clamped(params: Dictionary) -> Dictionary:
	var out := {}
	for key in params:
		if not ChipSfxSynth.DEFAULTS.has(key):
			continue
		var value: Variant = params[key]
		if key == "wave":
			out[key] = str(value) if ChipSfxSynth.WAVES.has(str(value)) else "square"
		elif key == "noise_seed":
			out[key] = int(value)
		elif value is float or value is int:
			var signed: bool = key.ends_with("_ramp") or key in ["freq_dramp", "arp_mod", "pha_offset"]
			var lo := -1.0 if signed else 0.0
			out[key] = clampf(float(value), lo, 1.0)
	return out
