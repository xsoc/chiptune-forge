class_name SoundDesigner
extends RefCounted
## Picks the instruments: wave, duty cycle, envelope, vibrato and echo for
## each channel, from the vibe's brightness, energy and weirdness and the
## style's preferred waves. Instrument indexes match [DrumWriter].


static func design(ctx: GenContext) -> void:
	var rng := ctx.rng("sound")
	var p := ctx.p
	var bright := float(p["brightness"])
	var energy := float(p["energy"])
	var weird := float(p["weirdness"])
	var legato := float(p["legato"])
	var echo := float(p["echo"])

	var lead_wave: String = p["lead_wave"]
	var lead_duty := 0.5
	if lead_wave == "":
		if energy < 0.3 and rng.chance(0.5):
			lead_wave = "triangle" if bright < 0.5 else "sine"
		else:
			lead_wave = "pulse"
	if lead_wave == "pulse":
		if bright > 0.7:
			lead_duty = 0.125 if rng.chance(0.35) else 0.25
		elif bright > 0.4:
			lead_duty = 0.25 if rng.chance(0.6) else 0.5
		else:
			lead_duty = 0.5
	var lead := {
		"name": "Lead",
		"wave": lead_wave,
		"duty": lead_duty,
		"attack": 0.004,
		"decay": snappedf(0.12 + legato * 0.2, 0.001),
		"sustain": snappedf(0.5 + legato * 0.3, 0.01),
		"release": snappedf(0.04 + legato * 0.12, 0.001),
		"vibrato_depth": snappedf(0.12 + weird * 0.45, 0.01),
		"vibrato_rate": snappedf(5.0 + rng.next_float() * 1.5, 0.1),
		"vibrato_delay": snappedf(0.15 + (1.0 - energy) * 0.15, 0.01),
		"glide": 0.04 if bool(p["lead_glide"]) else 0.0,
		"echo": snappedf(0.2 + echo * 0.5, 0.01),
		"volume": 0.5,
	}
	if weird > 0.6:
		lead["wave"] = "wave"
		lead["table"] = _random_table(rng)

	var harmony := {
		"name": "Harmony",
		"wave": "pulse",
		"duty": 0.125 if lead_duty != 0.125 else 0.25,
		"attack": 0.004,
		"decay": 0.15,
		"sustain": 0.55,
		"release": 0.08,
		"vibrato_depth": 0.1,
		"vibrato_rate": 5.0,
		"vibrato_delay": 0.25,
		"echo": snappedf(0.15 + echo * 0.4, 0.01),
		"volume": 0.3,
	}
	if ctx.choices.get("harmony", "") == "echo":
		harmony["duty"] = lead_duty
		harmony["wave"] = lead_wave if lead_wave != "wave" else "pulse"

	var chord_arp: bool = ctx.choices.get("arp", "") == "chord_arp"
	var arp := {
		"name": "Arp",
		"wave": "pulse",
		"duty": 0.125 if bright > 0.5 else 0.25,
		"attack": 0.002,
		"decay": 0.09,
		"sustain": 0.65 if chord_arp else 0.25,
		"release": 0.03,
		"arp_rate": 40.0 if energy > 0.5 else 30.0,
		"echo": snappedf(echo * 0.4, 0.01),
		"volume": 0.24,
	}

	var pad_wave := "triangle"
	if lead_wave == "saw" or p["style_name"] in ["Synthwave", "Trance", "Vaporwave", "Chillwave", "Synth Pop"]:
		pad_wave = "saw"
	elif bright > 0.55 and rng.chance(0.5):
		pad_wave = "pulse"
	var pad := {
		"name": "Pad",
		"wave": pad_wave,
		"duty": 0.5,
		"attack": snappedf(0.05 + (1.0 - energy) * 0.25, 0.001),
		"decay": 0.4,
		"sustain": 0.75,
		"release": 0.25,
		"vibrato_depth": 0.06,
		"vibrato_rate": 4.0,
		"vibrato_delay": 0.3,
		"echo": snappedf(echo * 0.3, 0.01),
		"volume": 0.17 if pad_wave == "saw" else 0.2,
	}
	if ctx.choices.get("pad", "") == "stabs":
		pad["attack"] = 0.002
		pad["decay"] = 0.08
		pad["sustain"] = 0.4
		pad["release"] = 0.04
		pad["wave"] = "pulse"
		pad["duty"] = 0.25

	var bass_wave: String = p["bass_wave"]
	var bass := {
		"name": "Bass",
		"wave": bass_wave,
		"duty": 0.5,
		"attack": 0.002,
		"decay": 0.15,
		"sustain": 0.7,
		"release": 0.03,
		"glide": 0.05 if ctx.choices.get("bass", "") in ["halftime"] else 0.0,
		"volume": {"triangle": 0.85, "sine": 0.8, "pulse": 0.42, "saw": 0.4}.get(bass_wave, 0.6),
	}

	var kick := {"name": "Kick", "wave": "triangle", "attack": 0.001, "decay": 0.14, "sustain": 0.0, "release": 0.02, "pitch_drop": 30.0, "pitch_drop_time": 0.025, "volume": 0.95}
	var snare := {"name": "Snare", "wave": "noise", "attack": 0.001, "decay": 0.13, "sustain": 0.0, "release": 0.02, "volume": 0.5}
	var hat := {"name": "Closed hat", "wave": "noise", "attack": 0.001, "decay": 0.03, "sustain": 0.0, "release": 0.01, "volume": 0.24}
	var open_hat := {"name": "Open hat", "wave": "noise", "attack": 0.001, "decay": 0.16, "sustain": 0.0, "release": 0.03, "volume": 0.2}
	var crash := {"name": "Crash", "wave": "noise", "attack": 0.001, "decay": 0.7, "sustain": 0.0, "release": 0.1, "volume": 0.26}
	var tom := {"name": "Tom", "wave": "triangle", "attack": 0.001, "decay": 0.2, "sustain": 0.0, "release": 0.03, "pitch_drop": 6.0, "pitch_drop_time": 0.08, "volume": 0.8}
	var ride := {"name": "Ride", "wave": "noise", "short": true, "attack": 0.001, "decay": 0.25, "sustain": 0.0, "release": 0.05, "volume": 0.16}

	ctx.instruments = [lead, harmony, arp, pad, bass, kick, snare, hat, open_hat, crash, tom, ride]


static func _random_table(rng: Pcg32) -> Array:
	# A random 4-bit wave that rises then falls, so it stays tonal. Integer
	# maths only, so the table is identical on every platform.
	var table: Array = []
	var v := 8
	for i in 32:
		var drift := rng.range_int(0, 3)
		v += drift if i < 16 else -drift
		v = clampi(v, 0, 15)
		table.append(v)
	return table
