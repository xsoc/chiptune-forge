class_name NesArranger
extends RefCounted
## Fits a generated song into the NES's four melodic channels.
##
## Pulse 1 plays the lead. Pulse 2 plays one accompaniment part per section:
## the arpeggio if there is one, else the pad's chords as fast arpeggios,
## else the harmony line. The triangle plays the bass and the noise channel
## plays every drum. The DPCM channel is left free (no samples). Each channel
## plays one note at a time, notes move by octaves into the chip's range, and
## the tempo snaps to a groove of whole video frames. Everything it changes
## is listed in [member NesSong.report].
##
## The part choices match [GbArranger], so a song keeps its shape across
## targets.

const LEAD := GbArranger.LEAD
const HARMONY := GbArranger.HARMONY
const ARP := GbArranger.ARP
const PAD := GbArranger.PAD
const BASS := GbArranger.BASS
const DRUMS := GbArranger.DRUMS
const NOISE := GbArranger.NOISE
const PART_NAMES := GbArranger.PART_NAMES

## Instrument indexes in [member NesSong.instruments].
const INST_LEAD := 0
const INST_ARP := 1
const INST_CHORDS := 2
const INST_HARMONY := 3
const INST_BASS := 4
const INST_KIT := 5

## Volume column for each part at velocity 100.
const PART_VOLUME := {INST_LEAD: 12, INST_ARP: 9, INST_CHORDS: 8, INST_HARMONY: 9}

## The noise drum kit: period index (0 is the highest pitch), mode (1 is the
## metallic short loop), volume envelope, and a pitch drop in period steps
## per frame (an arpeggio envelope on the noise channel).
const KIT := [
	{"name": "Kick", "index": 10, "mode": 0, "volume": [15, 13, 11, 8, 6, 4, 2, 1, 0], "drop": [0, -1, -2, -3, -4, -5]},
	{"name": "Snare", "index": 6, "mode": 0, "volume": [14, 12, 10, 9, 7, 6, 5, 4, 3, 2, 1, 0], "drop": []},
	{"name": "Closed hat", "index": 1, "mode": 0, "volume": [9, 6, 3, 1, 0], "drop": []},
	{"name": "Open hat", "index": 1, "mode": 0, "volume": [10, 9, 8, 7, 6, 6, 5, 5, 4, 4, 3, 3, 2, 2, 1, 1, 0], "drop": []},
	{"name": "Crash", "index": 3, "mode": 0, "volume": [13, 12, 11, 11, 10, 10, 9, 9, 8, 8, 7, 7, 6, 6, 6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 1, 1, 1, 0], "drop": []},
	{"name": "Tom", "index": 9, "mode": 0, "volume": [14, 12, 10, 8, 7, 5, 4, 3, 2, 1, 0], "drop": [0, 0, -1, -1, -2, -2, -3]},
	{"name": "Ride", "index": 3, "mode": 1, "volume": [8, 7, 6, 5, 4, 4, 3, 3, 2, 2, 1, 0], "drop": []},
	{"name": "Soft snare", "index": 6, "mode": 0, "volume": [8, 7, 6, 5, 4, 3, 2, 1, 0], "drop": []},
	{"name": "Soft hat", "index": 1, "mode": 0, "volume": [5, 3, 2, 1, 0], "drop": []},
]
const KIT_FOR := {GbArranger.KICK: 0, GbArranger.SNARE: 1, GbArranger.HAT: 2, GbArranger.OPEN_HAT: 3, GbArranger.CRASH: 4, GbArranger.TOM: 5, GbArranger.RIDE: 6}
const SOFT_KIT := {GbArranger.SNARE: 7, GbArranger.HAT: 8}

## The lead's delayed vibrato: a pitch envelope in timer periods.
const VIBRATO_DELAY := 12
const VIBRATO := [1, 2, 1, 0, -1, -2, -1, 0]


static func arrange(song: ChipSong) -> NesSong:
	var nes := NesSong.new()
	var data := song.data
	var timing: Dictionary = data.get("timing", {})
	var spb := song.get_steps_per_beat()
	nes.title = song.get_title()
	nes.steps_per_beat = spb
	nes.steps_per_bar = spb * song.get_beats_per_bar()
	var speed := NesSong.choose_groove(song.get_bpm(), spb)
	nes.groove = speed["groove"]
	nes.looping = bool(timing.get("loop", true))

	var channels: Array = data.get("channels", [])
	var instruments: Array = data.get("instruments", [])
	var roles := GbArranger._roles(channels)
	_design_instruments(nes, instruments, channels, roles)

	var stats := {"octave": {}, "merged": 0, "accomp": {}, "dropped": {}, "promoted": [], "arp_chords": []}
	var arp_index := {}
	var sections: Array = data.get("sections", [])
	var per_section: Array = []
	for i in sections.size():
		per_section.append(_arrange_section(nes, song, sections[i], roles, stats, arp_index))

	# Lay the sections out in play order. A looping song stops at the loop
	# end: the engine jumps back from there, so an outro would never play.
	var order: Array = data.get("order", [])
	var loop_end := song.get_loop_end_step()
	var events: Array = [[], [], [], []]
	var row := 0
	for index in order:
		var section: Dictionary = sections[int(index)]
		var length := int(section.get("length", 0))
		if nes.looping and row >= loop_end:
			break
		nes.section_rows.append({"name": str(section.get("name", "")), "row": row, "length": length})
		var arranged: Dictionary = per_section[int(index)]
		nes.feeds.append({"row": row, "sources": arranged["sources"]})
		for c in 4:
			for e in arranged["events"][c]:
				var moved: Dictionary = e.duplicate()
				moved["step"] = int(e["step"]) + row
				events[c].append(moved)
		row += length
	nes.row_count = row
	nes.loop_start_row = song.get_loop_start_step() if nes.looping else 0
	for c in 4:
		nes.notes[c] = _to_notes(events[c], row)
	nes.source = _build_source(nes, song, per_section, speed)
	_write_report(nes, song, stats, speed)
	return nes


static func _design_instruments(nes: NesSong, instruments: Array, channels: Array, roles: Dictionary) -> void:
	var lead := GbArranger._instrument_of(instruments, channels, roles[LEAD])
	var arp := GbArranger._instrument_of(instruments, channels, roles[ARP])
	var harmony := GbArranger._instrument_of(instruments, channels, roles[HARMONY])
	var lead_inst := _tone("Lead", lead)
	var pitch: Array = []
	for i in VIBRATO_DELAY:
		pitch.append(0)
	pitch.append_array(VIBRATO)
	lead_inst["pitch"] = pitch
	lead_inst["pitch_loop"] = VIBRATO_DELAY
	nes.instruments = [
		lead_inst,
		_tone("Arp", arp),
		{"name": "Chords", "volume": [15], "duty": [2]},
		_tone("Harmony", harmony),
		{"name": "Bass", "volume": [15]},
	]
	for drum in KIT:
		var inst := {"name": drum["name"], "volume": drum["volume"].duplicate(), "duty": [int(drum["mode"])]}
		if not (drum["drop"] as Array).is_empty():
			inst["arp"] = drum["drop"].duplicate()
		nes.instruments.append(inst)


## A pulse instrument from a source instrument: its duty and a volume
## envelope for its ADSR at 60 frames a second.
static func _tone(name: String, inst: Dictionary) -> Dictionary:
	return {"name": name, "volume": adsr_envelope(inst), "duty": [GbArranger._duty_code(inst)]}


## Volume envelope (0 to 15 per frame) for an ADSR: the attack ramps up, the
## decay falls to the sustain level, which then holds.
static func adsr_envelope(inst: Dictionary) -> Array:
	var attack := roundi(float(inst.get("attack", 0.005)) * NesApu.FRAME_HZ)
	var decay := maxi(roundi(float(inst.get("decay", 0.1)) * NesApu.FRAME_HZ), 1)
	var sustain := clampf(float(inst.get("sustain", 0.7)), 0.0, 1.0)
	var low := roundi(15.0 * sustain)
	var values: Array = []
	for i in mini(attack, 30):
		values.append(clampi(roundi(15.0 * (i + 1) / (attack + 1)), 1, 15))
	values.append(15)
	for i in mini(decay, 60):
		values.append(roundi(lerpf(15.0, low, float(i + 1) / decay)))
	# Drop repeats of the final value: the envelope holds it anyway.
	while values.size() > 1 and values[values.size() - 1] == values[values.size() - 2]:
		values.pop_back()
	return values


## Arranges one section. Returns {events: four arrays of note events,
## sources: the source channels feeding each NES channel}.
static func _arrange_section(nes: NesSong, song: ChipSong, section: Dictionary, roles: Dictionary, stats: Dictionary, arp_index: Dictionary) -> Dictionary:
	var name := str(section.get("name", ""))
	var length := int(section.get("length", 0))
	var notes := {}
	for part in PART_NAMES.size():
		notes[part] = GbArranger._notes_of(song, section, roles[part])
	var has := {}
	for part in PART_NAMES.size():
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
	var accomp_part := -1
	for part in [ARP, PAD, HARMONY]:
		if part != lead_part and has[part]:
			accomp_part = part
			break
	var drums_on: bool = has[DRUMS] or has[NOISE]
	if accomp_part >= 0:
		GbArranger._add_to(stats["accomp"], PART_NAMES[accomp_part], name)
	for part in [HARMONY, ARP, PAD]:
		if has[part] and part != lead_part and part != accomp_part:
			GbArranger._add_to(stats["dropped"], PART_NAMES[part], name)

	var events: Array = [[], [], [], []]
	if lead_part >= 0:
		events[0] = _melody_events(nes, notes[lead_part], NesSong.PULSE1, INST_LEAD, true, length, stats, "Lead", arp_index)
	if accomp_part == PAD:
		events[1] = _chord_events(nes, notes[PAD], length, stats, arp_index)
		stats["arp_chords"].append(name)
	elif accomp_part == ARP:
		events[1] = _melody_events(nes, notes[ARP], NesSong.PULSE2, INST_ARP, true, length, stats, "Arp", arp_index)
	elif accomp_part == HARMONY:
		events[1] = _melody_events(nes, notes[HARMONY], NesSong.PULSE2, INST_HARMONY, true, length, stats, "Harmony", arp_index)
	if has[BASS]:
		events[2] = _melody_events(nes, notes[BASS], NesSong.TRIANGLE, INST_BASS, false, length, stats, "Bass", arp_index)
	if drums_on:
		events[3] = _drum_events(notes[DRUMS] + notes[NOISE], length, stats)

	var sources: Array = [
		[roles[lead_part]] if lead_part >= 0 else [],
		[roles[accomp_part]] if accomp_part >= 0 else [],
		[roles[BASS]] if has[BASS] else [],
		[roles[DRUMS], roles[NOISE]] if drums_on else [],
	]
	return {"events": events, "sources": sources}


## One note at a time: on each step the highest note wins (the lowest for
## the bass).
static func _melody_events(nes: NesSong, notes: Array, channel: int, instrument: int, highest: bool, length: int, stats: Dictionary, part: String, arp_index: Dictionary) -> Array:
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
		var fitted := NesSong.fit_note(channel, int(note[2]))
		if fitted["moved"]:
			stats["octave"][part] = int(stats["octave"].get(part, 0)) + 1
		var value: int = fitted["note"]
		var velocity := int(note[3]) if note.size() > 3 else 100
		var event := {
			"step": int(step),
			"length": maxi(int(note[1]), 1),
			"note": value,
			"midi": NesSong.midi_of(channel, value),
			"velocity": velocity,
			"instrument": instrument,
			"volume": _volume(instrument, velocity),
			"arp": -1,
		}
		if note.size() > 5 and note[5] is Array:
			event["arp"] = _arpeggio(nes, arp_index, note[5], value)
			event["offsets"] = note[5]
		events.append(event)
	return events


## Volume column for a note: the part's level, scaled by velocity.
static func _volume(instrument: int, velocity: int) -> int:
	if not PART_VOLUME.has(instrument):
		return 15
	return clampi(roundi(PART_VOLUME[instrument] * velocity / 100.0), 3, 15)


## The index of a looping arpeggio over [param offsets] (semitones from the
## note), made the first time it is needed. Offsets that would leave the
## note range are dropped. Returns -1 when nothing is left to arpeggiate.
static func _arpeggio(nes: NesSong, arp_index: Dictionary, offsets: Array, note: int) -> int:
	var values: Array = [0]
	for value in offsets:
		var o := int(value)
		if o != 0 and absi(o) <= 24 and not values.has(o) and note + o <= NesSong.LAST_NOTE and note + o >= NesSong.FIRST_NOTE:
			values.append(o)
	if values.size() < 2:
		return -1
	var key := ",".join(PackedStringArray(values.map(func(v: int) -> String: return str(v))))
	if not arp_index.has(key):
		arp_index[key] = nes.arpeggios.size()
		var label := "-".join(PackedStringArray(values.map(func(v: int) -> String: return str(v))))
		nes.arpeggios.append({"name": "Arp %s" % label, "values": values, "loop": 0})
	return arp_index[key]


## Pad chords become one note per chord with an arpeggio over its tones.
static func _chord_events(nes: NesSong, notes: Array, length: int, stats: Dictionary, arp_index: Dictionary) -> Array:
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
	var events: Array = []
	for step in steps:
		var chord: Array = by_step[step]
		var pitches: Array = []
		var longest := 1
		for note in chord:
			pitches.append(int(note[2]))
			longest = maxi(longest, int(note[1]))
		pitches.sort()
		var fitted := NesSong.fit_note(NesSong.PULSE2, int(pitches[0]))
		var root: int = fitted["note"]
		var top: int = root + int(pitches[pitches.size() - 1]) - int(pitches[0])
		if top > NesSong.LAST_NOTE:
			root -= 12
			fitted["moved"] = true
		if fitted["moved"]:
			stats["octave"]["Pad"] = int(stats["octave"].get("Pad", 0)) + 1
		var offsets: Array = []
		for p in pitches:
			offsets.append(int(p) - int(pitches[0]))
		events.append({
			"step": int(step),
			"length": longest,
			"note": root,
			"midi": NesSong.midi_of(NesSong.PULSE2, root),
			"velocity": 90,
			"instrument": INST_CHORDS,
			"volume": _volume(INST_CHORDS, 100),
			"arp": _arpeggio(nes, arp_index, offsets, root),
			"offsets": offsets,
		})
	return events


## All drums on the noise channel: one hit per step, by priority.
static func _drum_events(notes: Array, length: int, stats: Dictionary) -> Array:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		if step < 0 or step >= length:
			continue
		var drum := int(note[4]) if note.size() > 4 and int(note[4]) >= 0 else GbArranger.SNARE
		if not KIT_FOR.has(drum):
			drum = GbArranger.SNARE
		if by_step.has(step):
			stats["merged"] = int(stats["merged"]) + 1
			var current := int(by_step[step][4]) if by_step[step].size() > 4 else GbArranger.SNARE
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
		var velocity := int(hit[3])
		var piece: int = KIT_FOR[drum]
		if velocity <= 60 and SOFT_KIT.has(drum):
			piece = SOFT_KIT[drum]
		var index: int = KIT[piece]["index"]
		if drum == GbArranger.TOM:
			# Fills step down in pitch: follow them, a higher index is lower.
			index = clampi(9 - (int(hit[2]) - 50) / 4, 7, 11)
		events.append({
			"step": int(step),
			"length": 1,
			"note": noise_note(index),
			"midi": int(hit[2]),
			"velocity": velocity,
			"instrument": INST_KIT + piece,
			"volume": 15,
			"arp": -1,
			"drum": drum,
		})
	return events


## The noise note value for a period index. The engine plays
## ((note + offset) & 15) ^ 15, so notes 16 to 31 cover the indexes 15 to 0
## and a negative arpeggio lowers the pitch without wrapping round.
static func noise_note(index: int) -> int:
	return 16 + (15 - clampi(index, 0, 15))


## Turns a channel's events into notes. A note lasts its length, or until
## the next note starts. Drums ring out on their envelopes for the whole gap.
static func _to_notes(events: Array, rows: int) -> Array:
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["step"]) < int(b["step"]))
	var out: Array = []
	for k in events.size():
		var e: Dictionary = events[k]
		var start := int(e["step"])
		if start >= rows:
			continue
		var next_start := int(events[k + 1]["step"]) if k + 1 < events.size() else rows
		if next_start <= start:
			continue
		var length := mini(int(e["length"]), next_start - start)
		if e.has("drum"):
			length = next_start - start
		out.append({
			"row": start,
			"length": maxi(mini(length, rows - start), 1),
			"note": int(e["note"]),
			"instrument": int(e["instrument"]),
			"volume": int(e["volume"]),
			"arp": int(e["arp"]),
		})
	return out


## The arrangement as a four-channel ChipSong, with the original's sections,
## order, cues and states, at the tempo the engine plays.
static func _build_source(nes: NesSong, song: ChipSong, per_section: Array, speed: Dictionary) -> ChipSong:
	var data: Dictionary = song.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(float(speed["bpm"]), 0.0001)
	data["timing"]["swing"] = 0.0
	data["effects"] = {"echo": 0.0, "echo_feedback": 0.0, "echo_beats": 0.75}
	data["meta"]["target"] = "nes"
	data["instruments"] = [
		{"name": "Pulse 1", "wave": "pulse", "duty": NesApu.DUTY[int(nes.instruments[INST_LEAD]["duty"][0])], "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.02, "volume": 0.5},
		{"name": "Pulse 2", "wave": "pulse", "duty": NesApu.DUTY[int(nes.instruments[INST_ARP]["duty"][0])], "attack": 0.002, "decay": 0.15, "sustain": 0.5, "release": 0.02, "volume": 0.32},
		{"name": "Triangle", "wave": "triangle", "attack": 0.002, "decay": 0.1, "sustain": 1.0, "release": 0.02, "volume": 0.6},
		{"name": "Noise", "wave": "noise", "attack": 0.001, "decay": 0.12, "sustain": 0.0, "release": 0.02, "volume": 0.4},
	]
	var channels: Array = []
	for c in 4:
		channels.append({"name": NesSong.CHANNEL_NAMES[c], "instrument": c, "layer": "Drums" if c == 3 else NesSong.CHANNEL_NAMES[c], "volume": 1.0, "pan": 0.0, "polyphony": 1})
	data["channels"] = channels
	data["layers"] = [
		{"name": "Pulse 1", "channels": [0]},
		{"name": "Pulse 2", "channels": [1]},
		{"name": "Triangle", "channels": [2]},
		{"name": "Noise", "channels": [3]},
	]
	var patterns: Array = []
	var sections: Array = data["sections"]
	for i in sections.size():
		var ids: Array = []
		for c in 4:
			var notes: Array = []
			for e in per_section[i]["events"][c]:
				var note: Array = [int(e["step"]), int(e["length"]), int(e["midi"]), clampi(int(e["velocity"]), 1, 127)]
				if c == 3 and e.has("drum"):
					# The drum kind, so MIDI export can map it to a GM drum.
					note.append(int(e["drum"]))
				elif e.has("offsets") and int(e["arp"]) >= 0:
					note.append(-1)
					note.append(nes.arpeggios[int(e["arp"])]["values"].duplicate())
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


static func _write_report(nes: NesSong, song: ChipSong, stats: Dictionary, speed: Dictionary) -> void:
	var lines := PackedStringArray()
	var lead_line := "Pulse 1 plays the lead"
	var promoted: Array = stats["promoted"]
	if not promoted.is_empty():
		var parts: Array = []
		for entry in promoted:
			parts.append("%s in %s" % [entry[1], entry[0]])
		lead_line += ", and the %s where there is no lead" % ", ".join(PackedStringArray(parts))
	lines.append(lead_line + ".")
	var accomp: Dictionary = stats["accomp"]
	var accomp_parts: Array = []
	for part in accomp:
		var where := ", ".join(PackedStringArray(accomp[part]))
		if part == "Pad":
			accomp_parts.append("the Pad's chords as arpeggios in %s" % where)
		else:
			accomp_parts.append("the %s in %s" % [part, where])
	if not accomp_parts.is_empty():
		lines.append("Pulse 2 plays %s." % "; ".join(PackedStringArray(accomp_parts)))
	lines.append("Triangle plays the bass, at one volume (the triangle has no volume control).")
	lines.append("Noise plays every drum. DPCM is left free for your own samples.")
	var dropped: Dictionary = stats["dropped"]
	for part in dropped:
		lines.append("%s dropped in %s (no channel left)." % [part, ", ".join(PackedStringArray(dropped[part]))])
	if int(stats["merged"]) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step." % int(stats["merged"]))
	var octave: Dictionary = stats["octave"]
	for part in octave:
		lines.append("%d %s notes moved by an octave to fit the chip's range." % [int(octave[part]), part])
	var timing: Dictionary = song.data.get("timing", {})
	if float(timing.get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: the engine plays even rows.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the NES has none.")
	var groove := "-".join(PackedStringArray(Array(nes.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	var patterns := nes.pattern_chunks().size()
	lines.append("%d patterns of %d, %d notes, %d instruments and %d arpeggios." % [patterns, NesSong.MAX_PATTERNS, nes.note_count(), nes.instruments.size(), nes.arpeggios.size()])
	nes.report = lines
