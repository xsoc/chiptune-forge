class_name OplPatches
extends RefCounted
## The two-operator patches the AdLib and Sound Blaster arranger picks from.
##
## A patch is {name, fb, cnt, mod, car}: feedback (0 to 7) and connection
## (0 FM, 1 additive) for the channel, and the modulator's and carrier's
## settings, each {mult, tl, ar, dr, sl, rr, egt, ksr, ksl, ws, vib, am} in
## register units: tl is 0.75 dB per step (0 to 63), ar/dr/rr and sl are 0
## to 15, egt 1 holds the sustain while the key is down, ws picks the
## waveform. On the OPL3 [method for_opl3] swaps in its extra waveforms
## where they suit the sound better.


static func op(mult: int, tl: int, ar: int, dr: int, sl: int, rr: int, egt := 1, ws := 0, vib := 0, ksr := 0, ksl := 0) -> Dictionary:
	return {"mult": mult, "tl": tl, "ar": ar, "dr": dr, "sl": sl, "rr": rr, "egt": egt, "ksr": ksr, "ksl": ksl, "ws": ws, "vib": vib, "am": 0}


static func lead(wave: String) -> Dictionary:
	match wave:
		"saw":
			# Brass: a fed-back pair whose brightness swells in.
			return {"name": "Brass lead", "fb": 6, "cnt": 0, "mod": op(1, 22, 11, 2, 2, 6), "car": op(1, 0, 13, 1, 1, 6, 1, 0, 1)}
		"triangle", "sine":
			# Flute: nearly pure, with a breath of second harmonic.
			return {"name": "Flute lead", "fb": 1, "cnt": 0, "mod": op(2, 44, 12, 3, 3, 6), "car": op(1, 0, 12, 2, 1, 6, 1, 0, 1)}
		"wave":
			# Reed: odd harmonics from a 3:1 pair on a half sine.
			return {"name": "Reed lead", "fb": 3, "cnt": 0, "mod": op(3, 30, 14, 3, 2, 6, 1, 1), "car": op(1, 0, 14, 2, 1, 6, 1, 0, 1)}
	# Square-ish: a 2:1 pair gives the odd-heavy tone of a pulse.
	return {"name": "Square lead", "fb": 5, "cnt": 0, "mod": op(2, 28, 15, 4, 3, 6), "car": op(1, 0, 15, 2, 2, 6, 1, 0, 1)}


static func harmony(wave: String) -> Dictionary:
	if wave in ["triangle", "sine"]:
		return {"name": "Soft harmony", "fb": 1, "cnt": 0, "mod": op(1, 40, 13, 3, 3, 6), "car": op(1, 0, 13, 2, 2, 6)}
	return {"name": "Square harmony", "fb": 4, "cnt": 0, "mod": op(2, 34, 15, 4, 3, 6), "car": op(1, 0, 15, 2, 3, 6)}


static func arp(_wave: String) -> Dictionary:
	# A plucked bell: both operators decay, the 4:1 modulator faster.
	return {"name": "Pluck", "fb": 3, "cnt": 0, "mod": op(4, 30, 15, 7, 8, 7, 0), "car": op(1, 0, 15, 5, 6, 7, 0)}


static func pad() -> Dictionary:
	# Strings: slow bows, a little vibrato.
	return {"name": "Strings", "fb": 4, "cnt": 0, "mod": op(1, 30, 7, 2, 2, 5, 1, 0, 1), "car": op(1, 0, 6, 1, 1, 4, 1, 0, 1)}


static func bass(wave: String) -> Dictionary:
	if wave in ["triangle", "sine"]:
		return {"name": "Round bass", "fb": 2, "cnt": 0, "mod": op(1, 36, 15, 5, 4, 8), "car": op(1, 0, 15, 3, 3, 8)}
	return {"name": "Picked bass", "fb": 5, "cnt": 0, "mod": op(1, 24, 15, 5, 4, 8), "car": op(1, 0, 15, 3, 3, 8)}


## The rhythm mode's settings: the bass drum is a full pair on channel 7;
## the other four drums are one operator each.
static func bass_drum() -> Dictionary:
	return {"name": "Bass drum", "fb": 4, "cnt": 0, "mod": op(1, 18, 15, 8, 15, 8, 0), "car": op(1, 0, 15, 6, 15, 6, 0)}


static func hi_hat() -> Dictionary:
	return op(1, 0, 15, 8, 15, 8, 0)


static func snare() -> Dictionary:
	return op(1, 0, 15, 7, 15, 7, 0)


static func tom() -> Dictionary:
	return op(1, 0, 15, 6, 15, 6, 0)


static func cymbal() -> Dictionary:
	return op(1, 0, 15, 3, 15, 3, 0)


## [param patch] with the OPL3's extra waveforms where they help: a real
## square for square sounds and the derived square's buzz for brass.
static func for_opl3(patch: Dictionary) -> Dictionary:
	var out := patch.duplicate(true)
	match str(patch.get("name", "")):
		"Square lead", "Square harmony":
			out["car"]["ws"] = 6
			out["mod"]["tl"] = 46
		"Brass lead":
			out["mod"]["ws"] = 7
		"Picked bass":
			out["mod"]["ws"] = 5
	return out


## Register byte values of one operator: [$20, $40, $60, $80, $E0] given
## [param extra_tl] more attenuation.
static func op_bytes(o: Dictionary, extra_tl := 0) -> PackedInt32Array:
	return PackedInt32Array([
		(int(o.get("am", 0)) << 7) | (int(o.get("vib", 0)) << 6) | (int(o.get("egt", 1)) << 5) | (int(o.get("ksr", 0)) << 4) | (int(o.get("mult", 1)) & 15),
		((int(o.get("ksl", 0)) & 3) << 6) | clampi(int(o.get("tl", 0)) + extra_tl, 0, 63),
		((int(o.get("ar", 15)) & 15) << 4) | (int(o.get("dr", 0)) & 15),
		((int(o.get("sl", 0)) & 15) << 4) | (int(o.get("rr", 15)) & 15),
		int(o.get("ws", 0)) & 7,
	])
