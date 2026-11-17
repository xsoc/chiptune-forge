class_name SnesArranger
extends RefCounted
## Fits a generated song onto the SNES's sampled voices, for SNESMod.
##
## Starts from the Mega Drive arrangement ([MdArranger]), which already has
## one channel per part, and moves it onto seven of the eight voices: lead,
## harmony, arpeggio and bass keep a voice each, the pad's chords play their
## two highest notes on two voices, and the drums share one voice of
## sampled drums. The eighth voice stays free for SNESMod's sound effects.
## Each part plays a small sample from [SnesSamples] chosen from its wave in
## the source song, with a volume envelope; the lead gets a delayed vibrato
## and the arrangement gets the S-DSP's echo.

const INST_LEAD := 0
const INST_HARMONY := 1
const INST_ARP := 2
const INST_BASS := 3
const INST_PAD := 4
const INST_KICK := 5
const INST_SNARE := 6
const INST_TOM := 7
const INST_HAT := 8
const INST_OPEN_HAT := 9
const INST_CRASH := 10
const INST_RIDE := 11
## The drum instrument for each drum kind.
const DRUM_INSTRUMENT := {
	GbArranger.KICK: INST_KICK, GbArranger.SNARE: INST_SNARE, GbArranger.TOM: INST_TOM,
	GbArranger.HAT: INST_HAT, GbArranger.OPEN_HAT: INST_OPEN_HAT, GbArranger.CRASH: INST_CRASH,
	GbArranger.RIDE: INST_RIDE,
}
const DRUM_SAMPLES := ["kick", "snare", "tom", "hat", "open_hat", "crash", "ride"]
## Level (0 to 15, 2 dB steps) for each instrument at velocity 100.
const PART_LEVEL := {INST_LEAD: 15, INST_HARMONY: 12, INST_ARP: 11, INST_BASS: 15, INST_PAD: 11, INST_KICK: 15, INST_SNARE: 14, INST_TOM: 14, INST_HAT: 11, INST_OPEN_HAT: 11, INST_CRASH: 12, INST_RIDE: 11}
## Mega Drive channels feeding each SNES channel (pads and drums merge).
const FROM_MD := [[MdSong.FM1], [MdSong.FM2], [MdSong.FM3], [MdSong.FM4], [MdSong.SQUARE1, MdSong.SQUARE2, MdSong.SQUARE3], [], [MdSong.FM5, MdSong.MD_NOISE], []]
## Stereo placement: harmony and arpeggio apart, pads spread.
const PANS := [32, 22, 42, 32, 18, 46, 32, 32]
## Echo on the lead, harmony, arpeggio and pads.
const ECHO_CHANNELS := (1 << SnesSong.LEAD) | (1 << SnesSong.HARMONY) | (1 << SnesSong.ARP) | (1 << SnesSong.PAD1) | (1 << SnesSong.PAD2)


## Arranges [param song]. [param into] is the song to fill, for targets
## that play the same arrangement on other hardware (the Game Boy Advance).
static func arrange(song: ChipSong, into: SnesSong = null) -> SnesSong:
	var md := MdArranger.arrange(song)
	var src: ChipSong = md.source
	var snes := into if into else SnesSong.new()
	var data := song.data
	var spb := song.get_steps_per_beat()
	snes.title = song.get_title()
	snes.steps_per_beat = spb
	snes.steps_per_bar = md.steps_per_bar
	var speed := SnesSong.choose_tempo(song.get_bpm(), spb, snes.standard_ticks)
	snes.set_tempo(int(speed["tempo"]), int(speed["speed"]))
	snes.looping = md.looping
	snes.pans = PackedInt32Array(PANS)
	var channels: Array = data.get("channels", [])
	var instruments: Array = data.get("instruments", [])
	var roles := GbArranger._roles(channels)
	_design_instruments(snes, instruments, channels, roles)
	_design_echo(snes, song)

	var stats := {"pad_notes": 0, "merged": 0, "arps": 0, "octave": {}}
	var md_sections: Array = src.data.get("sections", [])
	var md_patterns: Array = src.data.get("patterns", [])
	var arp_index := {}
	var per_section: Array = []
	for section in md_sections:
		per_section.append(_arrange_section(snes, section, md_patterns, stats, arp_index))

	var order: Array = src.data.get("order", [])
	var events: Array = []
	for c in SnesSong.CHANNEL_COUNT:
		events.append([])
	var row := 0
	var loop_end := song.get_loop_end_step()
	for index in order:
		var section: Dictionary = md_sections[int(index)]
		var length := int(section.get("length", 0))
		if snes.looping and row >= loop_end:
			break
		snes.section_rows.append({"name": str(section.get("name", "")), "row": row, "length": length})
		for c in SnesSong.CHANNEL_COUNT:
			for e in per_section[int(index)][c]:
				var moved: Dictionary = e.duplicate()
				moved["step"] = int(e["step"]) + row
				events[c].append(moved)
		row += length
	snes.row_count = row
	snes.loop_start_row = md.loop_start_row
	for c in SnesSong.CHANNEL_COUNT:
		snes.notes[c] = NesArranger._to_notes(events[c], row)
	for feed in md.feeds:
		var sources: Array = []
		for c in SnesSong.CHANNEL_COUNT:
			var merged: Array = []
			var from: Array = FROM_MD[c] if c != SnesSong.PAD2 else FROM_MD[SnesSong.PAD1]
			for md_channel in from:
				for s in feed["sources"][md_channel]:
					if not merged.has(s):
						merged.append(s)
			sources.append(merged)
		snes.feeds.append({"row": feed["row"], "sources": sources})
	snes.source = _build_source(snes, song, per_section, float(speed["bpm"]))
	snes.stats = stats
	_write_report(snes, song, md, stats, speed)
	return snes


## The sample for a part's wave in the source song.
static func wave_sample(inst: Dictionary, bass := false) -> String:
	var wave := str(inst.get("wave", "pulse"))
	if bass:
		match wave:
			"saw":
				return "bass_saw"
			"pulse", "square":
				return "bass_square"
		return "bass_triangle"
	match wave:
		"pulse":
			var duty := float(inst.get("duty", 0.5))
			if duty <= 0.15 or duty >= 0.85:
				return "pulse12"
			if duty <= 0.35 or duty >= 0.65:
				return "pulse25"
			return "square"
		"square":
			return "square"
		"saw", "triangle", "sine":
			return wave
	return "square"


static func _design_instruments(snes: SnesSong, instruments: Array, channels: Array, roles: Dictionary) -> void:
	var lead := GbArranger._instrument_of(instruments, channels, roles[GbArranger.LEAD])
	var harmony := GbArranger._instrument_of(instruments, channels, roles[GbArranger.HARMONY])
	var arp := GbArranger._instrument_of(instruments, channels, roles[GbArranger.ARP])
	var bass := GbArranger._instrument_of(instruments, channels, roles[GbArranger.BASS])
	var pad := GbArranger._instrument_of(instruments, channels, roles[GbArranger.PAD])
	var names: Array = [
		wave_sample(lead), wave_sample(harmony), wave_sample(arp), wave_sample(bass, true),
		"pad_saw" if str(pad.get("wave", "pulse")) in ["saw", "triangle", "sine"] else "pad_square",
	]
	names.append_array(DRUM_SAMPLES)
	var samples := PackedStringArray()
	var sample_of := func(sample_name: String) -> int:
		var i := samples.find(sample_name)
		if i < 0:
			samples.append(sample_name)
			i = samples.size() - 1
		return i
	var hz := snes.frame_hz
	var ticks := func(seconds: float) -> int: return clampi(roundi(seconds * hz), 1, 200)
	var depth := clampi(roundi(float(lead.get("vibrato_depth", 0.2)) * 12.0), 2, 6)
	snes.instruments = [
		{"name": "Lead", "sample": sample_of.call(names[0]), "fadeout": 0,
			"env": _sustain_env(64, 48, ticks.call(0.25), ticks.call(0.08)),
			"vibrato": {"delay": snes.steps_per_beat, "speed": 4, "depth": depth}},
		{"name": "Harmony", "sample": sample_of.call(names[1]), "fadeout": 0,
			"env": _sustain_env(60, 40, ticks.call(0.3), ticks.call(0.08))},
		{"name": "Arp", "sample": sample_of.call(names[2]), "fadeout": 0,
			"env": {"nodes": [[0, 64], [ticks.call(0.08), 34], [ticks.call(0.08) + ticks.call(0.3), 18], [ticks.call(0.08) + ticks.call(0.3) + ticks.call(0.06), 0]], "sustain": 2}},
		{"name": "Bass", "sample": sample_of.call(names[3]), "fadeout": 0,
			"env": _sustain_env(64, 54, ticks.call(0.15), ticks.call(0.05))},
		{"name": "Pad", "sample": sample_of.call(names[4]), "fadeout": 0, "env": _pad_env(pad, ticks)},
	]
	for i in DRUM_SAMPLES.size():
		snes.instruments.append({"name": str(DRUM_SAMPLES[i]).capitalize(), "sample": sample_of.call(DRUM_SAMPLES[i]), "fadeout": 0})
	snes.samples = samples


## An envelope that starts at [param peak], falls to [param hold] over
## [param decay] ticks and holds it until the note ends, then fades out
## over [param release] ticks.
static func _sustain_env(peak: int, hold: int, decay: int, release: int) -> Dictionary:
	return {"nodes": [[0, peak], [decay, hold], [decay + release, 0]], "sustain": 1}


## The pad's envelope, from its ADSR in the source song.
static func _pad_env(pad: Dictionary, ticks: Callable) -> Dictionary:
	var attack: int = ticks.call(clampf(float(pad.get("attack", 0.05)), 0.0, 2.0))
	var decay: int = ticks.call(clampf(float(pad.get("decay", 0.3)), 0.01, 2.0))
	var release: int = ticks.call(clampf(float(pad.get("release", 0.2)), 0.02, 1.0))
	var hold := clampi(roundi(64.0 * clampf(float(pad.get("sustain", 0.7)), 0.1, 1.0)), 8, 64)
	return {"nodes": [[0, 0], [attack, 64], [attack + decay, hold], [attack + decay + release, 0]], "sustain": 2}


## Echo from the source song's echo, or a light room if it has none: the
## sound people expect from the SNES. Longer delays cost audio RAM (2 KB
## per 16 ms), so the delay stays at 80 ms or less.
static func _design_echo(snes: SnesSong, song: ChipSong) -> void:
	var effects: Dictionary = song.data.get("effects", {})
	var amount := float(effects.get("echo", 0.0))
	var echo := {"fir": [127, 0, 0, 0, 0, 0, 0, 0], "eon": ECHO_CHANNELS}
	if amount > 0.0:
		var beats := float(effects.get("echo_beats", 0.75))
		var ms := beats * 60000.0 / maxf(song.get_bpm(), 1.0)
		echo["edl"] = clampi(roundi(ms / 16.0), 2, 5)
		echo["efb"] = clampi(roundi(float(effects.get("echo_feedback", 0.3)) * 90.0), 0, 80)
		echo["evol"] = clampi(roundi(amount * 110.0), 20, 60)
	else:
		echo["edl"] = 3
		echo["efb"] = 32
		echo["evol"] = 24
	snes.echo = echo


## One section's events per SNES channel, from the Mega Drive patterns.
static func _arrange_section(snes: SnesSong, section: Dictionary, patterns: Array, stats: Dictionary, arp_index: Dictionary) -> Array:
	var ids: Array = section.get("patterns", [])
	var md_notes := func(md_channel: int) -> Array:
		if md_channel >= ids.size() or int(ids[md_channel]) < 0:
			return []
		return patterns[int(ids[md_channel])]["notes"]
	var out: Array = []
	for c in SnesSong.CHANNEL_COUNT:
		out.append([])
	out[SnesSong.LEAD] = _line(snes, md_notes.call(MdSong.FM1), INST_LEAD, stats, arp_index)
	out[SnesSong.HARMONY] = _line(snes, md_notes.call(MdSong.FM2), INST_HARMONY, stats, arp_index)
	out[SnesSong.ARP] = _line(snes, md_notes.call(MdSong.FM3), INST_ARP, stats, arp_index)
	out[SnesSong.BASS] = _line(snes, md_notes.call(MdSong.FM4), INST_BASS, stats, arp_index)
	var pads := _pads(snes, md_notes.call(MdSong.SQUARE1) + md_notes.call(MdSong.SQUARE2) + md_notes.call(MdSong.SQUARE3), stats)
	out[SnesSong.PAD1] = pads[0]
	out[SnesSong.PAD2] = pads[1]
	out[SnesSong.DRUMS] = _drums(md_notes.call(MdSong.FM5) + md_notes.call(MdSong.MD_NOISE), stats)
	return out


## Level for a note: the part's level, 2 dB lower for each 0.8x velocity.
static func _volume(instrument: int, velocity: int) -> int:
	var base: int = PART_LEVEL.get(instrument, 15)
	return SnesSong.volume_of_level(clampi(base + roundi(10.0 * log(maxf(velocity, 1) / 100.0) / log(10.0)), 1, 15))


## A note moved by octaves to fit the instrument. Returns the note.
static func _fit(snes: SnesSong, instrument: int, midi: int, stats: Dictionary) -> int:
	var highest := snes.highest_note(instrument)
	var note := midi
	while note > highest:
		note -= 12
	while note < 12:
		note += 12
	if note != midi:
		var part := str(snes.instruments[instrument]["name"])
		stats["octave"][part] = int(stats["octave"].get(part, 0)) + 1
	return note


static func _line(snes: SnesSong, notes: Array, instrument: int, stats: Dictionary, arp_index: Dictionary) -> Array:
	var events: Array = []
	for note in notes:
		var velocity := int(note[3]) if note.size() > 3 else 100
		var value := _fit(snes, instrument, int(note[2]), stats)
		var event := {
			"step": int(note[0]),
			"length": maxi(int(note[1]), 1),
			"note": value,
			"midi": value,
			"velocity": velocity,
			"instrument": instrument,
			"volume": _volume(instrument, velocity),
			"arp": -1,
		}
		if note.size() > 5 and note[5] is Array:
			var fitted := _arpeggio(snes, arp_index, note[5], value, instrument, stats)
			event["note"] = fitted["note"]
			event["midi"] = fitted["note"]
			event["arp"] = fitted["arp"]
		events.append(event)
	return events


## An arpeggio as Impulse Tracker's J command plays it: the note and up to
## two more, 0 to 15 semitones above. Offsets below the note move the note
## down to the lowest of them. Returns {note, arp}.
static func _arpeggio(snes: SnesSong, arp_index: Dictionary, offsets: Array, note: int, instrument: int, stats: Dictionary) -> Dictionary:
	var values: Array = []
	for value in offsets:
		if not values.has(int(value)):
			values.append(int(value))
	var low: int = values.min()
	var base := note + low
	var ups: Array = []
	for v in values:
		var up := int(v) - low
		if up > 0 and up <= 15 and not ups.has(up) and base + up <= snes.highest_note(instrument):
			ups.append(up)
	if ups.size() > 2 or ups.size() + 1 < values.size():
		stats["arps"] = int(stats["arps"]) + 1
	ups = ups.slice(0, 2)
	if ups.is_empty():
		return {"note": note, "arp": -1}
	var arp: Array = [0] + ups
	var key := ",".join(PackedStringArray(arp.map(func(v: int) -> String: return str(v))))
	if not arp_index.has(key):
		arp_index[key] = snes.arpeggios.size()
		snes.arpeggios.append({"name": "Arp %s" % key.replace(",", "-"), "values": arp, "loop": 0})
	return {"note": base, "arp": arp_index[key]}


## The pad's two highest notes at each step, the lower on Pad 1.
static func _pads(snes: SnesSong, notes: Array, stats: Dictionary) -> Array:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		if not by_step.has(step):
			by_step[step] = []
		by_step[step].append(note)
	var voices: Array = [[], []]
	var steps := by_step.keys()
	steps.sort()
	for step in steps:
		var chord: Array = by_step[step]
		chord.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
		if chord.size() > 2:
			stats["pad_notes"] = int(stats["pad_notes"]) + chord.size() - 2
			chord = chord.slice(chord.size() - 2)
		for v in chord.size():
			var note: Array = chord[v]
			var velocity := int(note[3]) if note.size() > 3 else 90
			var value := _fit(snes, INST_PAD, int(note[2]), stats)
			voices[v].append({
				"step": int(step),
				"length": maxi(int(note[1]), 1),
				"note": value,
				"midi": value,
				"velocity": velocity,
				"instrument": INST_PAD,
				"volume": _volume(INST_PAD, velocity),
				"arp": -1,
			})
	return voices


## All drums on one voice: one hit per step, by the usual priority.
static func _drums(notes: Array, stats: Dictionary) -> Array:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		var drum := int(note[4]) if note.size() > 4 and int(note[4]) >= 0 else GbArranger.SNARE
		if not DRUM_INSTRUMENT.has(drum):
			drum = GbArranger.SNARE
		if by_step.has(step):
			var current := int(by_step[step][4])
			if current == drum:
				continue
			stats["merged"] = int(stats["merged"]) + 1
			if GbArranger.DRUM_PRIORITY.find(drum) >= GbArranger.DRUM_PRIORITY.find(current):
				continue
		var hit: Array = note.duplicate()
		while hit.size() < 5:
			hit.append(-1)
		hit[4] = drum
		by_step[step] = hit
	var steps := by_step.keys()
	steps.sort()
	var events: Array = []
	for step in steps:
		var hit: Array = by_step[step]
		var drum := int(hit[4])
		var velocity := int(hit[3]) if hit.size() > 3 else 100
		var instrument: int = DRUM_INSTRUMENT[drum]
		var note := 60
		if drum == GbArranger.TOM:
			# Fills step down in pitch: follow them, around the sample's pitch.
			note = clampi(60 + (int(hit[2]) - 45) / 2, 54, 66)
		events.append({
			"step": int(step),
			"length": 1,
			"note": note,
			"midi": int(hit[2]),
			"velocity": velocity,
			"instrument": instrument,
			"volume": _volume(instrument, velocity),
			"arp": -1,
			"drum": drum,
		})
	return events


## The arrangement as an eight-channel ChipSong, with the original's
## sections, order, cues and states, at the tempo the console plays.
static func _build_source(snes: SnesSong, song: ChipSong, per_section: Array, bpm: float) -> ChipSong:
	var data: Dictionary = song.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(bpm, 0.0001)
	data["timing"]["swing"] = 0.0
	data["meta"]["target"] = "snes"
	var insts: Array = []
	var channels: Array = []
	var layers: Array = []
	for c in SnesSong.CHANNEL_COUNT:
		var name := SnesSong.SNES_CHANNEL_NAMES[c]
		var wave := "noise" if c == SnesSong.DRUMS else ("triangle" if c == SnesSong.BASS else "pulse")
		insts.append({"name": name, "wave": wave, "duty": 0.5, "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.05, "volume": 0.4})
		channels.append({"name": name, "instrument": c, "layer": name, "volume": 1.0, "pan": 0.0, "polyphony": 1})
		layers.append({"name": name, "channels": [c]})
	data["instruments"] = insts
	data["channels"] = channels
	data["layers"] = layers
	var patterns: Array = []
	var sections: Array = data["sections"]
	for i in sections.size():
		var ids: Array = []
		for c in SnesSong.CHANNEL_COUNT:
			var notes: Array = []
			for e in per_section[i][c]:
				var note: Array = [int(e["step"]), int(e["length"]), int(e["midi"]), clampi(int(e["velocity"]), 1, 127)]
				if e.has("drum"):
					note.append(int(e["drum"]))
				elif int(e["arp"]) >= 0:
					note.append(-1)
					note.append(snes.arpeggios[int(e["arp"])]["values"].duplicate())
				notes.append(note)
			if notes.is_empty():
				ids.append(-1)
			else:
				ids.append(patterns.size())
				patterns.append({"notes": notes})
		sections[i]["patterns"] = ids
	data["patterns"] = patterns
	var out := ChipSong.new()
	out.data = data
	return out


static func _write_report(snes: SnesSong, song: ChipSong, md: MdSong, stats: Dictionary, speed: Dictionary) -> void:
	var lines := PackedStringArray()
	var sample := func(index: int) -> String: return snes.samples[int(snes.instruments[index]["sample"])].replace("_", " ")
	lines.append("Voice 1 plays the lead (%s wave, with vibrato on long notes), voice 2 the harmony (%s) and voice 3 the arpeggio (%s)." % [sample.call(INST_LEAD), sample.call(INST_HARMONY), sample.call(INST_ARP)])
	lines.append("Voice 4 plays the bass (%s). Voices 5 and 6 play the pad's two highest notes (%s)." % [sample.call(INST_BASS), sample.call(INST_PAD)])
	lines.append("Voice 7 plays all the drums as samples. Voice 8 is left free for SNESMod's sound effects.")
	for promoted in md.stats.get("promoted", []):
		lines.append("The %s plays the lead in %s, where there is none." % [str(promoted[1]).to_lower(), promoted[0]])
	if int(stats["pad_notes"]) > 0:
		lines.append("%d pad notes dropped where a chord had more than two." % int(stats["pad_notes"]))
	if int(stats["merged"]) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step." % int(stats["merged"]))
	if int(stats["arps"]) > 0:
		lines.append("%d arpeggios cut to three notes, as Impulse Tracker's arpeggio plays them." % int(stats["arps"]))
	var octave: Dictionary = stats["octave"]
	for part in octave:
		lines.append("%d %s notes moved by an octave to fit the sample's range." % [int(octave[part]), part])
	var echo: Dictionary = snes.echo
	var amount := float(song.data.get("effects", {}).get("echo", 0.0))
	lines.append("%s: %d ms delay on the melody and pads." % ["Echo from the song" if amount > 0.0 else "A light echo added", int(echo["edl"]) * 16])
	if float(song.data.get("timing", {}).get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: SNESMod plays even rows.")
	var ram := snes.ram_use()
	lines.append("Audio RAM: %d samples in %.1f KB, echo %d KB, %.1f KB left for patterns." % [int(ram["samples"]), int(ram["bytes"]) / 1024.0, int(ram["echo"]) / 1024, int(ram["free"]) / 1024.0])
	lines.append("Tempo %s BPM plays at %.1f BPM (speed %d, tempo %d)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), snes.speed(), snes.tempo])
	snes.report = lines
