class_name MelodyWriter
extends RefCounted
## Writes the lead melody.
##
## Melodies are built from motifs: a one-bar rhythm and contour that is
## repeated, varied and answered across a four-bar phrase, ending on a
## cadence. Pairs of phrases form a question-and-answer period, the first
## ending away from home and the second on the tonic. Strong beats land on
## chord tones. Each letter (A, B, C) gets one melody, reused wherever that
## section repeats, which is what makes a tune memorable rather than random.

const PHRASE_PLANS := [
	["a", "a2", "a", "c"],
	["a", "b", "a", "c"],
	["a", "a", "b", "c"],
	["a", "b", "a2", "c"],
	["a", "a2", "b", "c"],
]

## Cadence rhythms on a 16-step bar: [step, length] pairs, the last being the
## target note.
const CADENCE_RHYTHMS := [
	[[0, 4], [4, 4], [8, 8]],
	[[0, 2], [2, 2], [4, 12]],
	[[0, 12]],
	[[0, 6], [6, 2], [8, 6]],
	[[0, 3], [3, 3], [6, 2], [8, 8]],
]

## Register shift in semitones for each letter, so later sections lift.
const LETTER_SHIFT := {"A": 0, "B": 3, "C": -2, "D": 5}


static func write(ctx: GenContext) -> void:
	var rng := ctx.rng("melody", "Lead")
	ctx.melody_by_letter.clear()
	var base_energy := float(ctx.p["energy"])
	for i in ctx.sections.size():
		var section := ctx.sections[i]
		var letter: String = section["letter"]
		match section["kind"]:
			"main":
				if not ctx.melody_by_letter.has(letter):
					ctx.melody_by_letter[letter] = _compose(ctx, letter, int(section["bars"]), rng)
				# Quiet sections well below the song's energy leave the lead out,
				# so a build can start from the accompaniment.
				if float(section["energy"]) >= base_energy - 0.25 or ctx.sections.size() <= 2:
					for note in ctx.melody_by_letter[letter]:
						ctx.parts[i][GenContext.Channel.LEAD].append(note.duplicate())
			"outro":
				_outro(ctx, i, rng)
			"jingle":
				_jingle(ctx, i, rng)


static func _register(ctx: GenContext, letter: String) -> Vector2i:
	var center := 71 + int(roundf((float(ctx.p["brightness"]) - 0.5) * 10.0)) + int(LETTER_SHIFT.get(letter, 0))
	return Vector2i(center - 8, center + 9)


static func _compose(ctx: GenContext, letter: String, bars: int, rng: Pcg32) -> Array:
	var spb := ctx.steps_per_bar
	var reg := _register(ctx, letter)
	var pitches := MusicTheory.scale_pitches(ctx.key, ctx.mode, reg.x - 12, reg.y + 12)
	var density := float(ctx.p["melody_density"])
	var synco := float(ctx.p["syncopation"])
	var legato := float(ctx.p["legato"])
	var leapiness := clampf(float(ctx.p["energy"]) * 0.6 + float(ctx.p["complexity"]) * 0.4, 0.0, 1.0)
	var contour := float(ctx.p["contour"])
	var complexity := float(ctx.p["complexity"])

	var rhythm_a := _rhythm(rng, ctx, density, synco, legato)
	var rhythm_b := _rhythm(rng, ctx, density * 0.9, synco, legato)
	var contour_a := _contour(rng, rhythm_a.size(), contour, leapiness)
	var contour_b := _contour(rng, rhythm_b.size(), -contour * 0.5, leapiness)
	var plan: Array = PHRASE_PLANS[rng.range_int(0, PHRASE_PLANS.size() - 1)]
	var anchor := (reg.x + reg.y) / 2
	var anchor_b := anchor + rng.range_int(2, 5)
	var notes: Array = []
	var phrases := maxi(1, bars / 4)

	for bar in bars:
		var phrase := bar / 4
		var pos := bar % 4
		var kind: String = plan[pos]
		if bar == bars - 1:
			kind = "c"
		elif bars < 4 and pos == bars - 1:
			kind = "c"
		# The answering phrase of a period changes its third bar.
		if phrase % 2 == 1 and pos == 2:
			kind = "a2" if plan[2] == "b" else "b"
		var bar_start := bar * spb
		match kind:
			"a":
				_place(ctx, letter, notes, bar_start, rhythm_a, contour_a, anchor, pitches, reg, rng, false)
			"a2":
				_place(ctx, letter, notes, bar_start, rhythm_a, contour_a, anchor, pitches, reg, rng, true)
			"b":
				_place(ctx, letter, notes, bar_start, rhythm_b, contour_b, anchor_b, pitches, reg, rng, false)
			"c":
				var full := phrase % 2 == 1 or phrase == phrases - 1
				_cadence(ctx, letter, notes, bar_start, anchor, full, pitches, reg, rng)

	if complexity > 0.35:
		_ornament(ctx, notes, pitches, rng, (complexity - 0.35) * 0.6)
	return notes


## A one-bar rhythm: [step, length] pairs.
static func _rhythm(rng: Pcg32, ctx: GenContext, density: float, synco: float, legato: float) -> Array:
	var spb := ctx.steps_per_bar
	var spbeat := ctx.steps_per_beat
	var target := clampi(int(roundf(2.0 + density * 6.0 + rng.range_float(-1.0, 1.0))), 2, spb / 2 + 1)
	var weights: Array = []
	for step in spb:
		var w := 0.3 + synco * 1.2 * density
		if step % spbeat == 0:
			w = 4.0
		elif step % 2 == 0:
			w = 1.5 + synco * 2.0
		weights.append(w)
	weights[0] = 6.0
	var chosen: Array[int] = []
	if rng.chance(0.85):
		chosen.append(0)
		weights[0] = 0.0
	while chosen.size() < target:
		var step := rng.pick_index_weighted(weights)
		if weights[step] <= 0.0:
			break
		chosen.append(step)
		weights[step] = 0.0
	chosen.sort()
	var out: Array = []
	for j in chosen.size():
		var next := chosen[j + 1] if j + 1 < chosen.size() else spb
		var gap := next - chosen[j]
		var length := gap
		if not rng.chance(legato) and gap > 1:
			length = maxi(1, gap - maxi(1, gap / 3))
		if j == chosen.size() - 1 and gap > 4 and rng.chance(0.5):
			length = mini(length, 4)
		out.append([chosen[j], length])
	return out


## Scale-step moves between the notes of a motif. Big leaps are followed by a
## step back the other way, as singers do.
static func _contour(rng: Pcg32, count: int, bias: float, leapiness: float) -> Array:
	var deltas: Array = []
	var last := 0
	for j in maxi(count - 1, 0):
		var d := 0
		if absi(last) >= 3:
			d = -signi(last) * rng.range_int(1, 2)
		else:
			var r := rng.next_float()
			var magnitude := 1
			if r < 0.5:
				magnitude = 1
			elif r < 0.75:
				magnitude = 2
			elif r < 0.88 - leapiness * 0.1:
				magnitude = 0
			else:
				magnitude = rng.range_int(3, 5)
			var up := rng.chance(0.5 + bias * 0.3)
			d = magnitude if up else -magnitude
		deltas.append(d)
		last = d
	return deltas


static func _place(ctx: GenContext, letter: String, notes: Array, bar_start: int, rhythm: Array, contour: Array, anchor: int, pitches: PackedInt32Array, reg: Vector2i, rng: Pcg32, vary: bool) -> void:
	if rhythm.is_empty():
		return
	var first_chord := ctx.chord_at(letter, bar_start + int(rhythm[0][0]))
	var start_pitch := MusicTheory.nearest_in_classes(anchor, first_chord["pcs"])
	var idx := _index_of(pitches, start_pitch)
	var scale_len := MusicTheory.scale_of(ctx.mode).size()
	for j in rhythm.size():
		if j > 0:
			idx += int(contour[j - 1])
			if vary and j >= rhythm.size() - 2:
				idx += rng.range_int(-2, 2)
		# Fold back into the register by octaves.
		while idx >= pitches.size():
			idx -= scale_len
		while idx < 0:
			idx += scale_len
		while pitches[idx] > reg.y and idx - scale_len >= 0:
			idx -= scale_len
		while pitches[idx] < reg.x and idx + scale_len < pitches.size():
			idx += scale_len
		var pitch := pitches[idx]
		var step := bar_start + int(rhythm[j][0])
		if step % ctx.steps_per_beat == 0:
			var chord := ctx.chord_at(letter, step)
			pitch = MusicTheory.nearest_in_classes(pitch, chord["pcs"])
			idx = _index_of(pitches, pitch)
		notes.append([step, int(rhythm[j][1]), pitch, _velocity(ctx, step, rng)])


static func _cadence(ctx: GenContext, letter: String, notes: Array, bar_start: int, anchor: int, full: bool, pitches: PackedInt32Array, reg: Vector2i, rng: Pcg32) -> void:
	var chord := ctx.chord_at(letter, bar_start + ctx.steps_per_bar / 2)
	var target_pc := ctx.key
	if not full:
		var fifth := posmod(ctx.key + 7, 12)
		var second := posmod(ctx.key + MusicTheory.scale_of(ctx.mode)[1], 12)
		var pcs: PackedInt32Array = chord["pcs"]
		if pcs.has(fifth):
			target_pc = fifth
		elif pcs.has(second):
			target_pc = second
		else:
			target_pc = pcs[mini(1, pcs.size() - 1)]
	var target := MusicTheory.nearest_in_classes(anchor, PackedInt32Array([target_pc]))
	target = MusicTheory.fold(target, reg.x, reg.y + 2)
	var rhythm: Array = CADENCE_RHYTHMS[rng.range_int(0, CADENCE_RHYTHMS.size() - 1)]
	var scale := float(ctx.steps_per_bar) / 16.0
	var t_idx := _index_of(pitches, target)
	var from_above := rng.chance(0.5)
	for j in rhythm.size():
		var step := bar_start + int(roundf(int(rhythm[j][0]) * scale))
		var length := maxi(1, int(roundf(int(rhythm[j][1]) * scale)))
		var away := rhythm.size() - 1 - j
		var idx := t_idx + (away if from_above else -away)
		var pitch := pitches[clampi(idx, 0, pitches.size() - 1)] if away > 0 else target
		notes.append([step, length, pitch, _velocity(ctx, step, rng)])


static func _ornament(ctx: GenContext, notes: Array, pitches: PackedInt32Array, rng: Pcg32, amount: float) -> void:
	var extra: Array = []
	for note in notes:
		if int(note[1]) >= 4 and rng.chance(amount):
			var half := int(note[1]) / 2
			note[1] = half
			var idx := _index_of(pitches, int(note[2])) + (1 if rng.chance(0.5) else -1)
			var neighbour := pitches[clampi(idx, 0, pitches.size() - 1)]
			extra.append([int(note[0]) + half, half, neighbour, int(note[3]) - 12])
	notes.append_array(extra)


static func _outro(ctx: GenContext, section_index: int, rng: Pcg32) -> void:
	var section := ctx.sections[section_index]
	var steps := ctx.section_steps(section)
	var reg := _register(ctx, "A")
	var pitches := MusicTheory.scale_pitches(ctx.key, ctx.mode, reg.x - 12, reg.y + 12)
	var notes: Array = []
	var last_bar := steps - ctx.steps_per_bar
	if last_bar > 0:
		_cadence(ctx, "O", notes, last_bar - ctx.steps_per_bar, (reg.x + reg.y) / 2, false, pitches, reg, rng)
	var tonic := MusicTheory.nearest_in_classes((reg.x + reg.y) / 2, PackedInt32Array([ctx.key]))
	notes.append([maxi(last_bar, 0), ctx.steps_per_bar, tonic, 110])
	for note in notes:
		ctx.parts[section_index][GenContext.Channel.LEAD].append(note)


static func _jingle(ctx: GenContext, section_index: int, rng: Pcg32) -> void:
	var section := ctx.sections[section_index]
	var steps := ctx.section_steps(section)
	var reg := _register(ctx, "A")
	var root := MusicTheory.pitch_at_or_above(ctx.key, reg.x)
	var third := 3 if ctx.minor else 4
	var falling := float(ctx.p["contour"]) < -0.3
	var line := [root, root + third, root + 7, root + 12]
	if falling:
		line = [root + 12, root + 7, root + third, root]
	var unit := 2 if steps >= 16 else 1
	if rng.chance(0.3):
		line.insert(2, root + 5)
	var step := 0
	for pitch in line:
		ctx.add_note(section_index, GenContext.Channel.LEAD, step, unit, pitch, 104)
		step += unit
	ctx.add_note(section_index, GenContext.Channel.LEAD, step, maxi(steps - step, 2), line[line.size() - 1], 118)


static func _velocity(ctx: GenContext, step: int, rng: Pcg32) -> int:
	if step % ctx.steps_per_bar == 0:
		return 112
	if step % ctx.steps_per_beat == 0:
		return 102
	return 88 + rng.range_int(0, 8)


static func _index_of(pitches: PackedInt32Array, pitch: int) -> int:
	var best := 0
	var best_distance := 999
	for i in pitches.size():
		var distance := absi(pitches[i] - pitch)
		if distance < best_distance:
			best = i
			best_distance = distance
	return best
