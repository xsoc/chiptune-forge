class_name MdArranger
extends RefCounted
## Fits a generated song into the Mega Drive's six FM channels and its PSG.
##
## With ten channels, every part gets its own: FM 1 plays the lead, FM 2
## the harmony, FM 3 the arpeggio, FM 4 the bass, and FM 5 the kick, snare
## and toms as FM drums. The PSG's three squares play the pad's chords as
## real chords (up to three notes), and its noise channel the snare, hats
## and cymbals. FM 6 stays free, because SGDK's XGM driver plays sampled
## sound effects there. Each FM part gets a patch chosen from the part's
## wave in the source song. Notes move by octaves into each chip's range and
## the tempo snaps to whole frames at the console's 59.92 Hz.

const LEAD := GbArranger.LEAD
const HARMONY := GbArranger.HARMONY
const ARP := GbArranger.ARP
const PAD := GbArranger.PAD
const BASS := GbArranger.BASS
const DRUMS := GbArranger.DRUMS
const NOISE := GbArranger.NOISE
const PART_NAMES := GbArranger.PART_NAMES

## Instrument indexes in [member MdSong.instruments].
const INST_LEAD := 0
const INST_HARMONY := 1
const INST_ARP := 2
const INST_BASS := 3
const INST_KICK := 4
const INST_SNARE := 5
const INST_TOM := 6
const INST_PAD := 7
const INST_NOISE_KIT := 8

## Level (0 to 15, 2 dB steps) for each instrument at velocity 100.
const PART_LEVEL := {INST_LEAD: 15, INST_HARMONY: 12, INST_ARP: 11, INST_BASS: 15, INST_KICK: 15, INST_SNARE: 13, INST_TOM: 14, INST_PAD: 11}
## Drums the FM drum channel plays, and the noise channel plays.
const FM_DRUMS := [GbArranger.KICK, GbArranger.SNARE, GbArranger.TOM]
const NOISE_DRUMS := [GbArranger.SNARE, GbArranger.CRASH, GbArranger.OPEN_HAT, GbArranger.HAT, GbArranger.RIDE]
## Noise kit pieces, from [NesArranger.KIT]: its index for each drum kind.
const NOISE_PIECE := {GbArranger.SNARE: 1, GbArranger.HAT: 2, GbArranger.OPEN_HAT: 3, GbArranger.CRASH: 4, GbArranger.RIDE: 6}
const SOFT_NOISE_PIECE := {GbArranger.SNARE: 7, GbArranger.HAT: 8}
## The noise kit's instruments, in order from INST_NOISE_KIT.
const NOISE_KIT := [1, 2, 3, 4, 6, 7, 8]
## FM drum notes (MIDI) and pitch drops (semitones per frame).
const KICK_NOTE := 33
const KICK_DROP := [24, 17, 12, 8, 5, 3, 1, 0]
const SNARE_NOTE := 52
const SNARE_DROP := [7, 3, 0]
const TOM_DROP := [7, 4, 2, 1, 0, -1, -2]
## The lead's vibrato starts after this many frames.
const VIBRATO_DELAY := 12


static func arrange(song: ChipSong) -> MdSong:
	var md := MdSong.new()
	var data := song.data
	var timing: Dictionary = data.get("timing", {})
	var spb := song.get_steps_per_beat()
	md.title = song.get_title()
	md.steps_per_beat = spb
	md.steps_per_bar = spb * song.get_beats_per_bar()
	var speed := NesSong.choose_groove(song.get_bpm(), spb, MdSong.FRAME_HZ)
	md.groove = speed["groove"]
	md.looping = bool(timing.get("loop", true))

	var channels: Array = data.get("channels", [])
	var instruments: Array = data.get("instruments", [])
	var roles := GbArranger._roles(channels)
	_design_instruments(md, instruments, channels, roles)

	var stats := {"octave": {}, "merged": 0, "promoted": [], "chord_notes": 0}
	var arp_index := {}
	var sections: Array = data.get("sections", [])
	var per_section: Array = []
	for i in sections.size():
		per_section.append(_arrange_section(md, song, sections[i], roles, stats, arp_index))

	var order: Array = data.get("order", [])
	var loop_end := song.get_loop_end_step()
	var events: Array = []
	for c in MdSong.CHANNEL_COUNT:
		events.append([])
	var row := 0
	for index in order:
		var section: Dictionary = sections[int(index)]
		var length := int(section.get("length", 0))
		if md.looping and row >= loop_end:
			break
		md.section_rows.append({"name": str(section.get("name", "")), "row": row, "length": length})
		var arranged: Dictionary = per_section[int(index)]
		md.feeds.append({"row": row, "sources": arranged["sources"]})
		for c in MdSong.CHANNEL_COUNT:
			for e in arranged["events"][c]:
				var moved: Dictionary = e.duplicate()
				moved["step"] = int(e["step"]) + row
				events[c].append(moved)
		row += length
	md.row_count = row
	md.loop_start_row = song.get_loop_start_step() if md.looping else 0
	for c in MdSong.CHANNEL_COUNT:
		md.notes[c] = NesArranger._to_notes(events[c], row)
	md.source = _build_source(md, song, per_section, speed)
	md.stats = stats
	_write_report(md, song, stats, speed)
	return md


static func _design_instruments(md: MdSong, instruments: Array, channels: Array, roles: Dictionary) -> void:
	var lead := GbArranger._instrument_of(instruments, channels, roles[LEAD])
	var harmony := GbArranger._instrument_of(instruments, channels, roles[HARMONY])
	var arp := GbArranger._instrument_of(instruments, channels, roles[ARP])
	var bass := GbArranger._instrument_of(instruments, channels, roles[BASS])
	var pad := GbArranger._instrument_of(instruments, channels, roles[PAD])
	var lead_inst := {"name": "Lead", "fm": MdPatches.lead(str(lead.get("wave", "pulse")))}
	var cents := clampi(roundi(float(lead.get("vibrato_depth", 0.2)) * 50.0), 5, 25)
	var pitch: Array = []
	for i in VIBRATO_DELAY:
		pitch.append(0)
	for v in [0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5, 0.0]:
		pitch.append(roundi(v * cents))
	lead_inst["pitch"] = pitch
	lead_inst["pitch_loop"] = VIBRATO_DELAY
	var pad_volume: Array = []
	for v in NesArranger.adsr_envelope(pad):
		pad_volume.append(SmsSong.level_of(float(v)))
	md.instruments = [
		lead_inst,
		{"name": "Harmony", "fm": MdPatches.harmony(str(harmony.get("wave", "pulse")))},
		{"name": "Arp", "fm": MdPatches.arp(str(arp.get("wave", "pulse")))},
		{"name": "Bass", "fm": MdPatches.bass(str(bass.get("wave", "triangle")))},
		{"name": "Kick", "fm": MdPatches.kick(), "arp": KICK_DROP.duplicate()},
		{"name": "Snare", "fm": MdPatches.snare(), "arp": SNARE_DROP.duplicate()},
		{"name": "Tom", "fm": MdPatches.tom(), "arp": TOM_DROP.duplicate()},
		{"name": "Pad", "volume": pad_volume},
	]
	for piece in NOISE_KIT:
		var drum: Dictionary = NesArranger.KIT[piece]
		var volume: Array = []
		for v in drum["volume"]:
			volume.append(SmsSong.level_of(float(v)))
		md.instruments.append({"name": "Noise " + str(drum["name"]).to_lower(), "volume": volume, "duty": [1]})


## Arranges one section. Returns {events: one array of note events per
## channel, sources: the source channels feeding each channel}.
static func _arrange_section(md: MdSong, song: ChipSong, section: Dictionary, roles: Dictionary, stats: Dictionary, arp_index: Dictionary) -> Dictionary:
	var name := str(section.get("name", ""))
	var length := int(section.get("length", 0))
	var notes := {}
	var has := {}
	for part in PART_NAMES.size():
		notes[part] = GbArranger._notes_of(song, section, roles[part])
		has[part] = not (notes[part] as Array).is_empty()
	var lead_part := -1
	if has[LEAD]:
		lead_part = LEAD
	else:
		for part in [HARMONY, ARP]:
			if has[part]:
				lead_part = part
				stats["promoted"].append([name, PART_NAMES[part]])
				break

	var events: Array = []
	var sources: Array = []
	for c in MdSong.CHANNEL_COUNT:
		events.append([])
		sources.append([])
	if lead_part >= 0:
		events[MdSong.FM1] = _line_events(md, notes[lead_part], INST_LEAD, true, length, stats, "Lead", arp_index)
		sources[MdSong.FM1] = [roles[lead_part]]
	if has[HARMONY] and lead_part != HARMONY:
		events[MdSong.FM2] = _line_events(md, notes[HARMONY], INST_HARMONY, true, length, stats, "Harmony", arp_index)
		sources[MdSong.FM2] = [roles[HARMONY]]
	if has[ARP] and lead_part != ARP:
		events[MdSong.FM3] = _line_events(md, notes[ARP], INST_ARP, true, length, stats, "Arp", arp_index)
		sources[MdSong.FM3] = [roles[ARP]]
	if has[BASS]:
		events[MdSong.FM4] = _line_events(md, notes[BASS], INST_BASS, false, length, stats, "Bass", arp_index)
		sources[MdSong.FM4] = [roles[BASS]]
	if has[PAD]:
		var voices := _chord_events(notes[PAD], length, stats)
		for v in 3:
			events[MdSong.SQUARE1 + v] = voices[v]
			if not (voices[v] as Array).is_empty():
				sources[MdSong.SQUARE1 + v] = [roles[PAD]]
	if has[DRUMS] or has[NOISE]:
		var hits: Array = notes[DRUMS] + notes[NOISE]
		events[MdSong.FM5] = _fm_drum_events(hits, length, stats)
		events[MdSong.MD_NOISE] = _noise_drum_events(hits, length, stats)
		sources[MdSong.FM5] = [roles[DRUMS], roles[NOISE]]
		sources[MdSong.MD_NOISE] = [roles[DRUMS], roles[NOISE]]
	return {"events": events, "sources": sources}


## Level for a note: the part's level, 2 dB lower for each 0.8x velocity.
static func _level(instrument: int, velocity: int) -> int:
	var base: int = PART_LEVEL.get(instrument, 15)
	return clampi(base + roundi(10.0 * log(maxf(velocity, 1) / 100.0) / log(10.0)), 1, 15)


## One note at a time, on an FM channel: on each step the highest note wins
## (the lowest for the bass).
static func _line_events(md: MdSong, notes: Array, instrument: int, highest: bool, length: int, stats: Dictionary, part: String, arp_index: Dictionary) -> Array:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		if step < 0 or step >= length:
			continue
		var pitch := int(note[2])
		if not by_step.has(step):
			by_step[step] = note
		else:
			var other := int(by_step[step][2])
			if (highest and pitch > other) or (not highest and pitch < other):
				by_step[step] = note
	var steps := by_step.keys()
	steps.sort()
	var events: Array = []
	for step in steps:
		var note: Array = by_step[step]
		var fitted := MdSong.fit_fm(int(note[2]))
		if fitted["moved"]:
			stats["octave"][part] = int(stats["octave"].get(part, 0)) + 1
		var value: int = fitted["note"]
		var velocity := int(note[3]) if note.size() > 3 else 100
		var event := {
			"step": int(step),
			"length": maxi(int(note[1]), 1),
			"note": value,
			"midi": value,
			"velocity": velocity,
			"instrument": instrument,
			"volume": _level(instrument, velocity),
			"arp": -1,
		}
		if note.size() > 5 and note[5] is Array:
			event["arp"] = _arpeggio(md, arp_index, note[5], value)
			event["offsets"] = note[5]
		events.append(event)
	return events


## The index of a looping arpeggio over [param offsets], made the first time
## it is needed, or -1 when nothing is left to arpeggiate.
static func _arpeggio(md: MdSong, arp_index: Dictionary, offsets: Array, note: int) -> int:
	var values: Array = [0]
	for value in offsets:
		var o := int(value)
		if o != 0 and absi(o) <= 24 and not values.has(o) and note + o <= MdSong.FM_HIGHEST and note + o >= MdSong.FM_LOWEST:
			values.append(o)
	if values.size() < 2:
		return -1
	var key := ",".join(PackedStringArray(values.map(func(v: int) -> String: return str(v))))
	if not arp_index.has(key):
		arp_index[key] = md.arpeggios.size()
		var label := "-".join(PackedStringArray(values.map(func(v: int) -> String: return str(v))))
		md.arpeggios.append({"name": "Arp %s" % label, "values": values, "loop": 0})
	return arp_index[key]


## Pad chords as real chords on the three squares, lowest note on Square 1.
## Chords of four or more notes lose their lowest notes (the bass has the
## root). Returns three arrays of events.
static func _chord_events(notes: Array, length: int, stats: Dictionary) -> Array:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		if step < 0 or step >= length:
			continue
		if not by_step.has(step):
			by_step[step] = []
		by_step[step].append(note)
	var steps := by_step.keys()
	steps.sort()
	var voices: Array = [[], [], []]
	for step in steps:
		var chord: Array = by_step[step]
		chord.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
		var pitches: Array = []
		for note in chord:
			if not pitches.has(int(note[2])):
				pitches.append(int(note[2]))
		if pitches.size() > 3:
			stats["chord_notes"] = int(stats["chord_notes"]) + pitches.size() - 3
			pitches = pitches.slice(pitches.size() - 3)
		var longest := 1
		var velocity := 90
		for note in chord:
			longest = maxi(longest, int(note[1]))
			if note.size() > 3:
				velocity = int(note[3])
		for v in pitches.size():
			var fitted := SmsSong.fit(int(pitches[v]))
			if fitted["moved"]:
				stats["octave"]["Pad"] = int(stats["octave"].get("Pad", 0)) + 1
			voices[v].append({
				"step": int(step),
				"length": longest,
				"note": int(fitted["note"]),
				"midi": int(fitted["note"]),
				"velocity": velocity,
				"instrument": INST_PAD,
				"volume": _level(INST_PAD, velocity),
				"arp": -1,
			})
	return voices


## Drum hits by step, one per step from [param kinds] by priority. Returns
## {step: hit} where hit[4] is the drum kind.
static func _pick_hits(notes: Array, length: int, kinds: Array, stats: Dictionary) -> Dictionary:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		if step < 0 or step >= length:
			continue
		var drum := int(note[4]) if note.size() > 4 and int(note[4]) >= 0 else GbArranger.SNARE
		if not NesArranger.KIT_FOR.has(drum):
			drum = GbArranger.SNARE
		if not kinds.has(drum):
			continue
		if by_step.has(step):
			stats["merged"] = int(stats["merged"]) + 1
			var current := int(by_step[step][4])
			if GbArranger.DRUM_PRIORITY.find(drum) >= GbArranger.DRUM_PRIORITY.find(current):
				continue
		var hit: Array = note.duplicate()
		while hit.size() < 5:
			hit.append(-1)
		hit[4] = drum
		by_step[step] = hit
	return by_step


## Kick, snare and toms on FM 5.
static func _fm_drum_events(notes: Array, length: int, stats: Dictionary) -> Array:
	var by_step := _pick_hits(notes, length, FM_DRUMS, stats)
	var steps := by_step.keys()
	steps.sort()
	var events: Array = []
	for step in steps:
		var hit: Array = by_step[step]
		var drum := int(hit[4])
		var velocity := int(hit[3]) if hit.size() > 3 else 100
		var instrument := INST_KICK
		var note := KICK_NOTE
		if drum == GbArranger.SNARE:
			instrument = INST_SNARE
			note = SNARE_NOTE
		elif drum == GbArranger.TOM:
			instrument = INST_TOM
			# Fills step down in pitch: follow them.
			note = clampi(43 + (int(hit[2]) - 50) / 2, 36, 52)
		events.append({
			"step": int(step),
			"length": 1,
			"note": note,
			"midi": int(hit[2]),
			"velocity": velocity,
			"instrument": instrument,
			"volume": _level(instrument, velocity),
			"arp": -1,
			"drum": drum,
		})
	return events


## Snare, hats and cymbals on the noise channel.
static func _noise_drum_events(notes: Array, length: int, stats: Dictionary) -> Array:
	var by_step := _pick_hits(notes, length, NOISE_DRUMS, stats)
	var steps := by_step.keys()
	steps.sort()
	var events: Array = []
	for step in steps:
		var hit: Array = by_step[step]
		var drum := int(hit[4])
		var velocity := int(hit[3]) if hit.size() > 3 else 100
		var piece: int = NOISE_PIECE[drum]
		if velocity <= 60 and SOFT_NOISE_PIECE.has(drum):
			piece = SOFT_NOISE_PIECE[drum]
		var index: int = NesArranger.KIT[piece]["index"]
		events.append({
			"step": int(step),
			"length": 1,
			"note": SmsArranger.RATE_FOR_INDEX[index],
			"midi": int(hit[2]),
			"velocity": velocity,
			"instrument": INST_NOISE_KIT + NOISE_KIT.find(piece),
			"volume": 15,
			"arp": -1,
			"drum": drum,
		})
	return events


## The arrangement as a ten-channel ChipSong, with the original's sections,
## order, cues and states, at the tempo the console plays.
static func _build_source(md: MdSong, song: ChipSong, per_section: Array, speed: Dictionary) -> ChipSong:
	var data: Dictionary = song.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(float(speed["bpm"]), 0.0001)
	data["timing"]["swing"] = 0.0
	data["effects"] = {"echo": 0.0, "echo_feedback": 0.0, "echo_beats": 0.75}
	data["meta"]["target"] = "genesis"
	var insts: Array = []
	var channels: Array = []
	var layers: Array = []
	for c in MdSong.CHANNEL_COUNT:
		var drums := c == MdSong.FM5 or c == MdSong.MD_NOISE
		var wave := "noise" if c == MdSong.MD_NOISE else ("pulse" if c >= MdSong.SQUARE1 else "sine")
		insts.append({"name": MdSong.MD_CHANNEL_NAMES[c], "wave": wave, "duty": 0.5, "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.05, "volume": 0.4})
		channels.append({"name": MdSong.MD_CHANNEL_NAMES[c], "instrument": c, "layer": "Drums" if drums else MdSong.MD_CHANNEL_NAMES[c], "volume": 1.0, "pan": 0.0, "polyphony": 1})
		layers.append({"name": MdSong.MD_CHANNEL_NAMES[c], "channels": [c]})
	data["instruments"] = insts
	data["channels"] = channels
	data["layers"] = layers
	var patterns: Array = []
	var sections: Array = data["sections"]
	for i in sections.size():
		var ids: Array = []
		for c in MdSong.CHANNEL_COUNT:
			var notes: Array = []
			for e in per_section[i]["events"][c]:
				var note: Array = [int(e["step"]), int(e["length"]), int(e["midi"]), clampi(int(e["velocity"]), 1, 127)]
				if e.has("drum"):
					note.append(int(e["drum"]))
				elif e.has("offsets") and int(e["arp"]) >= 0:
					note.append(-1)
					note.append(md.arpeggios[int(e["arp"])]["values"].duplicate())
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


static func _write_report(md: MdSong, song: ChipSong, stats: Dictionary, speed: Dictionary) -> void:
	var lines := PackedStringArray()
	var patch := func(index: int) -> String: return str(md.instruments[index]["fm"]["name"])
	var lead_line := "FM 1 plays the lead (%s)" % patch.call(INST_LEAD)
	var promoted: Array = stats["promoted"]
	if not promoted.is_empty():
		var parts: Array = []
		for entry in promoted:
			parts.append("%s in %s" % [entry[1], entry[0]])
		lead_line += ", and the %s where there is no lead" % ", ".join(PackedStringArray(parts))
	lines.append(lead_line + ".")
	lines.append("FM 2 plays the harmony (%s), FM 3 the arpeggio (%s) and FM 4 the bass (%s)." % [patch.call(INST_HARMONY), patch.call(INST_ARP), patch.call(INST_BASS)])
	lines.append("FM 5 plays the kick, snare and toms as FM drums; the noise channel plays the snare, hats and cymbals.")
	lines.append("Square 1 to 3 play the pad's chords. FM 6 is left free for SGDK's sampled sound effects.")
	if int(stats["chord_notes"]) > 0:
		lines.append("%d pad notes dropped where a chord had more than three." % int(stats["chord_notes"]))
	if int(stats["merged"]) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step of one channel." % int(stats["merged"]))
	var octave: Dictionary = stats["octave"]
	for part in octave:
		lines.append("%d %s notes moved by an octave to fit the chip's range." % [int(octave[part]), part])
	var timing: Dictionary = song.data.get("timing", {})
	if float(timing.get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: XGM plays even frames.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the Mega Drive has none.")
	var groove := "-".join(PackedStringArray(Array(md.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	md.report = lines
