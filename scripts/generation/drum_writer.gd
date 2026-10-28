class_name DrumWriter
extends RefCounted
## Writes the drum parts: kick and toms on the tonal drum channel, snare,
## hats and cymbals on the noise channel. Patterns come from [DrumBook];
## energy picks the variant, sections start with a crash and end with a fill.

const KICK := 5
const SNARE := 6
const HAT := 7
const OPEN_HAT := 8
const CRASH := 9
const TOM := 10
const RIDE := 11

const PITCH := {KICK: 36, SNARE: 74, HAT: 100, OPEN_HAT: 98, CRASH: 90, TOM: 50, RIDE: 96}
const LINE_INSTRUMENT := {"k": KICK, "s": SNARE, "h": HAT, "o": OPEN_HAT, "r": RIDE}


static func write(ctx: GenContext) -> void:
	var rng := ctx.rng("drums", "Drums")
	var family: String = ctx.p["drum_pattern"]
	if family == "none":
		return
	var spb := ctx.steps_per_bar
	var density := float(ctx.p["drum_density"])
	for i in ctx.sections.size():
		var section := ctx.sections[i]
		var e := float(section["energy"])
		var kind: String = section["kind"]
		var bars := int(section["bars"])
		match kind:
			"jingle":
				_jingle(ctx, i, rng)
				continue
			"outro":
				_hit(ctx, i, (bars - 1) * spb, KICK, 120)
				_hit(ctx, i, (bars - 1) * spb, CRASH, 110)
				if bars > 1:
					_bars(ctx, i, family, clampf(e - 0.2, 0.0, 1.0), density, 0, bars - 1, rng, false)
				continue
			"intro":
				if e < 0.25:
					continue
			_:
				if e < 0.2:
					continue
		var with_fill := kind == "main" and bars >= 2 and e >= 0.4
		_bars(ctx, i, family, e, density, 0, bars, rng, with_fill)
		if kind == "main" and e >= 0.5:
			_hit(ctx, i, 0, CRASH, 100)


static func _bars(ctx: GenContext, i: int, family: String, e: float, density: float, first_bar: int, last_bar: int, rng: Pcg32, with_fill: bool) -> void:
	var spb := ctx.steps_per_bar
	var level := clampf(e * 0.75 + density * 0.25, 0.0, 1.0)
	var lines := DrumBook.get_pattern(family, level, spb)
	var fill_len := 8 if e > 0.7 else 4
	for bar in range(first_bar, last_bar):
		var filling := with_fill and bar == last_bar - 1
		for key in lines:
			var line: String = lines[key]
			for step in spb:
				if filling and step >= spb - fill_len and key != "h":
					continue
				var c := line[step]
				if c == ".":
					continue
				var velocity := 100
				match c:
					"a":
						velocity = 120
					"g":
						velocity = 50
				# Small push on beats, so the groove breathes.
				if step % ctx.steps_per_beat != 0 and c == "x":
					velocity -= 10 + rng.range_int(0, 8)
				_hit(ctx, i, bar * spb + step, LINE_INSTRUMENT[key], velocity)
		if filling:
			_fill(ctx, i, bar * spb + spb - fill_len, fill_len, rng)


static func _fill(ctx: GenContext, i: int, start: int, length: int, rng: Pcg32) -> void:
	var toms := rng.chance(0.5)
	for n in length:
		var velocity := 70 + int(50.0 * n / maxf(length - 1, 1))
		if toms:
			var pitch := 55 - int(12.0 * n / length)
			ctx.add_note(i, GenContext.Channel.DRUMS, start + n, 1, pitch, velocity, TOM)
		elif n % 2 == 0 or n >= length - 4:
			_hit(ctx, i, start + n, SNARE, velocity)


static func _jingle(ctx: GenContext, i: int, _rng: Pcg32) -> void:
	var steps := ctx.section_steps(ctx.sections[i])
	var roll := mini(8, steps / 2)
	for n in roll:
		_hit(ctx, i, n, SNARE, 60 + n * 7)
	_hit(ctx, i, roll, KICK, 120)
	_hit(ctx, i, roll, CRASH, 115)


static func _hit(ctx: GenContext, i: int, step: int, instrument: int, velocity: int) -> void:
	var channel := GenContext.Channel.DRUMS if instrument == KICK or instrument == TOM else GenContext.Channel.NOISE
	ctx.add_note(i, channel, step, 1, PITCH[instrument], velocity, instrument)
