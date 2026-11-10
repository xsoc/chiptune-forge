class_name GbArranger
extends RefCounted
## Fits a generated song into the Game Boy's four channels.
##
## Pulse 1 plays the lead. Pulse 2 plays one accompaniment part per section:
## the arpeggio if there is one, else the pad's chords as fast arpeggios (the
## classic chip trick), else the harmony line. The wave channel plays the
## bass and the noise channel plays every drum. Each channel plays one note
## at a time, notes move by octaves into the chip's range, and the tempo
## snaps to what the driver's timer can play. Everything it changes is
## listed in [member GbSong.report].

const LEAD := 0
const HARMONY := 1
const ARP := 2
const PAD := 3
const BASS := 4
const DRUMS := 5
const NOISE := 6
const PART_NAMES: PackedStringArray = ["Lead", "Harmony", "Arp", "Pad", "Bass", "Drums", "Noise"]

## Drum instrument indexes in generated songs (see [DrumWriter]).
const KICK := 5
const SNARE := 6
const HAT := 7
const OPEN_HAT := 8
const CRASH := 9
const TOM := 10
const RIDE := 11
## When two drums land on the same step, the earlier one in this list wins.
const DRUM_PRIORITY := [KICK, SNARE, CRASH, TOM, OPEN_HAT, HAT, RIDE]

## The noise drum kit: envelope (NR42), 7-bit LFSR, and the hUGE note that
## sets the pitch (NR43 through the driver's note table).
const KIT := [
	{"name": "Kick", "envelope": 0xF1, "narrow": false, "note": 29},
	{"name": "Snare", "envelope": 0xC1, "narrow": false, "note": 41},
	{"name": "Closed hat", "envelope": 0x61, "narrow": false, "note": 61},
	{"name": "Open hat", "envelope": 0x63, "narrow": false, "note": 60},
	{"name": "Crash", "envelope": 0x97, "narrow": false, "note": 53},
	{"name": "Tom", "envelope": 0xC2, "narrow": true, "note": 33},
	{"name": "Ride", "envelope": 0x52, "narrow": true, "note": 57},
	{"name": "Soft snare", "envelope": 0x71, "narrow": false, "note": 41},
	{"name": "Soft hat", "envelope": 0x31, "narrow": false, "note": 61},
]
const KIT_FOR := {KICK: 1, SNARE: 2, HAT: 3, OPEN_HAT: 4, CRASH: 5, TOM: 6, RIDE: 7}
const SOFT_KIT := {SNARE: 8, HAT: 9}

## Duty instrument numbers.
const INST_LEAD := 1
const INST_ARP := 2
const INST_CHORDS := 3
const INST_HARMONY := 4

## Options: sfx_channel (-1 none, 1 Pulse 2, 3 Noise) and sfx_free (leave
## that channel empty instead of sharing it).
static func arrange(song: ChipSong, options: Dictionary = {}) -> GbSong:
	var gb := GbSong.new()
	var data := song.data
	var timing: Dictionary = data.get("timing", {})
	var spb := song.get_steps_per_beat()
	gb.title = song.get_title()
	gb.steps_per_bar = spb * song.get_beats_per_bar()
	var speed := GbSong.choose_timing(song.get_bpm(), spb)
	gb.ticks_per_row = speed["ticks_per_row"]
	gb.timer_tac = speed["tac"]
	gb.timer_tma = speed["tma"]
	gb.tick_hz = speed["tick_hz"]
	gb.sfx_channel = int(options.get("sfx_channel", -1))
	gb.sfx_free = bool(options.get("sfx_free", false)) and gb.sfx_channel >= 0
	gb.looping = bool(timing.get("loop", true))

	var channels: Array = data.get("channels", [])
	var instruments: Array = data.get("instruments", [])
	var roles := _roles(channels)
	_design_instruments(gb, instruments, channels, roles)

	var stats := {"octave": {}, "merged": 0, "accomp": {}, "dropped": {}, "promoted": [], "arp_chords": []}
	var sections: Array = data.get("sections", [])
	var per_section: Array = []
	for i in sections.size():
		per_section.append(_arrange_section(gb, song, sections[i], roles, stats))

	# Lay the sections out in play order. A looping song stops at the loop
	# end: the driver jumps back from there, so an outro would never play.
	var order: Array = data.get("order", [])
	var loop_end := song.get_loop_end_step()
	var events: Array = [[], [], [], []]
	var row := 0
	for index in order:
		var section: Dictionary = sections[int(index)]
		var length := int(section.get("length", 0))
		if gb.looping and row >= loop_end:
			break
		gb.section_rows.append({"name": str(section.get("name", "")), "row": row, "length": length})
		var arranged: Dictionary = per_section[int(index)]
		gb.feeds.append({"row": row, "sources": arranged["sources"]})
		for c in 4:
			for e in arranged["events"][c]:
				var moved: Dictionary = e.duplicate()
				moved["step"] = int(e["step"]) + row
				events[c].append(moved)
		row += length
	gb.loop_start_row = song.get_loop_start_step() if gb.looping else 0
	gb.resize(row)
	for c in 4:
		_write_channel(gb, c, events[c])
	gb.source = _build_source(gb, song, per_section, speed)
	_write_report(gb, song, stats, speed)
	return gb


## Which source channel plays each part, by the channel names generated
## songs use. Missing parts are -1.
static func _roles(channels: Array) -> Dictionary:
	var roles := {}
	for part in PART_NAMES.size():
		roles[part] = -1
	for c in channels.size():
		var part := PART_NAMES.find(str(channels[c].get("name", "")))
		if part >= 0:
			roles[part] = c
	return roles


static func _design_instruments(gb: GbSong, instruments: Array, channels: Array, roles: Dictionary) -> void:
	var lead := _instrument_of(instruments, channels, roles[LEAD])
	var arp := _instrument_of(instruments, channels, roles[ARP])
	var harmony := _instrument_of(instruments, channels, roles[HARMONY])
	var bass := _instrument_of(instruments, channels, roles[BASS])
	gb.duty_instruments = [
		{"name": "Lead", "duty": _duty_code(lead), "envelope": _envelope(13, lead)},
		{"name": "Arp", "duty": _duty_code(arp), "envelope": _envelope(9, arp)},
		{"name": "Chords", "duty": 2, "envelope": 0x70},
		{"name": "Harmony", "duty": _duty_code(harmony), "envelope": _envelope(9, harmony)},
	]
	for inst in gb.duty_instruments:
		inst["sweep"] = 0x08
	var wave := 0
	match str(bass.get("wave", "triangle")):
		"saw":
			wave = 1
		"pulse", "square":
			wave = 2
	gb.wave_instruments = [{"name": "Bass", "level": 1, "wave": wave}]
	gb.waves = [_triangle_wave(), _saw_wave(), _square_wave()]
	gb.noise_instruments = []
	for drum in KIT:
		gb.noise_instruments.append({"name": drum["name"], "envelope": drum["envelope"], "narrow": drum["narrow"]})


static func _instrument_of(instruments: Array, channels: Array, channel: int) -> Dictionary:
	if channel < 0 or channel >= channels.size():
		return {}
	var index := int(channels[channel].get("instrument", -1))
	return instruments[index] if index >= 0 and index < instruments.size() else {}


## NRx1 duty code: 0 is 12.5 %, 1 is 25 %, 2 is 50 %, 3 is 75 %.
static func _duty_code(inst: Dictionary) -> int:
	match str(inst.get("wave", "pulse")):
		"pulse", "square":
			var duty := float(inst.get("duty", 0.5))
			if duty < 0.19:
				return 0
			if duty < 0.37:
				return 1
			return 2
		"saw":
			return 1
	return 2


## A hardware envelope (NRx2) for an instrument's ADSR: steady when it
## sustains, otherwise a fade to silence over about its decay time.
static func _envelope(volume: int, inst: Dictionary) -> int:
	var sustain := float(inst.get("sustain", 0.7))
	if sustain >= 0.6:
		return volume << 4
	var fade := float(inst.get("decay", 0.1)) * (1.0 + 3.0 * sustain) + 0.05
	var pace := clampi(roundi(fade * 64.0 / volume), 1, 7)
	return (volume << 4) | pace


static func _triangle_wave() -> PackedByteArray:
	var out := PackedByteArray()
	for i in 32:
		out.append(i if i < 16 else 31 - i)
	return out


static func _saw_wave() -> PackedByteArray:
	var out := PackedByteArray()
	for i in 32:
		out.append(15 - i / 2)
	return out


static func _square_wave() -> PackedByteArray:
	var out := PackedByteArray()
	for i in 32:
		out.append(15 if i < 16 else 0)
	return out


## Arranges one section. Returns {events: four arrays of note events,
## sources: the source channels feeding each Game Boy channel}.
static func _arrange_section(gb: GbSong, song: ChipSong, section: Dictionary, roles: Dictionary, stats: Dictionary) -> Dictionary:
	var name := str(section.get("name", ""))
	var length := int(section.get("length", 0))
	var notes := {}
	for part in PART_NAMES.size():
		notes[part] = _notes_of(song, section, roles[part])
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
	if gb.sfx_free and gb.sfx_channel == 1:
		accomp_part = -1
	if gb.sfx_free and gb.sfx_channel == 3:
		drums_on = false
	if accomp_part >= 0:
		_add_to(stats["accomp"], PART_NAMES[accomp_part], name)
	for part in [HARMONY, ARP, PAD]:
		if has[part] and part != lead_part and part != accomp_part:
			_add_to(stats["dropped"], PART_NAMES[part], name)

	var events: Array = [[], [], [], []]
	if lead_part >= 0:
		events[0] = _melody_events(notes[lead_part], 0, INST_LEAD, true, length, gb, stats, "Lead")
	if accomp_part == PAD:
		events[1] = _chord_events(notes[PAD], length, stats)
		stats["arp_chords"].append(name)
	elif accomp_part == ARP:
		events[1] = _melody_events(notes[ARP], 1, INST_ARP, true, length, gb, stats, "Arp")
	elif accomp_part == HARMONY:
		events[1] = _melody_events(notes[HARMONY], 1, INST_HARMONY, true, length, gb, stats, "Harmony")
	if has[BASS]:
		events[2] = _melody_events(notes[BASS], 2, 1, false, length, gb, stats, "Bass")
	if drums_on:
		events[3] = _drum_events(notes[DRUMS] + notes[NOISE], length, stats)

	var sources: Array = [
		[roles[lead_part]] if lead_part >= 0 else [],
		[roles[accomp_part]] if accomp_part >= 0 else [],
		[roles[BASS]] if has[BASS] else [],
		[roles[DRUMS], roles[NOISE]] if drums_on else [],
	]
	return {"events": events, "sources": sources}


static func _add_to(groups: Dictionary, key: String, section_name: String) -> void:
	if not groups.has(key):
		groups[key] = []
	if not groups[key].has(section_name):
		groups[key].append(section_name)


static func _notes_of(song: ChipSong, section: Dictionary, channel: int) -> Array:
	if channel < 0:
		return []
	var ids: Array = section.get("patterns", [])
	if channel >= ids.size() or int(ids[channel]) < 0:
		return []
	return song.data["patterns"][int(ids[channel])].get("notes", [])


## One note at a time: on each step the highest note wins (the lowest for
## the bass), and a note ends where the next begins.
static func _melody_events(notes: Array, channel: int, instrument: int, highest: bool, length: int, gb: GbSong, stats: Dictionary, part: String) -> Array:
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
	var base: int = GbSong.BASE_MIDI[channel]
	for step in steps:
		var note: Array = by_step[step]
		var midi := int(note[2])
		var pitch := midi - base
		var moved := false
		while pitch < 0:
			pitch += 12
			moved = true
		while pitch >= GbSong.LAST_NOTE:
			pitch -= 12
			moved = true
		if moved:
			stats["octave"][part] = int(stats["octave"].get(part, 0)) + 1
		var event := {
			"step": int(step),
			"length": maxi(int(note[1]), 1),
			"note": pitch,
			"midi": pitch + base,
			"velocity": int(note[3]) if note.size() > 3 else 100,
			"instrument": instrument,
			"arp": 0,
		}
		if note.size() > 5 and note[5] is Array:
			event["arp"] = _arp_param(note[5], pitch)
		events.append(event)
	return events


## hUGE arpeggio parameter (0xy) from semitone offsets: the driver plays the
## note, then +y, then +x, a tick each. Up to two offsets of 1 to 15.
static func _arp_param(offsets: Array, pitch: int) -> int:
	var ups: Array = []
	for value in offsets:
		var o := int(value)
		if o > 0 and o <= 15 and not ups.has(o) and pitch + o < GbSong.LAST_NOTE:
			ups.append(o)
	ups.sort()
	if ups.is_empty():
		return 0
	if ups.size() == 1:
		return ups[0] << 4
	return (ups[1] << 4) | ups[0]


## Pad chords become one note per chord with an arpeggio over its tones.
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
	var events: Array = []
	for step in steps:
		var chord: Array = by_step[step]
		var pitches: Array = []
		var longest := 1
		for note in chord:
			pitches.append(int(note[2]))
			longest = maxi(longest, int(note[1]))
		pitches.sort()
		var root: int = pitches[0] - GbSong.BASE_MIDI[1]
		var moved := false
		while root < 0:
			root += 12
			moved = true
		while root + 7 >= GbSong.LAST_NOTE:
			root -= 12
			moved = true
		if moved:
			stats["octave"]["Pad"] = int(stats["octave"].get("Pad", 0)) + 1
		var offsets: Array = []
		for p in pitches:
			offsets.append(int(p) - int(pitches[0]))
		events.append({
			"step": int(step),
			"length": longest,
			"note": root,
			"midi": root + GbSong.BASE_MIDI[1],
			"velocity": 90,
			"instrument": INST_CHORDS,
			"arp": _arp_param(offsets, root),
		})
	return events


## All drums on the noise channel: one hit per step, by priority.
static func _drum_events(notes: Array, length: int, stats: Dictionary) -> Array:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		if step < 0 or step >= length:
			continue
		var drum := int(note[4]) if note.size() > 4 and int(note[4]) >= 0 else SNARE
		if not KIT_FOR.has(drum):
			drum = SNARE
		if by_step.has(step):
			stats["merged"] = int(stats["merged"]) + 1
			var current := int(by_step[step][4]) if by_step[step].size() > 4 else SNARE
			if DRUM_PRIORITY.find(drum) >= DRUM_PRIORITY.find(current):
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
		var number: int = KIT_FOR[drum]
		if velocity <= 60 and SOFT_KIT.has(drum):
			number = SOFT_KIT[drum]
		var note: int = KIT[number - 1]["note"]
		if drum == TOM:
			# Fills step down in pitch: follow them, lower note = lower pitch.
			note = clampi(33 + (int(hit[2]) - 50) / 2, 26, 40)
		events.append({
			"step": int(step),
			"length": 1,
			"note": note,
			"midi": int(hit[2]),
			"velocity": velocity,
			"instrument": number,
			"arp": 0,
			"drum": drum,
		})
	return events


## Writes a channel's events into tracker rows: note, instrument and effect
## on the first row, the arpeggio or vibrato on every row it lasts, and a
## note cut (E00) where a note ends before the next one starts.
static func _write_channel(gb: GbSong, channel: int, events: Array) -> void:
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["step"]) < int(b["step"]))
	var rows := gb.row_count
	var default_volume := {}
	for i in gb.duty_instruments.size():
		default_volume[i + 1] = int(gb.duty_instruments[i]["envelope"]) >> 4
	var vibrato := _vibrato_param(gb) if channel == 0 else 0
	var vibrato_delay := 2 * maxi(gb.steps_per_bar / 16, 1)
	for k in events.size():
		var e: Dictionary = events[k]
		var start := int(e["step"])
		if start >= rows:
			continue
		var next_start := int(events[k + 1]["step"]) if k + 1 < events.size() else rows
		if next_start <= start:
			continue
		var end := mini(mini(start + int(e["length"]), next_start), rows)
		var arp := int(e.get("arp", 0))
		var instrument := int(e["instrument"])
		var effect := 0
		var param := 0
		if arp != 0:
			param = arp
		elif channel <= 1 and default_volume.has(instrument):
			# Accents and soft notes: set this note's volume (Cxy).
			var full: int = default_volume[instrument]
			var volume := clampi(roundi(full * int(e["velocity"]) / 100.0), 3, 15)
			if absi(volume - full) >= 2:
				effect = GbSong.FX_SET_VOLUME
				param = volume
		gb.set_cell(channel, start, int(e["note"]), instrument, effect, param)
		for r in range(start + 1, end):
			if arp != 0:
				gb.set_effect(channel, r, GbSong.FX_ARPEGGIO, arp)
			elif vibrato != 0 and end - start >= 6 and r - start >= vibrato_delay:
				gb.set_effect(channel, r, GbSong.FX_VIBRATO, vibrato)
		# Drums ring out on their envelopes; tones stop where the note ends.
		if channel != 3 and end < next_start and end < rows:
			gb.set_effect(channel, end, GbSong.FX_NOTE_CUT, 0)


## hUGE vibrato (4xy) for the lead: x picks the speed (a mask on the tick
## counter), y the depth in period units. About 7 Hz, a quarter tone deep.
static func _vibrato_param(gb: GbSong) -> int:
	var speed := 4 if gb.tick_hz < 90.0 else 8
	return (speed << 4) | 2


## The arrangement as a four-channel ChipSong, with the original's sections,
## order, cues and states, at the tempo the driver plays.
static func _build_source(gb: GbSong, song: ChipSong, per_section: Array, speed: Dictionary) -> ChipSong:
	var data: Dictionary = song.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(float(speed["bpm"]), 0.0001)
	data["timing"]["swing"] = 0.0
	data["effects"] = {"echo": 0.0, "echo_feedback": 0.0, "echo_beats": 0.75}
	data["meta"]["target"] = "gameboy"
	data["instruments"] = [
		{"name": "Pulse 1", "wave": "pulse", "duty": GbApu.DUTY[gb.duty_instruments[0]["duty"]], "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.02, "volume": 0.5},
		{"name": "Pulse 2", "wave": "pulse", "duty": GbApu.DUTY[gb.duty_instruments[1]["duty"]], "attack": 0.002, "decay": 0.15, "sustain": 0.5, "release": 0.02, "volume": 0.32},
		{"name": "Wave", "wave": "wave", "table": Array(gb.waves[gb.wave_instruments[0]["wave"]]), "attack": 0.002, "decay": 0.1, "sustain": 1.0, "release": 0.02, "volume": 0.6},
		{"name": "Noise", "wave": "noise", "attack": 0.001, "decay": 0.12, "sustain": 0.0, "release": 0.02, "volume": 0.4},
	]
	var channels: Array = []
	for c in 4:
		channels.append({"name": GbSong.CHANNEL_NAMES[c], "instrument": c, "layer": "Drums" if c == 3 else GbSong.CHANNEL_NAMES[c], "volume": 1.0, "pan": 0.0, "polyphony": 1})
	data["channels"] = channels
	data["layers"] = [
		{"name": "Pulse 1", "channels": [0]},
		{"name": "Pulse 2", "channels": [1]},
		{"name": "Wave", "channels": [2]},
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
				var arp := int(e.get("arp", 0))
				if c == 3 and e.has("drum"):
					# The drum kind, so MIDI export can map it to a GM drum.
					note.append(int(e["drum"]))
				elif arp != 0:
					note.append(-1)
					note.append([0, arp & 0x0F, arp >> 4] if arp & 0x0F else [0, arp >> 4])
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


static func _write_report(gb: GbSong, song: ChipSong, stats: Dictionary, speed: Dictionary) -> void:
	var lines := PackedStringArray()
	var accomp: Dictionary = stats["accomp"]
	var lead_line := "Pulse 1 plays the lead"
	var promoted: Array = stats["promoted"]
	if not promoted.is_empty():
		var parts: Array = []
		for entry in promoted:
			parts.append("%s in %s" % [entry[1], entry[0]])
		lead_line += ", and the %s where there is no lead" % ", ".join(PackedStringArray(parts))
	lines.append(lead_line + ".")
	var accomp_parts: Array = []
	for part in accomp:
		var where := ", ".join(PackedStringArray(accomp[part]))
		if part == "Pad":
			accomp_parts.append("the Pad's chords as arpeggios in %s" % where)
		else:
			accomp_parts.append("the %s in %s" % [part, where])
	if gb.sfx_free and gb.sfx_channel == 1:
		lines.append("Pulse 2 is kept free for sound effects.")
	elif not accomp_parts.is_empty():
		lines.append("Pulse 2 plays %s." % "; ".join(PackedStringArray(accomp_parts)))
	lines.append("Wave plays the bass.")
	if gb.sfx_free and gb.sfx_channel == 3:
		lines.append("Noise is kept free for sound effects, so there are no drums.")
	else:
		lines.append("Noise plays every drum.")
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
		lines.append("Swing straightened: the driver plays even rows.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the Game Boy has none.")
	lines.append("Tempo %s BPM plays at %.1f BPM (%d ticks per row on the timer)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), int(speed["ticks_per_row"])])
	if gb.sfx_channel >= 0 and not gb.sfx_free:
		lines.append("%s is marked safe for sound effects to interrupt." % GbSong.CHANNEL_NAMES[gb.sfx_channel])
	var size := gb.data_size()
	var size_line := "Song data %.1f KB of a %d KB ROM bank." % [size / 1024.0, GbSong.BANK_BYTES / 1024]
	if size > GbSong.BANK_BYTES:
		size_line = "Song data %.1f KB is more than one %d KB ROM bank: make the song shorter, or split it across banks yourself." % [size / 1024.0, GbSong.BANK_BYTES / 1024]
	lines.append(size_line)
	gb.report = lines
