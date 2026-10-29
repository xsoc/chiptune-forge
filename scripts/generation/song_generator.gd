class_name SongGenerator
extends RefCounted
## Turns [SongSettings] into a [ChipSong].
##
## The pipeline runs in fixed stages, each with its own random stream:
## resolve parameters, form, harmony, melody, accompaniment, bass, drums,
## then sound design. The same settings and seed always give the same song.

## Bump when a change alters the output for existing seeds.
const ENGINE_VERSION := "1.1.0"
const LICENSE := "Generated with Chiptune Forge. You own this music and may use it for any purpose, including commercially, with no royalties or credit required."

## Most main sections a song can have. Enough for 15 minutes of 16-bar
## sections at the fastest tempo.
const MAX_SECTIONS := 64

const FORM_TEMPLATES := {
	"loop": ["A", "A"],
	"verse_chorus": ["A", "B", "A", "B"],
	"aaba": ["A", "A", "B", "A"],
	"rondo": ["A", "B", "A", "C", "A"],
	"through": ["A", "B", "C", "D"],
	"build": ["A", "A", "A", "B"],
	"boss": ["A", "B", "A", "C"],
}

const LAYER_CHANNELS := {
	"Lead": [GenContext.Channel.LEAD],
	"Harmony": [GenContext.Channel.HARMONY],
	"Arp": [GenContext.Channel.ARP],
	"Pad": [GenContext.Channel.PAD],
	"Bass": [GenContext.Channel.BASS],
	"Drums": [GenContext.Channel.DRUMS, GenContext.Channel.NOISE],
}

## Adaptive states from the mockups, with the intensity where each begins.
const STATES := [
	{"name": "Explore", "min_intensity": 0.0, "levels": {"Drums": "low", "Bass": "full", "Lead": "mid", "Harmony": "off", "Arp": "low", "Pad": "full"}},
	{"name": "Tension", "min_intensity": 0.3, "levels": {"Drums": "mid", "Bass": "full", "Lead": "off", "Harmony": "mid", "Arp": "full", "Pad": "mid"}},
	{"name": "Combat", "min_intensity": 0.6, "levels": {"Drums": "full", "Bass": "full", "Lead": "full", "Harmony": "full", "Arp": "full", "Pad": "low"}},
	{"name": "Boss", "min_intensity": 0.85, "levels": {"Drums": "full", "Bass": "full", "Lead": "full", "Harmony": "full", "Arp": "full", "Pad": "full"}},
]


## Generates a song. When [param previous] is given, layers named in
## [param locked] keep their notes from it, provided the form is unchanged.
static func generate(settings: SongSettings, catalog: Catalog = null, previous: ChipSong = null, locked: PackedStringArray = []) -> ChipSong:
	var ctx := GenContext.new()
	ctx.settings = settings
	ctx.catalog = catalog if catalog else Catalog.get_default()
	ctx.seed = settings.get_seed()
	resolve(ctx)
	build_form(ctx)
	build_harmony(ctx)
	ctx.parts.clear()
	for i in ctx.sections.size():
		var channels: Array = []
		for c in GenContext.CHANNEL_COUNT:
			channels.append([])
		ctx.parts.append(channels)
	MelodyWriter.write(ctx)
	PartWriter.write(ctx)
	DrumWriter.write(ctx)
	SoundDesigner.design(ctx)
	return assemble(ctx, previous, locked)


## Blends the vibes, style and sliders into one parameter set.
static func resolve(ctx: GenContext) -> void:
	var s := ctx.settings
	var rng := ctx.rng("resolve")
	var style: Style = ctx.catalog.get_style(s.style)
	if style == null:
		style = Style.new()
	var vibes: Array[Vibe] = []
	var weights: Array[float] = []
	for i in s.vibes.size():
		var vibe: Vibe = ctx.catalog.get_vibe(s.vibes[i])
		if vibe:
			vibes.append(vibe)
			weights.append(maxf(s.vibe_strengths[i] if i < s.vibe_strengths.size() else 100.0, 1.0))
	if vibes.is_empty():
		vibes.append(Vibe.new())
		weights.append(1.0)
	var total := 0.0
	for w in weights:
		total += w

	var p := {}
	for field in ["chord_colour", "bars_per_chord", "energy", "brightness", "tension", "weirdness", "contour", "legato", "swing", "echo"]:
		var value := 0.0
		for i in vibes.size():
			value += float(vibes[i].get(field)) * weights[i] / total
		p[field] = value
	var mode_weights := {}
	var prog_weights := {}
	var vmin := 0.0
	var vmax := 0.0
	for i in vibes.size():
		var w := weights[i] / total
		for m in vibes[i].mode_weights:
			mode_weights[m] = mode_weights.get(m, 0.0) + float(vibes[i].mode_weights[m]) * w
		for f in vibes[i].progression_weights:
			prog_weights[f] = prog_weights.get(f, 0.0) + float(vibes[i].progression_weights[f]) * w
		vmin += vibes[i].tempo_min * w
		vmax += vibes[i].tempo_max * w
	for m in style.mode_bias:
		mode_weights[m] = mode_weights.get(m, 0.0) + float(style.mode_bias[m]) * 0.5
	for f in style.progression_weights:
		prog_weights[f] = prog_weights.get(f, 0.0) + float(style.progression_weights[f])

	var intensity := clampf(s.intensity / 100.0, 0.0, 1.0)
	var complexity := clampf(s.complexity / 100.0, 0.0, 1.0)
	p["intensity"] = intensity
	p["complexity"] = complexity
	p["energy"] = clampf(float(p["energy"]) * 0.5 + intensity * 0.5, 0.0, 1.0)
	p["swing"] = maxf(float(p["swing"]), style.swing)
	p["chord_colour"] = clampf(float(p["chord_colour"]) + style.chord_colour + complexity * 0.15, 0.0, 1.0)
	p["melody_density"] = clampf(style.melody_density * 0.6 + float(p["energy"]) * 0.3 + complexity * 0.2 - 0.05, 0.05, 1.0)
	p["syncopation"] = clampf(style.syncopation + complexity * 0.2, 0.0, 1.0)
	p["drum_density"] = style.drum_density
	p["drum_pattern"] = style.drum_pattern
	p["bass_patterns"] = style.bass_patterns
	p["accompaniment"] = style.accompaniment
	p["harmony_parts"] = style.harmony_parts
	p["lead_wave"] = style.lead_wave
	p["bass_wave"] = style.bass_wave
	p["lead_glide"] = style.lead_glide
	p["progression_weights"] = prog_weights
	p["style_name"] = style.display_name
	p["vibe_name"] = vibes[0].display_name
	ctx.p = p

	# Tempo: where the vibe's and style's ranges overlap, pushed up by intensity.
	var lo := maxf(vmin, style.tempo_min)
	var hi := minf(vmax, style.tempo_max)
	if lo > hi:
		var mid := (vmin + vmax) * 0.25 + (style.tempo_min + style.tempo_max) * 0.25
		lo = mid - 6.0
		hi = mid + 6.0
	var t := clampf(rng.next_float() * 0.5 + intensity * 0.5, 0.0, 1.0)
	ctx.tempo = s.tempo if s.tempo > 0 else int(roundf(lerpf(lo, hi, t)))
	ctx.tempo = clampi(ctx.tempo, 40, 240)

	ctx.beats_per_bar = style.beats_per_bar
	for vibe in vibes:
		if vibe.beats_per_bar > 0 and weights[vibes.find(vibe)] / total >= 0.5:
			ctx.beats_per_bar = vibe.beats_per_bar
	ctx.steps_per_bar = ctx.beats_per_bar * ctx.steps_per_beat

	var mode_pick: Variant = rng.pick_weighted(mode_weights) if not mode_weights.is_empty() else "major"
	ctx.mode = s.mode if MusicTheory.SCALES.has(s.mode) else str(mode_pick)
	ctx.minor = MusicTheory.is_minor_mode(ctx.mode)
	# Mix the vibe and style into the key, so one seed does not put every
	# combination in the same key. Sliders do not affect it.
	var key_roll := rng.range_int(0, 11) + Pcg32.hash_text(s.style + "|" + ",".join(PackedStringArray(s.vibes)))
	ctx.key = posmod(s.key, 12) if s.key >= 0 else key_roll % 12

	var form_hint := ""
	for vibe in vibes:
		if vibe.form_hint != "" and form_hint == "":
			form_hint = vibe.form_hint
	var form_pick: Variant = rng.pick_weighted(style.forms) if not style.forms.is_empty() else "verse_chorus"
	if s.form != "auto":
		ctx.form = s.form
	elif form_hint != "":
		ctx.form = form_hint
	else:
		ctx.form = str(form_pick)
	ctx.loop = s.loop and ctx.form != "jingle"


## Picks the song form and section lengths that fit the requested length.
static func build_form(ctx: GenContext) -> void:
	var s := ctx.settings
	var bar_seconds := ctx.beats_per_bar * 60.0 / ctx.tempo
	var energy := float(ctx.p["energy"])
	ctx.sections.clear()
	ctx.order.clear()

	if ctx.form == "jingle":
		var bars := clampi(int(roundf(minf(s.length_seconds, 8.0) / bar_seconds)), 1, 4)
		ctx.sections.append({"name": "Jingle", "letter": "J", "kind": "jingle", "bars": bars, "energy": maxf(energy, 0.6)})
		ctx.order.append(0)
		return

	var total_bars := maxi(4, int(roundf(s.length_seconds / bar_seconds)))
	var intro_bars := 0
	var outro_bars := 0
	if s.intro:
		intro_bars = 4 if total_bars >= 40 else 2
	if s.outro:
		outro_bars = 4 if total_bars >= 40 else 2
	var body_bars := maxi(total_bars - intro_bars - outro_bars, 4)
	var template: Array = FORM_TEMPLATES.get(ctx.form, FORM_TEMPLATES["verse_chorus"]).duplicate()
	var max_sections := maxi(1, body_bars / 4)
	if template.size() > max_sections:
		template = template.slice(0, max_sections)
	var section_bars := clampi(int(roundf(body_bars / float(template.size()) / 4.0)) * 4, 4, 16)
	# Long songs repeat the form rather than stretching sections past 16 bars,
	# then add the start of the form again to get close to the asked length.
	var base := template.duplicate()
	while (template.size() + base.size()) * section_bars <= body_bars + section_bars / 2 and template.size() + base.size() <= MAX_SECTIONS:
		template.append_array(base)
	var extra := 0
	while (template.size() + 1) * section_bars <= body_bars + section_bars / 2 and template.size() < MAX_SECTIONS:
		template.append(base[extra % base.size()])
		extra += 1

	var curve := s.energy_curve
	var count := template.size()
	var plan: Array = []
	for i in count:
		var letter: String = template[i]
		var e := energy
		var progress := float(i) / maxf(count - 1, 1)
		match curve:
			"build":
				e = lerpf(energy - 0.35, energy + 0.15, progress)
			"wave":
				e = energy + (0.15 if i % 2 == 1 else -0.15)
			"peak_drop":
				e = energy + 0.2 * sin(progress * PI * 0.85) - (0.3 if i == count - 1 and count > 2 else 0.0)
			_:
				if letter != "A":
					e += 0.1
		if ctx.form == "build":
			e = lerpf(energy - 0.4, energy + 0.15, progress)
		elif ctx.form == "boss" and letter == "C":
			e += 0.2
		plan.append([letter, clampf(e, 0.05, 1.0)])

	if intro_bars > 0:
		_add_section(ctx, "Intro", "I", "intro", intro_bars, clampf(energy - 0.3, 0.05, 1.0))
	for entry in plan:
		var letter: String = entry[0]
		var e: float = snappedf(entry[1], 0.1)
		_add_section(ctx, letter, letter, "main", section_bars, e)
	if outro_bars > 0:
		_add_section(ctx, "Outro", "O", "outro", outro_bars, clampf(energy - 0.15, 0.05, 1.0))


static func _add_section(ctx: GenContext, base_name: String, letter: String, kind: String, bars: int, energy: float) -> void:
	# Reuse a section with the same letter and energy, so repeats share patterns.
	var variant := 1
	for i in ctx.sections.size():
		var existing := ctx.sections[i]
		if existing["letter"] == letter and existing["kind"] == kind:
			if absf(float(existing["energy"]) - energy) < 0.05:
				ctx.order.append(i)
				return
			variant += 1
	var section_name := base_name if variant == 1 else "%s%d" % [base_name, variant]
	ctx.sections.append({"name": section_name, "letter": letter, "kind": kind, "bars": bars, "energy": energy})
	ctx.order.append(ctx.sections.size() - 1)


## Writes the chord progression for each letter.
static func build_harmony(ctx: GenContext) -> void:
	var rng := ctx.rng("harmony")
	ctx.chords_by_letter.clear()
	var families: Dictionary = ctx.p["progression_weights"]
	if families.is_empty():
		families = {"pop": 1.0}
	var bars_per_chord := float(ctx.p["bars_per_chord"])
	var used: Array = []
	var letters: Array[String] = []
	var bars_by_letter := {}
	for section in ctx.sections:
		if not letters.has(section["letter"]):
			letters.append(section["letter"])
			bars_by_letter[section["letter"]] = section["bars"]

	var a_progression: Array = []
	for letter in letters:
		var bars: int = bars_by_letter[letter]
		var progression: Array
		match letter:
			"I":
				continue
			"O", "J":
				progression = ProgressionBook.pick("cadence", ctx.minor, rng)
			_:
				var family := str(rng.pick_weighted(families))
				progression = ProgressionBook.pick(family, ctx.minor, rng)
				for attempt in 4:
					if not used.has(progression):
						break
					progression = ProgressionBook.pick(family, ctx.minor, rng)
				used.append(progression)
				if letter == "A":
					a_progression = progression
		var chord_bars := bars_per_chord
		if letter in ["O", "J"]:
			chord_bars = maxf(bars / 4.0, 0.5)
		var chord_steps := maxi(int(chord_bars * ctx.steps_per_bar), ctx.steps_per_beat * 2)
		var total := bars * ctx.steps_per_bar
		# Keep at least two chords in a section.
		while total / chord_steps < 2 and chord_steps > ctx.steps_per_beat * 2:
			chord_steps /= 2
		ctx.chords_by_letter[letter] = _lay_chords(ctx, progression, chord_steps, total, rng, letter in ["O", "J"])

	if letters.has("I"):
		var intro_bars: int = bars_by_letter["I"]
		var intro_prog := a_progression if not a_progression.is_empty() else ProgressionBook.pick("pop", ctx.minor, rng)
		var chord_steps := maxi(intro_bars * ctx.steps_per_bar / 2, ctx.steps_per_beat * 2)
		ctx.chords_by_letter["I"] = _lay_chords(ctx, intro_prog, chord_steps, intro_bars * ctx.steps_per_bar, rng, false)


static func _lay_chords(ctx: GenContext, progression: Array, chord_steps: int, total: int, rng: Pcg32, is_cadence: bool) -> Array:
	var chords: Array = []
	var colour := float(ctx.p["chord_colour"])
	var step := 0
	var i := 0
	var count := maxi(total / chord_steps, 1)
	while step < total:
		var numeral: String = progression[i % progression.size()]
		if is_cadence:
			# Squeeze the cadence so it ends on the tonic in the last slot.
			var from_end := count - 1 - i
			numeral = progression[maxi(progression.size() - 1 - from_end, 0)]
		var parsed := MusicTheory.parse_numeral(numeral)
		var quality: String = parsed["quality"]
		if quality in ["maj", "min"] and rng.chance(colour * 0.6):
			quality = MusicTheory.colour_chord(quality, rng)
		var root := posmod(ctx.key + int(parsed["root"]), 12)
		var length := mini(chord_steps, total - step)
		chords.append({
			"start": step,
			"length": length,
			"root": root,
			"quality": quality,
			"pcs": MusicTheory.chord_pitch_classes(root, quality),
			"numeral": numeral,
		})
		step += length
		i += 1
	return chords


## Builds the final song dictionary: deduplicated patterns, sections, order,
## layers, states and cues.
static func assemble(ctx: GenContext, previous: ChipSong, locked: PackedStringArray) -> ChipSong:
	var reuse := previous != null and not locked.is_empty() and _same_form(ctx, previous)
	var patterns: Array = []
	var pattern_index := {}
	var sections: Array = []
	for i in ctx.sections.size():
		var section := ctx.sections[i]
		var ids: Array = []
		for c in GenContext.CHANNEL_COUNT:
			var notes: Array = ctx.parts[i][c]
			if reuse and _layer_of_channel(c) in locked:
				notes = _previous_notes(previous, i, c)
			notes.sort_custom(func(a: Array, b: Array) -> bool:
				return a[0] < b[0] if a[0] != b[0] else a[2] < b[2])
			if notes.is_empty():
				ids.append(-1)
				continue
			var key := JSON.stringify(notes)
			if not pattern_index.has(key):
				pattern_index[key] = patterns.size()
				patterns.append({"notes": notes})
			ids.append(pattern_index[key])
		sections.append({
			"name": section["name"],
			"length": ctx.section_steps(section),
			"patterns": ids,
			"energy": snappedf(float(section["energy"]), 0.01),
			"chords": _chord_names(ctx, section["letter"]),
		})

	var cues: Array = []
	var step := 0
	var loop_start := 0
	var loop_end := 0
	var seen_main := false
	for index in ctx.order:
		var section: Dictionary = ctx.sections[index]
		cues.append({"name": "section:%s" % section["name"], "step": step})
		if section["kind"] == "main" and not seen_main:
			loop_start = step
			seen_main = true
		if section["kind"] != "outro":
			loop_end = step + ctx.section_steps(section)
		step += ctx.section_steps(section)
	if not seen_main:
		loop_end = step
	cues.append({"name": "loop_start", "step": loop_start})
	cues.append({"name": "loop_end", "step": loop_end})

	var channels: Array = []
	for c in GenContext.CHANNEL_COUNT:
		channels.append({
			"name": GenContext.CHANNEL_NAMES[c],
			"instrument": c,
			"layer": _layer_of_channel(c),
			"volume": 1.0,
			"pan": [0.0, -0.35, 0.3, -0.15, 0.0, 0.0, 0.1][c],
			"polyphony": 3 if c == GenContext.Channel.PAD else (2 if c == GenContext.Channel.NOISE else 1),
		})
	var layers: Array = []
	for layer_name in SongSettings.LAYERS:
		layers.append({"name": layer_name, "channels": LAYER_CHANNELS[layer_name]})

	var s := ctx.settings
	var title := "%s %s" % [ctx.p["vibe_name"], ctx.p["style_name"]]
	var data := {
		"format": ChipSong.FORMAT,
		"version": ChipSong.VERSION,
		"meta": {
			"title": title.strip_edges(),
			"engine_version": ENGINE_VERSION,
			"seed": s.seed_text,
			"settings": s.to_dict(),
			"key": MusicTheory.key_name(ctx.key, ctx.mode),
			"form": ctx.form,
			"target": s.target,
			"license": LICENSE,
		},
		"timing": {
			"bpm": ctx.tempo,
			"beats_per_bar": ctx.beats_per_bar,
			"steps_per_beat": ctx.steps_per_beat,
			"swing": snappedf(float(ctx.p["swing"]), 0.01),
			"loop": ctx.loop,
			"loop_start": loop_start,
			"loop_end": loop_end,
		},
		"effects": {
			"echo": snappedf(clampf(float(ctx.p["echo"]) * 0.6, 0.0, 0.6), 0.01),
			"echo_feedback": 0.35,
			"echo_beats": 0.75,
		},
		"instruments": ctx.instruments,
		"channels": channels,
		"patterns": patterns,
		"sections": sections,
		"order": ctx.order.duplicate(),
		"layers": layers,
		"states": STATES.duplicate(true),
		"cues": cues,
	}
	var song := ChipSong.new()
	song.data = data
	return song


static func _layer_of_channel(channel: int) -> String:
	for layer_name in LAYER_CHANNELS:
		if LAYER_CHANNELS[layer_name].has(channel):
			return layer_name
	return ""


static func _chord_names(ctx: GenContext, letter: String) -> Array:
	var names: Array = []
	for chord in ctx.chords_by_letter.get(letter, []):
		names.append([chord["start"], chord["numeral"]])
	return names


static func _same_form(ctx: GenContext, previous: ChipSong) -> bool:
	var prev_sections: Array = previous.data.get("sections", [])
	var prev_order: Array = previous.data.get("order", [])
	if prev_sections.size() != ctx.sections.size() or prev_order.size() != ctx.order.size():
		return false
	for i in prev_order.size():
		if int(prev_order[i]) != ctx.order[i]:
			return false
	for i in ctx.sections.size():
		if int(prev_sections[i].get("length", 0)) != ctx.section_steps(ctx.sections[i]):
			return false
	return true


static func _previous_notes(previous: ChipSong, section_index: int, channel: int) -> Array:
	var ids: Array = previous.data["sections"][section_index].get("patterns", [])
	if channel >= ids.size() or int(ids[channel]) < 0:
		return []
	return previous.data["patterns"][int(ids[channel])]["notes"].duplicate(true)
