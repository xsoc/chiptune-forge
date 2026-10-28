class_name PartWriter
extends RefCounted
## Writes the harmony line, arpeggio, pad and bass parts from the chords.

const ARP_TYPES: PackedStringArray = ["arp", "chord_arp", "broken"]
const PAD_TYPES: PackedStringArray = ["pad", "stabs"]
const HARMONY_TYPES: PackedStringArray = ["echo", "thirds", "counter"]
const BASS_TYPES: PackedStringArray = ["root_8ths", "octave", "root_fifth", "root_quarters", "arp"]
const ARP_SHAPES: PackedStringArray = ["up", "down", "updown", "random"]


static func write(ctx: GenContext) -> void:
	var pick_rng := ctx.rng("parts")
	var accompaniment: Dictionary = ctx.p["accompaniment"]
	var arp_weights := {}
	var pad_weights := {}
	for kind in accompaniment:
		if ARP_TYPES.has(kind):
			arp_weights[kind] = accompaniment[kind]
		elif PAD_TYPES.has(kind):
			pad_weights[kind] = accompaniment[kind]
	var arp_total := _sum(arp_weights)
	var pad_total := _sum(pad_weights)
	if arp_total + pad_total <= 0.0:
		pad_weights = {"pad": 1.0}
		pad_total = 1.0
	ctx.choices["arp"] = str(pick_rng.pick_weighted(arp_weights)) if arp_total > 0.0 else ""
	ctx.choices["pad"] = str(pick_rng.pick_weighted(pad_weights)) if pad_total > 0.0 else ""
	ctx.choices["arp_share"] = arp_total / (arp_total + pad_total)
	var harmony_parts: Dictionary = ctx.p["harmony_parts"]
	ctx.choices["harmony"] = str(pick_rng.pick_weighted(harmony_parts)) if not harmony_parts.is_empty() else "counter"
	var bass_patterns: Dictionary = ctx.p["bass_patterns"]
	ctx.choices["bass"] = str(pick_rng.pick_weighted(bass_patterns)) if not bass_patterns.is_empty() else "root_8ths"
	if float(ctx.p["tension"]) > 0.6 and pick_rng.chance(0.4):
		ctx.choices["bass"] = "pedal"
	ctx.choices["arp_shape"] = ["up", "down", "updown", "updown", "up", "random"][pick_rng.range_int(0, 5)]
	_vary_choice(ctx, "harmony", "Harmony", harmony_parts, HARMONY_TYPES)
	_vary_choice(ctx, "bass", "Bass", bass_patterns, BASS_TYPES)
	if ctx.choices["arp"] != "":
		_vary_choice(ctx, "arp", "Arp", arp_weights, ARP_TYPES)
		_vary_choice(ctx, "arp_shape", "Arp", {}, ARP_SHAPES)
	if ctx.choices["pad"] != "":
		_vary_choice(ctx, "pad", "Pad", pad_weights, PAD_TYPES)

	var harmony_rng := ctx.rng("harmony_line", "Harmony")
	var arp_rng := ctx.rng("arp", "Arp")
	var pad_rng := ctx.rng("pad", "Pad")
	var bass_rng := ctx.rng("bass", "Bass")
	for i in ctx.sections.size():
		var section := ctx.sections[i]
		var e := float(section["energy"])
		var kind: String = section["kind"]
		var has_lead: bool = not ctx.parts[i][GenContext.Channel.LEAD].is_empty()
		var arp_type: String = ctx.choices["arp"]
		var pad_type: String = ctx.choices["pad"]
		var arp_share: float = ctx.choices["arp_share"]

		if kind == "main" and has_lead:
			var harmony_type: String = ctx.choices["harmony"]
			if e >= 0.5 or (harmony_type == "echo" and e >= 0.35):
				_harmony_line(ctx, i, harmony_type, harmony_rng)

		var use_arp := arp_type != "" and (
			(kind == "main" and e >= 0.3) or (kind == "intro" and pad_type == "") or arp_share >= 0.99)
		var use_pad := pad_type != "" and (e <= 0.8 or arp_share <= 0.5 or kind != "main")
		if not use_arp and not use_pad:
			use_pad = pad_type != ""
			use_arp = not use_pad
		if kind == "jingle":
			use_arp = false
			use_pad = true
			pad_type = "pad"
		if use_arp:
			_arp(ctx, i, arp_type, e, arp_rng)
		if use_pad:
			_pad(ctx, i, "pad" if kind in ["intro", "outro"] else pad_type, e, pad_rng)
		if e >= 0.15 or kind in ["outro", "jingle"]:
			_bass(ctx, i, e, bass_rng)


## When a layer has been regenerated, swaps its part type for a different one,
## so a regenerated layer never comes back the same. Prefers the style's own
## types and falls back to [param fallback].
static func _vary_choice(ctx: GenContext, key: String, layer: String, weights: Dictionary, fallback: PackedStringArray) -> void:
	if ctx.settings.get_variation(layer) == 0:
		return
	var current: String = ctx.choices[key]
	var options := {}
	for kind in weights:
		if kind != current and float(weights[kind]) > 0.0:
			options[kind] = weights[kind]
	if options.is_empty():
		for kind in fallback:
			if kind != current:
				options[kind] = 1.0
	if not options.is_empty():
		ctx.choices[key] = str(ctx.rng("choice:" + key, layer).pick_weighted(options))


static func _sum(weights: Dictionary) -> float:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	return total


static func _harmony_line(ctx: GenContext, i: int, kind: String, rng: Pcg32) -> void:
	var letter: String = ctx.sections[i]["letter"]
	var steps := ctx.section_steps(ctx.sections[i])
	var lead: Array = ctx.parts[i][GenContext.Channel.LEAD]
	match kind:
		"echo":
			# The classic chip "fake echo": the lead again, a dotted eighth later.
			var delay := 3
			for note in lead:
				var step := int(note[0]) + delay
				if step < steps:
					ctx.add_note(i, GenContext.Channel.HARMONY, step, int(note[1]), int(note[2]), int(int(note[3]) * 0.55))
		"thirds":
			for note in lead:
				if int(note[1]) < 2:
					continue
				var chord := ctx.chord_at(letter, int(note[0]))
				var below := _chord_tone_below(int(note[2]) - 3, chord["pcs"])
				if int(note[2]) - below <= 9:
					ctx.add_note(i, GenContext.Channel.HARMONY, int(note[0]), int(note[1]), below, int(int(note[3]) * 0.8))
		_:
			# A slow counter-line of chord tones with smooth voice leading.
			var unit := ctx.steps_per_bar / 2 if ctx.beats_per_bar % 2 == 0 else ctx.steps_per_bar
			if float(ctx.sections[i]["energy"]) > 0.75:
				unit = ctx.steps_per_beat * (2 if ctx.beats_per_bar % 2 == 0 else 1)
			var current := 64
			var step := 0
			while step < steps:
				var chord := ctx.chord_at(letter, step)
				var options: Array = []
				for pc in chord["pcs"]:
					options.append(MusicTheory.nearest_in_classes(current, PackedInt32Array([pc])))
				options.sort_custom(func(a: int, b: int) -> bool: return absi(a - current) < absi(b - current))
				var pick: int = options[0]
				if options.size() > 1 and pick == current and rng.chance(0.6):
					pick = options[1]
				current = MusicTheory.fold(pick, 55, 74)
				ctx.add_note(i, GenContext.Channel.HARMONY, step, unit, current, 84)
				step += unit


static func _chord_tone_below(pitch: int, pcs: PackedInt32Array) -> int:
	for d in 12:
		if pcs.has(posmod(pitch - d, 12)):
			return pitch - d
	return pitch


static func _arp(ctx: GenContext, i: int, kind: String, e: float, rng: Pcg32) -> void:
	var letter: String = ctx.sections[i]["letter"]
	var shape: String = ctx.choices["arp_shape"]
	for chord in ctx.chords_by_letter.get(letter, []):
		var start: int = chord["start"]
		var length: int = chord["length"]
		var root := MusicTheory.pitch_at_or_above(int(chord["root"]), 60)
		var intervals: Array = MusicTheory.chord_intervals(chord["quality"])
		match kind:
			"chord_arp":
				# One channel plays the whole chord as a fast arpeggio.
				var offsets: Array = []
				for interval in intervals:
					offsets.append(int(interval) % 12 if int(interval) < 12 else int(interval) - 12)
				offsets.sort()
				var unit := 2 if e > 0.55 else ctx.steps_per_beat * 2
				var step := 0
				while step < length:
					var dur := mini(unit, length - step)
					var velocity := 92 if (start + step) % ctx.steps_per_beat == 0 else 76
					ctx.add_note(i, GenContext.Channel.ARP, start + step, maxi(dur - (1 if unit == 2 else 0), 1), root, velocity, -1, offsets)
					step += unit
			"broken":
				var low := MusicTheory.pitch_at_or_above(int(chord["root"]), 52)
				var third := low + int(intervals[1])
				var fifth := low + int(intervals[mini(2, intervals.size() - 1)])
				var figure := [low, fifth, third, fifth]
				var step := 0
				var n := 0
				while step < length:
					ctx.add_note(i, GenContext.Channel.ARP, start + step, 2, figure[n % 4], 80 if n % 4 == 0 else 68)
					step += 2
					n += 1
			_:
				var tones: Array = []
				for octave in [0, 12]:
					for interval in intervals:
						var pitch: int = root + int(interval) + int(octave)
						if pitch <= 86 and not tones.has(pitch):
							tones.append(pitch)
				tones.sort()
				var sequence: Array = tones.duplicate()
				match shape:
					"down":
						sequence.reverse()
					"updown":
						var back := tones.slice(1, tones.size() - 1)
						back.reverse()
						sequence.append_array(back)
				var unit := 1 if e > 0.55 else 2
				var step := 0
				var n := 0
				while step < length:
					var pitch: int = sequence[n % sequence.size()]
					if shape == "random":
						pitch = tones[rng.range_int(0, tones.size() - 1)]
					ctx.add_note(i, GenContext.Channel.ARP, start + step, unit, pitch, 84 if n % 4 == 0 else 70)
					step += unit
					n += 1


static func _pad(ctx: GenContext, i: int, kind: String, e: float, _rng: Pcg32) -> void:
	var letter: String = ctx.sections[i]["letter"]
	var previous: Array = [55, 60, 64]
	for chord in ctx.chords_by_letter.get(letter, []):
		var voicing := _voice_lead(previous, chord["pcs"])
		previous = voicing
		var start: int = chord["start"]
		var length: int = chord["length"]
		if kind == "stabs":
			var step := 0
			while step < length:
				var abs_step := start + step
				var beat_pos := abs_step % ctx.steps_per_beat
				var on := beat_pos == ctx.steps_per_beat / 2
				if ctx.beats_per_bar == 3:
					on = beat_pos == 0 and abs_step % ctx.steps_per_bar != 0
				if on:
					for pitch in voicing:
						ctx.add_note(i, GenContext.Channel.PAD, abs_step, 2 if ctx.beats_per_bar == 3 else 1, pitch + 5, 86)
				step += 1
		else:
			var velocity := 70 if e < 0.3 else 82
			for pitch in voicing:
				ctx.add_note(i, GenContext.Channel.PAD, start, length, pitch, velocity)


## Three-note voicing of [param pcs] that moves as little as possible from
## [param previous].
static func _voice_lead(previous: Array, pcs: PackedInt32Array) -> Array:
	var tones: Array = []
	for j in mini(3, pcs.size()):
		tones.append(pcs[j])
	if tones.size() == 2:
		tones.append(tones[0])
	var out: Array = []
	for j in tones.size():
		var target: int = previous[mini(j, previous.size() - 1)]
		var best := MusicTheory.nearest_in_classes(target, PackedInt32Array([tones[j]]))
		out.append(MusicTheory.fold(best, 50, 72))
	out.sort()
	return out


static func _bass(ctx: GenContext, i: int, e: float, rng: Pcg32) -> void:
	var section := ctx.sections[i]
	var letter: String = section["letter"]
	var chords: Array = ctx.chords_by_letter.get(letter, [])
	var kind: String = ctx.choices["bass"]
	if section["kind"] == "outro" or section["kind"] == "jingle":
		kind = "root_whole" if section["kind"] == "jingle" else "root_quarters"
	elif e < 0.3:
		kind = "root_whole"
	elif e < 0.45 and kind in ["root_8ths", "octave", "synco", "dnb"]:
		kind = "root_quarters"
	var beat := ctx.steps_per_beat
	for c in chords.size():
		var chord: Dictionary = chords[c]
		var start: int = chord["start"]
		var length: int = chord["length"]
		var root := MusicTheory.pitch_at_or_above(int(chord["root"]), 36)
		if section["kind"] == "outro" and c == chords.size() - 1:
			ctx.add_note(i, GenContext.Channel.BASS, start, length, root, 110)
			continue
		var intervals: Array = MusicTheory.chord_intervals(chord["quality"])
		var fifth := root + int(intervals[mini(2, intervals.size() - 1)])
		var next_root := root
		if c + 1 < chords.size():
			next_root = MusicTheory.pitch_at_or_above(int(chords[c + 1]["root"]), 36)
		match kind:
			"root_whole":
				ctx.add_note(i, GenContext.Channel.BASS, start, length, root, 100)
			"root_quarters":
				for step in range(0, length, beat):
					ctx.add_note(i, GenContext.Channel.BASS, start + step, beat - 1, root, 104 if step == 0 else 92)
			"root_8ths":
				for step in range(0, length, 2):
					ctx.add_note(i, GenContext.Channel.BASS, start + step, 2, root, 106 if step % beat == 0 else 88)
			"octave":
				for step in range(0, length, 2):
					var up := (step / 2) % 2 == 1
					ctx.add_note(i, GenContext.Channel.BASS, start + step, 2, root + (12 if up else 0), 100 if not up else 86)
			"root_fifth":
				for step in range(0, length, beat):
					var on_one := (start + step) % ctx.steps_per_bar == 0
					var pitch := root if ((start + step) / beat) % 2 == 0 else fifth - 12 if fifth - 12 >= 31 else fifth
					ctx.add_note(i, GenContext.Channel.BASS, start + step, beat - 1, pitch, 106 if on_one else 92)
			"walking":
				var scale := MusicTheory.scale_pitches(ctx.key, ctx.mode, 31, 55)
				var current := root
				for step in range(0, length, beat):
					var pitch := current
					if step == 0:
						pitch = root
					elif step + beat >= length:
						pitch = next_root + (1 if rng.chance(0.5) else -1)
					else:
						var options: Array = [root + int(intervals[1]), fifth, root + 12]
						for p in scale:
							if absi(p - current) <= 2 and p != current:
								options.append(p)
						pitch = options[rng.range_int(0, options.size() - 1)]
					current = pitch
					ctx.add_note(i, GenContext.Channel.BASS, start + step, beat, pitch, 96)
			"arp":
				var figure := [root, root + int(intervals[1]), fifth, root + 12]
				var n := 0
				for step in range(0, length, 2):
					ctx.add_note(i, GenContext.Channel.BASS, start + step, 2, figure[n % 4], 100 if n % 4 == 0 else 86)
					n += 1
			"synco":
				var hits := [[0, 3, 0], [3, 2, 0], [6, 2, 12], [10, 2, 0], [12, 2, 0], [14, 2, 12]]
				_bar_figure(ctx, i, start, length, root, hits)
			"reggae":
				var hits := [[0, 3, 0], [6, 2, 7], [8, 2, 0], [11, 3, 12]]
				_bar_figure(ctx, i, start, length, root, hits)
			"halftime":
				var hits := [[0, 6, 0], [7, 3, 0], [10, 6, -12]]
				_bar_figure(ctx, i, start, length, root, hits)
			"dnb":
				var hits := [[0, 6, 0], [10, 4, 0], [14, 2, 12]]
				_bar_figure(ctx, i, start, length, root, hits)
			"waltz":
				for step in range(0, length, ctx.steps_per_bar):
					ctx.add_note(i, GenContext.Channel.BASS, start + step, beat, root, 104)
			"pedal":
				var tonic := MusicTheory.pitch_at_or_above(ctx.key, 36)
				for step in range(0, length, 2):
					ctx.add_note(i, GenContext.Channel.BASS, start + step, 1, tonic, 100 if step % beat == 0 else 80)
			_:
				ctx.add_note(i, GenContext.Channel.BASS, start, length, root, 100)


## Repeats a one-bar figure of [step, length, interval] hits across a chord.
static func _bar_figure(ctx: GenContext, i: int, start: int, length: int, root: int, hits: Array) -> void:
	var scale := float(ctx.steps_per_bar) / 16.0
	var bar := 0
	while bar < length:
		for hit in hits:
			var step := bar + int(roundf(int(hit[0]) * scale))
			if step >= length:
				continue
			var dur := maxi(1, mini(int(roundf(int(hit[1]) * scale)), length - step))
			var pitch := maxi(root + int(hit[2]), 28)
			ctx.add_note(i, GenContext.Channel.BASS, start + step, dur, pitch, 104 if hit[0] == 0 else 90)
		bar += ctx.steps_per_bar
