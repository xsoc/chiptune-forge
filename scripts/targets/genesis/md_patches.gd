class_name MdPatches
extends RefCounted
## The YM2612 instrument patches the Mega Drive arranger picks from.
##
## Each patch is {name, alg, fb, ops}, with ops in Yamaha's operator order
## (1 to 4), each {mul, dt, tl, ks, ar, d1r, d2r, d1l, rr} in register units:
## mul 0 is half, dt 1 to 3 detune up and 5 to 7 down, tl is 0.75 dB per
## step, ar/d1r/d2r are 0 to 31, d1l and rr 0 to 15. Most use algorithm 4
## (two pairs of modulator into carrier), whose two pairs can be voiced a
## little apart for width; the modulators' own envelopes shape how the
## brightness moves.


static func op(mul: int, tl: int, ar: int, d1r: int, d2r: int, d1l: int, rr: int, dt := 0, ks := 0) -> Dictionary:
	return {"mul": mul, "dt": dt, "tl": tl, "ks": ks, "ar": ar, "d1r": d1r, "d2r": d2r, "d1l": d1l, "rr": rr}


## Silent operator, for patches that use fewer than four.
static func off() -> Dictionary:
	return op(1, 127, 31, 0, 0, 0, 15)


## Lead patches by the source lead's wave.
static func lead(wave: String) -> Dictionary:
	match wave:
		"saw":
			# Brass: a fed-back saw-like pair, brightness swelling in.
			return {"name": "Brass lead", "alg": 4, "fb": 6, "ops": [
				op(1, 24, 20, 4, 1, 2, 8),
				op(1, 8, 28, 3, 1, 1, 8, 0, 1),
				op(1, 30, 22, 5, 1, 3, 8, 3),
				op(1, 10, 28, 3, 1, 1, 8, 7, 1),
			]}
		"triangle", "sine":
			# Flute: nearly pure, with a breath of second harmonic.
			return {"name": "Flute lead", "alg": 4, "fb": 2, "ops": [
				op(2, 46, 24, 6, 0, 3, 7),
				op(1, 8, 24, 2, 0, 1, 7),
				op(1, 50, 24, 4, 0, 2, 7, 2),
				op(1, 12, 24, 2, 0, 1, 7, 6),
			]}
		"wave":
			# Hollow: odd harmonics from a 3:1 pair, like a clarinet.
			return {"name": "Reed lead", "alg": 4, "fb": 3, "ops": [
				op(3, 34, 26, 5, 1, 2, 8),
				op(1, 8, 28, 2, 0, 1, 8),
				op(1, 36, 26, 5, 1, 2, 8, 2),
				op(2, 14, 28, 2, 0, 1, 8, 6),
			]}
		_:
			# Square-ish: a 2:1 pair gives the odd-heavy tone of a pulse.
			return {"name": "Square lead", "alg": 4, "fb": 4, "ops": [
				op(2, 28, 31, 5, 1, 2, 8),
				op(1, 8, 31, 2, 0, 1, 8),
				op(1, 32, 31, 6, 1, 3, 8, 3),
				op(1, 12, 31, 2, 0, 1, 8, 7),
			]}


static func harmony(wave: String) -> Dictionary:
	if wave in ["triangle", "sine"]:
		# Soft organ: three sines an octave apart.
		return {"name": "Organ", "alg": 7, "fb": 0, "ops": [
			op(1, 22, 30, 0, 0, 0, 9),
			op(2, 26, 30, 0, 0, 0, 9),
			op(4, 34, 30, 0, 0, 0, 9),
			op(1, 30, 30, 0, 0, 0, 9, 3),
		]}
	# Soft square, a little under the lead.
	return {"name": "Soft square", "alg": 4, "fb": 2, "ops": [
		op(2, 34, 31, 6, 1, 3, 8),
		op(1, 10, 31, 2, 1, 1, 8),
		op(1, 38, 31, 6, 1, 3, 8, 2),
		op(1, 14, 31, 2, 1, 1, 8, 6),
	]}


static func arp(wave: String) -> Dictionary:
	if wave in ["triangle", "sine", "saw"]:
		# Electric piano: a high, fast-fading tine over a soft body.
		return {"name": "E-piano", "alg": 4, "fb": 0, "ops": [
			op(14, 42, 31, 16, 8, 15, 9),
			op(1, 8, 31, 6, 4, 4, 7),
			op(1, 30, 31, 9, 4, 5, 9),
			op(1, 10, 31, 6, 4, 3, 7, 3),
		]}
	# Pluck: bright on the attack, fading to a soft tone.
	return {"name": "Pluck", "alg": 4, "fb": 5, "ops": [
		op(3, 26, 31, 12, 6, 6, 10),
		op(1, 8, 31, 7, 5, 4, 8),
		op(1, 30, 31, 10, 6, 5, 10, 3),
		op(1, 12, 31, 7, 5, 4, 8, 7),
	]}


static func bass(wave: String) -> Dictionary:
	match wave:
		"saw":
			# Synth bass: fed-back saw with a filter-like decay.
			return {"name": "Synth bass", "alg": 4, "fb": 6, "ops": [
				op(1, 22, 31, 9, 3, 4, 12),
				op(1, 6, 31, 4, 2, 2, 10),
				op(2, 34, 31, 10, 4, 5, 12),
				op(1, 12, 31, 4, 2, 2, 10, 3),
			]}
		"pulse", "square":
			# Slap bass: a sharp, bright attack.
			return {"name": "Slap bass", "alg": 4, "fb": 5, "ops": [
				op(3, 24, 31, 14, 5, 8, 12),
				op(1, 6, 31, 5, 2, 2, 10),
				op(1, 30, 31, 12, 4, 6, 12, 3),
				op(1, 10, 31, 5, 2, 2, 10, 7),
			]}
		_:
			# Finger bass: round, with a little bite as the note starts.
			return {"name": "Finger bass", "alg": 4, "fb": 4, "ops": [
				op(1, 30, 31, 10, 3, 5, 12),
				op(1, 6, 31, 4, 2, 2, 10),
				op(1, 38, 31, 12, 4, 6, 12, 2),
				op(1, 10, 31, 4, 2, 2, 10, 6),
			]}


## Kick: a sine with a click, whose pitch the instrument drops.
static func kick() -> Dictionary:
	return {"name": "FM kick", "alg": 4, "fb": 0, "ops": [
		op(1, 24, 31, 20, 0, 15, 15),
		op(1, 0, 31, 9, 6, 3, 13),
		off(),
		off(),
	]}


## Snare body: a fed-back operator turns to noise, over a short tone.
static func snare() -> Dictionary:
	return {"name": "FM snare", "alg": 4, "fb": 7, "ops": [
		op(15, 0, 31, 12, 0, 15, 15),
		op(1, 6, 31, 14, 12, 6, 14),
		op(1, 127, 31, 0, 0, 0, 15),
		op(1, 10, 31, 16, 14, 15, 15),
	]}


static func tom() -> Dictionary:
	return {"name": "FM tom", "alg": 4, "fb": 0, "ops": [
		op(1, 30, 31, 16, 0, 15, 14),
		op(1, 2, 31, 7, 5, 3, 12),
		off(),
		off(),
	]}
