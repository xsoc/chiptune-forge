class_name PceArranger
extends RefCounted
## Fits a generated song onto the PC Engine's six wavetable channels.
##
## Starts from the Mega Drive arrangement ([MdArranger]), which already has
## one channel per part, and moves it onto the six channels: lead, harmony,
## arpeggio and bass keep a channel each, the pad plays its chords' top
## note, and the drums share channel 6, which switches between noise (snare,
## hats and cymbals) and a sine wave with a falling pitch (kick and toms).
## Each part gets a waveform chosen from its wave in the source song and a
## volume envelope from its ADSR; the lead gets a delayed vibrato.

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
const INST_SOFT_SNARE := 12
const INST_SOFT_HAT := 13
## Level (0 to 15, 2 dB steps) for each instrument at velocity 100.
const PART_LEVEL := {INST_LEAD: 15, INST_HARMONY: 12, INST_ARP: 11, INST_BASS: 15, INST_PAD: 10, INST_KICK: 15, INST_TOM: 14}
## Noise drums: the [NesArranger.KIT] piece whose volume envelope it uses,
## and its noise frequency (31 is the highest).
const NOISE_DRUMS := {
	INST_SNARE: [1, 22], INST_HAT: [2, 30], INST_OPEN_HAT: [3, 30], INST_CRASH: [4, 27],
	INST_RIDE: [6, 29], INST_SOFT_SNARE: [7, 22], INST_SOFT_HAT: [8, 30],
}
const DRUM_INSTRUMENT := {
	GbArranger.KICK: INST_KICK, GbArranger.SNARE: INST_SNARE, GbArranger.TOM: INST_TOM,
	GbArranger.HAT: INST_HAT, GbArranger.OPEN_HAT: INST_OPEN_HAT, GbArranger.CRASH: INST_CRASH,
	GbArranger.RIDE: INST_RIDE,
}
const SOFT_DRUM := {INST_SNARE: INST_SOFT_SNARE, INST_HAT: INST_SOFT_HAT}
## Kick and tom: sine notes that fall in pitch (semitones per frame).
const KICK_NOTE := MdArranger.KICK_NOTE
const KICK_DROP := [24, 17, 12, 8, 5, 3, 1, 0]
const KICK_VOLUME := [15, 15, 14, 13, 11, 9, 7, 5, 3, 1, 0]
const TOM_DROP := [7, 4, 2, 1, 0, -1, -2]
const TOM_VOLUME := [15, 14, 13, 12, 11, 10, 9, 7, 5, 3, 1, 0]
## Mega Drive channels feeding each channel.
const FROM_MD := [[MdSong.FM1], [MdSong.FM2], [MdSong.FM3], [MdSong.FM4], [MdSong.SQUARE1, MdSong.SQUARE2, MdSong.SQUARE3], [MdSong.FM5, MdSong.MD_NOISE]]
## The lead's vibrato: after this many frames, in sixteenths of a semitone.
const VIBRATO_DELAY := 12
const VIBRATO := [1, 2, 1, 0, -1, -2, -1, 0]


static func arrange(song: ChipSong) -> PceSong:
	var md := MdArranger.arrange(song)
	var src: ChipSong = md.source
	var pce := PceSong.new()
	var data := song.data
	var spb := song.get_steps_per_beat()
	pce.title = song.get_title()
	pce.steps_per_beat = spb
	pce.steps_per_bar = md.steps_per_bar
	var speed := NesSong.choose_groove(song.get_bpm(), spb, PceSong.FRAME_HZ)
	pce.groove = speed["groove"]
	pce.looping = md.looping
	var channels: Array = data.get("channels", [])
	var instruments: Array = data.get("instruments", [])
	var roles := GbArranger._roles(channels)
	_design_instruments(pce, instruments, channels, roles)

	var stats := {"pad_notes": 0, "merged": 0, "octave": {}}
	var md_sections: Array = src.data.get("sections", [])
	var md_patterns: Array = src.data.get("patterns", [])
	var arp_index := {}
	var per_section: Array = []
	for section in md_sections:
		per_section.append(_arrange_section(pce, section, md_patterns, stats, arp_index))

	var order: Array = src.data.get("order", [])
	var events: Array = []
	for c in PceSong.CHANNEL_COUNT:
		events.append([])
	var row := 0
	var loop_end := song.get_loop_end_step()
	for index in order:
		var section: Dictionary = md_sections[int(index)]
		var length := int(section.get("length", 0))
		if pce.looping and row >= loop_end:
			break
		pce.section_rows.append({"name": str(section.get("name", "")), "row": row, "length": length})
		for c in PceSong.CHANNEL_COUNT:
			for e in per_section[int(index)][c]:
				var moved: Dictionary = e.duplicate()
				moved["step"] = int(e["step"]) + row
				events[c].append(moved)
		row += length
	pce.row_count = row
	pce.loop_start_row = md.loop_start_row
	for c in PceSong.CHANNEL_COUNT:
		pce.notes[c] = NesArranger._to_notes(events[c], row)
	for feed in md.feeds:
		var sources: Array = []
		for c in PceSong.CHANNEL_COUNT:
			var merged: Array = []
			for md_channel in FROM_MD[c]:
				for s in feed["sources"][md_channel]:
					if not merged.has(s):
						merged.append(s)
			sources.append(merged)
		pce.feeds.append({"row": feed["row"], "sources": sources})
	pce.source = _build_source(pce, song, per_section, float(speed["bpm"]))
	pce.stats = stats
	_write_report(pce, song, md, stats, speed)
	return pce


## The waveform for a part's wave in the source song.
static func wave_name(inst: Dictionary, bass := false) -> String:
	var wave := str(inst.get("wave", "pulse"))
	if bass:
		match wave:
			"saw":
				return "saw"
			"pulse", "square":
				return "soft_square"
		return "triangle"
	match wave:
		"pulse":
			var duty := float(inst.get("duty", 0.5))
			if duty <= 0.15 or duty >= 0.85:
				return "pulse12"
			if duty <= 0.35 or duty >= 0.65:
				return "pulse25"
			return "square"
		"square", "saw", "triangle", "sine":
			return wave
	return "square"


## Levels for an ADSR from the source song, one per frame, as the NES
## arranger makes them.
static func adsr_levels(inst: Dictionary) -> Array:
	var out: Array = []
	for v in NesArranger.adsr_envelope(inst):
		out.append(SmsSong.level_of(float(v)))
	return out


static func _design_instruments(pce: PceSong, instruments: Array, channels: Array, roles: Dictionary) -> void:
	var lead := GbArranger._instrument_of(instruments, channels, roles[GbArranger.LEAD])
	var harmony := GbArranger._instrument_of(instruments, channels, roles[GbArranger.HARMONY])
	var arp := GbArranger._instrument_of(instruments, channels, roles[GbArranger.ARP])
	var bass := GbArranger._instrument_of(instruments, channels, roles[GbArranger.BASS])
	var pad := GbArranger._instrument_of(instruments, channels, roles[GbArranger.PAD])
	var depth := clampi(roundi(float(lead.get("vibrato_depth", 0.2)) * 8.0), 1, 2)
	var pitch: Array = []
	for i in VIBRATO_DELAY:
		pitch.append(0)
	for v in VIBRATO:
		pitch.append(int(v) * depth)
	var pad_wave := "organ" if str(pad.get("wave", "pulse")) in ["saw", "triangle", "sine"] else "soft_square"
	pce.instruments = [
		{"name": "Lead", "wave": pce.wave_index(wave_name(lead)), "volume": adsr_levels(lead), "pitch": pitch, "pitch_loop": VIBRATO_DELAY},
		{"name": "Harmony", "wave": pce.wave_index(wave_name(harmony)), "volume": adsr_levels(harmony)},
		{"name": "Arp", "wave": pce.wave_index(wave_name(arp)), "volume": adsr_levels(arp)},
		{"name": "Bass", "wave": pce.wave_index(wave_name(bass, true)), "volume": adsr_levels(bass)},
		{"name": "Pad", "wave": pce.wave_index(pad_wave), "volume": adsr_levels(pad)},
		{"name": "Kick", "wave": pce.wave_index("sine"), "volume": KICK_VOLUME.duplicate(), "arp": KICK_DROP.duplicate()},
	]
	var sine := pce.wave_index("sine")
	for inst in [INST_SNARE, INST_TOM, INST_HAT, INST_OPEN_HAT, INST_CRASH, INST_RIDE, INST_SOFT_SNARE, INST_SOFT_HAT]:
		if inst == INST_TOM:
			pce.instruments.append({"name": "Tom", "wave": sine, "volume": TOM_VOLUME.duplicate(), "arp": TOM_DROP.duplicate()})
			continue
		var drum: Dictionary = NesArranger.KIT[NOISE_DRUMS[inst][0]]
		var volume: Array = []
		for v in drum["volume"]:
			volume.append(SmsSong.level_of(float(v)))
		pce.instruments.append({"name": str(drum["name"]), "wave": sine, "noise": true, "volume": volume})


## One section's events per channel, from the Mega Drive patterns.
static func _arrange_section(pce: PceSong, section: Dictionary, patterns: Array, stats: Dictionary, arp_index: Dictionary) -> Array:
	var ids: Array = section.get("patterns", [])
	var md_notes := func(md_channel: int) -> Array:
		if md_channel >= ids.size() or int(ids[md_channel]) < 0:
			return []
		return patterns[int(ids[md_channel])]["notes"]
	var out: Array = []
	for c in PceSong.CHANNEL_COUNT:
		out.append([])
	out[PceSong.LEAD] = _line(pce, md_notes.call(MdSong.FM1), INST_LEAD, stats, arp_index)
	out[PceSong.HARMONY] = _line(pce, md_notes.call(MdSong.FM2), INST_HARMONY, stats, arp_index)
	out[PceSong.ARP] = _line(pce, md_notes.call(MdSong.FM3), INST_ARP, stats, arp_index)
	out[PceSong.BASS] = _line(pce, md_notes.call(MdSong.FM4), INST_BASS, stats, arp_index)
	out[PceSong.PAD] = _pad(pce, md_notes.call(MdSong.SQUARE1) + md_notes.call(MdSong.SQUARE2) + md_notes.call(MdSong.SQUARE3), stats)
	out[PceSong.DRUMS] = _drums(md_notes.call(MdSong.FM5) + md_notes.call(MdSong.MD_NOISE), stats)
	return out


## Level for a note: the part's level, 2 dB lower for each 0.8x velocity.
static func _volume(instrument: int, velocity: int) -> int:
	var base: int = PART_LEVEL.get(instrument, 15)
	return clampi(base + roundi(10.0 * log(maxf(velocity, 1) / 100.0) / log(10.0)), 1, 15)


static func _fit(pce: PceSong, instrument: int, midi: int, stats: Dictionary) -> int:
	var fitted := PceSong.fit(midi)
	if fitted["moved"]:
		var part := str(pce.instruments[instrument]["name"])
		stats["octave"][part] = int(stats["octave"].get(part, 0)) + 1
	return fitted["note"]


static func _line(pce: PceSong, notes: Array, instrument: int, stats: Dictionary, arp_index: Dictionary) -> Array:
	var events: Array = []
	for note in notes:
		var velocity := int(note[3]) if note.size() > 3 else 100
		var value := _fit(pce, instrument, int(note[2]), stats)
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
			event["arp"] = _arpeggio(pce, arp_index, note[5], value)
		events.append(event)
	return events


## The index of a looping arpeggio over [param offsets], or -1 when nothing
## is left to arpeggiate.
static func _arpeggio(pce: PceSong, arp_index: Dictionary, offsets: Array, note: int) -> int:
	var values: Array = [0]
	for value in offsets:
		var o := int(value)
		if o != 0 and absi(o) <= 24 and not values.has(o) and note + o <= PceSong.HIGHEST_NOTE and note + o >= PceSong.LOWEST_NOTE:
			values.append(o)
	if values.size() < 2:
		return -1
	var key := ",".join(PackedStringArray(values.map(func(v: int) -> String: return str(v))))
	if not arp_index.has(key):
		arp_index[key] = pce.arpeggios.size()
		pce.arpeggios.append({"name": "Arp %s" % key.replace(",", " "), "values": values, "loop": 0})
	return arp_index[key]


## The pad's top note at each step.
static func _pad(pce: PceSong, notes: Array, stats: Dictionary) -> Array:
	var by_step := {}
	for note in notes:
		var step := int(note[0])
		if not by_step.has(step):
			by_step[step] = note
		else:
			stats["pad_notes"] = int(stats["pad_notes"]) + 1
			if int(note[2]) > int(by_step[step][2]):
				by_step[step] = note
	var steps := by_step.keys()
	steps.sort()
	var events: Array = []
	for step in steps:
		var note: Array = by_step[step]
		var velocity := int(note[3]) if note.size() > 3 else 90
		var value := _fit(pce, INST_PAD, int(note[2]), stats)
		events.append({
			"step": int(step),
			"length": maxi(int(note[1]), 1),
			"note": value,
			"midi": value,
			"velocity": velocity,
			"instrument": INST_PAD,
			"volume": _volume(INST_PAD, velocity),
			"arp": -1,
		})
	return events


## All drums on channel 6: one hit per step, by the usual priority.
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
		if velocity <= 60 and SOFT_DRUM.has(instrument):
			instrument = SOFT_DRUM[instrument]
		var note := KICK_NOTE
		var volume := 15
		if NOISE_DRUMS.has(instrument):
			note = NOISE_DRUMS[instrument][1]
		elif instrument == INST_TOM:
			note = clampi(43 + (int(hit[2]) - 50) / 2, 36, 52)
			volume = _volume(instrument, velocity)
		else:
			volume = _volume(instrument, velocity)
		events.append({
			"step": int(step),
			"length": 1,
			"note": note,
			"midi": int(hit[2]),
			"velocity": velocity,
			"instrument": instrument,
			"volume": volume,
			"arp": -1,
			"drum": drum,
		})
	return events


## The arrangement as a six-channel ChipSong, with the original's sections,
## order, cues and states, at the tempo the console plays.
static func _build_source(pce: PceSong, song: ChipSong, per_section: Array, bpm: float) -> ChipSong:
	var data: Dictionary = song.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(bpm, 0.0001)
	data["timing"]["swing"] = 0.0
	data["effects"] = {"echo": 0.0, "echo_feedback": 0.0, "echo_beats": 0.75}
	data["meta"]["target"] = "pce"
	var insts: Array = []
	var channels: Array = []
	var layers: Array = []
	for c in PceSong.CHANNEL_COUNT:
		var name := PceSong.PCE_CHANNEL_NAMES[c]
		var wave := "noise" if c == PceSong.DRUMS else ("triangle" if c == PceSong.BASS else "pulse")
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
		for c in PceSong.CHANNEL_COUNT:
			var notes: Array = []
			for e in per_section[i][c]:
				var note: Array = [int(e["step"]), int(e["length"]), int(e["midi"]), clampi(int(e["velocity"]), 1, 127)]
				if e.has("drum"):
					note.append(int(e["drum"]))
				elif int(e["arp"]) >= 0:
					note.append(-1)
					note.append(pce.arpeggios[int(e["arp"])]["values"].duplicate())
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


static func _write_report(pce: PceSong, song: ChipSong, md: MdSong, stats: Dictionary, speed: Dictionary) -> void:
	var lines := PackedStringArray()
	var wave := func(index: int) -> String: return pce.wave_names[int(pce.instruments[index]["wave"])].replace("_", " ")
	lines.append("Channel 1 plays the lead (%s wave, with vibrato on long notes), channel 2 the harmony (%s) and channel 3 the arpeggio (%s)." % [wave.call(INST_LEAD), wave.call(INST_HARMONY), wave.call(INST_ARP)])
	lines.append("Channel 4 plays the bass (%s) and channel 5 the pad's top note (%s)." % [wave.call(INST_BASS), wave.call(INST_PAD)])
	lines.append("Channel 6 plays the drums: noise for the snare, hats and cymbals, and a falling sine for the kick and toms.")
	for promoted in md.stats.get("promoted", []):
		lines.append("The %s plays the lead in %s, where there is none." % [str(promoted[1]).to_lower(), promoted[0]])
	if int(stats["pad_notes"]) > 0:
		lines.append("%d pad notes dropped: the pad plays one note at a time." % int(stats["pad_notes"]))
	if int(stats["merged"]) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step." % int(stats["merged"]))
	var octave: Dictionary = stats["octave"]
	for part in octave:
		lines.append("%d %s notes moved by an octave to fit the chip's range." % [int(octave[part]), part])
	var timing: Dictionary = song.data.get("timing", {})
	if float(timing.get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: the player plays even frames.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the PC Engine has none.")
	var groove := "-".join(PackedStringArray(Array(pce.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	pce.report = lines
