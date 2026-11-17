class_name OplArranger
extends RefCounted
## Fits a generated song to a PC sound card's FM chip.
##
## The parts come from the Mega Drive arrangement ([MdArranger]), which
## already gives every part its own line: lead, harmony, arpeggio and bass,
## the pad's chords as up to three notes, and the drums split by kind. Here
## they go onto the OPL's channels:[br]
## - AdLib and Sound Blaster (one OPL2): six melodic channels (lead,
##   harmony, arpeggio, bass and two pad notes) and the rhythm mode's bass
##   drum, snare, tom, cymbal and hi-hat on channels 7 to 9.[br]
## - Sound Blaster Pro (two OPL2s, one per speaker): the same on the left,
##   and on the right the lead again a few cents sharp for width, the
##   arpeggio instead of the harmony, and the pad's third note.[br]
## - Sound Blaster 16 (OPL3): the left and right voices of the Pro on one
##   chip's eighteen channels, panned, with the OPL3's extra waveforms.

const LEAD := 0
const HARMONY := 1
const ARP := 2
const BASS := 3
const PAD := 4
const BD := 5
const SD := 6
const TOM := 7
const CYM := 8
const HH := 9

## Mega Drive drum instruments to rhythm pieces. FM 5 holds the kick, snare
## and toms; the noise channel's kit holds the snare, hats and cymbals.
const MD_DRUM := {
	MdArranger.INST_KICK: "bd",
	MdArranger.INST_SNARE: "sd",
	MdArranger.INST_TOM: "tom",
	MdArranger.INST_NOISE_KIT: "sd",
	MdArranger.INST_NOISE_KIT + 1: "hh",
	MdArranger.INST_NOISE_KIT + 2: "hh",
	MdArranger.INST_NOISE_KIT + 3: "cym",
	MdArranger.INST_NOISE_KIT + 4: "cym",
	MdArranger.INST_NOISE_KIT + 5: "sd",
	MdArranger.INST_NOISE_KIT + 6: "hh",
}
## Rhythm instrument index for each piece.
const DRUM_INST := {"bd": BD, "sd": SD, "tom": TOM, "cym": CYM, "hh": HH}


## The voices of each chip layout: [name, Mega Drive channel or drum, bank,
## channel, detune in cents, pan].
static func layout_for(chip: String) -> Array:
	var drums := func(bank: int, pan: String) -> Array:
		var out: Array = []
		for d in OplSong.DRUMS:
			out.append({"name": OplSong.DRUM_NAMES[d] + (" (right)" if bank == 1 and chip == "dual_opl2" else ""), "src": -1, "bank": bank, "ch": -1, "drum": d, "detune": 0, "pan": pan})
		return out
	var voice := func(name: String, src: int, bank: int, ch: int, detune := 0, pan := "LR") -> Dictionary:
		return {"name": name, "src": src, "bank": bank, "ch": ch, "drum": "", "detune": detune, "pan": pan}
	match chip:
		"dual_opl2":
			var out: Array = [
				voice.call("Lead (left)", MdSong.FM1, 0, 0),
				voice.call("Harmony (left)", MdSong.FM2, 0, 1),
				voice.call("Bass (left)", MdSong.FM4, 0, 3),
				voice.call("Pad 1 (left)", MdSong.SQUARE1, 0, 4),
				voice.call("Pad 2 (left)", MdSong.SQUARE2, 0, 5),
			]
			out.append_array(drums.call(0, "LR"))
			out.append_array([
				voice.call("Lead (right)", MdSong.FM1, 1, 0, 6),
				voice.call("Arpeggio (right)", MdSong.FM3, 1, 2),
				voice.call("Bass (right)", MdSong.FM4, 1, 3),
				voice.call("Pad 1 (right)", MdSong.SQUARE1, 1, 4),
				voice.call("Pad 3 (right)", MdSong.SQUARE3, 1, 5),
			])
			out.append_array(drums.call(1, "LR"))
			return out
		"opl3":
			var out: Array = [
				voice.call("Lead", MdSong.FM1, 0, 0),
				voice.call("Harmony", MdSong.FM2, 0, 1, 0, "L"),
				voice.call("Arpeggio", MdSong.FM3, 0, 2, 0, "R"),
				voice.call("Bass", MdSong.FM4, 0, 3),
				voice.call("Pad 1", MdSong.SQUARE1, 0, 4, 0, "L"),
				voice.call("Pad 2", MdSong.SQUARE2, 0, 5, 0, "R"),
			]
			out.append_array(drums.call(0, "LR"))
			out.append_array([
				voice.call("Lead double", MdSong.FM1, 1, 0, 7),
				voice.call("Pad 3", MdSong.SQUARE3, 1, 1),
			])
			return out
	var out: Array = [
		voice.call("Lead", MdSong.FM1, 0, 0),
		voice.call("Harmony", MdSong.FM2, 0, 1),
		voice.call("Arpeggio", MdSong.FM3, 0, 2),
		voice.call("Bass", MdSong.FM4, 0, 3),
		voice.call("Pad 1", MdSong.SQUARE1, 0, 4),
		voice.call("Pad 2", MdSong.SQUARE2, 0, 5),
	]
	out.append_array(drums.call(0, "LR"))
	return out


static func arrange(song: ChipSong, card := "adlib") -> OplSong:
	var md := MdArranger.arrange(song)
	var opl := OplSong.new()
	opl.card = card
	opl.chip = PcCards.chip_of(card)
	opl.title = md.title
	opl.steps_per_beat = md.steps_per_beat
	opl.steps_per_bar = md.steps_per_bar
	var speed := NesSong.choose_groove(song.get_bpm(), md.steps_per_beat, OplSong.FRAME_HZ)
	opl.groove = speed["groove"]
	opl.looping = md.looping
	opl.row_count = md.row_count
	opl.loop_start_row = md.loop_start_row
	opl.section_rows = md.section_rows.duplicate(true)
	opl.arpeggios = md.arpeggios.duplicate(true)
	opl.stats = md.stats
	_design_instruments(opl, song)
	var layout := layout_for(opl.chip)
	var src_of := PackedInt32Array()
	var dropped := 0
	for v in layout:
		var drum := str(v["drum"])
		var list: Array = []
		if drum == "":
			var src := int(v["src"])
			src_of.append(src)
			for n in md.notes[src]:
				var moved: Dictionary = n.duplicate()
				moved["instrument"] = _part_of(src)
				moved["note"] = _fit(int(n["note"]))
				list.append(moved)
		else:
			src_of.append(MdSong.FM5 if drum in ["bd", "tom"] else MdSong.MD_NOISE)
			list = _drum_notes(md, drum, opl.row_count)
		opl.notes.append(list)
		var entry: Dictionary = v.duplicate()
		entry.erase("src")
		opl.layout.append(entry)
	# Feeds: each voice takes the source channels of the Mega Drive channel
	# it came from (both drum channels for the drums).
	for feed in md.feeds:
		var sources: Array = []
		for i in layout.size():
			if str(layout[i]["drum"]) != "":
				var both: Array = feed["sources"][MdSong.FM5].duplicate()
				for c in feed["sources"][MdSong.MD_NOISE]:
					if not both.has(c):
						both.append(c)
				sources.append(both)
			else:
				sources.append(feed["sources"][src_of[i]])
		opl.feeds.append({"row": feed["row"], "sources": sources})
	if opl.chip == "opl2" or opl.chip == "dual_opl2":
		for n in md.notes[MdSong.SQUARE3]:
			if opl.chip == "opl2":
				dropped += 1
	opl.source = _build_source(opl, md, song, speed)
	_write_report(opl, song, speed, dropped)
	return opl


static func _part_of(md_channel: int) -> int:
	match md_channel:
		MdSong.FM1:
			return LEAD
		MdSong.FM2:
			return HARMONY
		MdSong.FM3:
			return ARP
		MdSong.FM4:
			return BASS
	return PAD


static func _fit(midi: int) -> int:
	var note := midi
	while note < OplSong.LOWEST:
		note += 12
	while note > OplSong.HIGHEST:
		note -= 12
	return note


static func _design_instruments(opl: OplSong, song: ChipSong) -> void:
	var instruments: Array = song.data.get("instruments", [])
	var channels: Array = song.data.get("channels", [])
	var roles := GbArranger._roles(channels)
	var wave := func(part: int) -> String:
		return str(GbArranger._instrument_of(instruments, channels, roles[part]).get("wave", "pulse"))
	var patches := [
		OplPatches.lead(wave.call(GbArranger.LEAD)),
		OplPatches.harmony(wave.call(GbArranger.HARMONY)),
		OplPatches.arp(wave.call(GbArranger.ARP)),
		OplPatches.bass(wave.call(GbArranger.BASS)),
		OplPatches.pad(),
	]
	opl.instruments = []
	for p in patches:
		var patch: Dictionary = OplPatches.for_opl3(p) if opl.chip == "opl3" else p
		opl.instruments.append({"name": patch["name"], "opl": patch})
	opl.instruments.append({"name": "Bass drum", "opl": OplPatches.bass_drum(), "drum": "bd"})
	opl.instruments.append({"name": "Snare", "op": OplPatches.snare(), "drum": "sd"})
	opl.instruments.append({"name": "Tom", "op": OplPatches.tom(), "drum": "tom"})
	opl.instruments.append({"name": "Cymbal", "op": OplPatches.cymbal(), "drum": "cym"})
	opl.instruments.append({"name": "Hi-hat", "op": OplPatches.hi_hat(), "drum": "hh"})


## One rhythm piece's notes from the Mega Drive drum channels. A hit on
## both channels in the same row plays once, at the louder level.
static func _drum_notes(md: MdSong, drum: String, rows: int) -> Array:
	var hits := {}
	for c in [MdSong.FM5, MdSong.MD_NOISE]:
		for n in md.notes[c]:
			if str(MD_DRUM.get(int(n["instrument"]), "")) != drum:
				continue
			var row := int(n["row"])
			# Noise-kit notes carry their level in the instrument's envelope.
			var level := int(n["volume"]) if c == MdSong.FM5 else 13
			if int(n["instrument"]) >= MdArranger.INST_NOISE_KIT + 5:
				level = 10
			var note := int(n["note"]) if drum == "tom" else 60
			if not hits.has(row) or int(hits[row]["volume"]) < level:
				hits[row] = {"row": row, "note": note, "instrument": DRUM_INST[drum], "volume": level, "arp": -1}
	var events: Array = []
	for row in hits:
		var e: Dictionary = hits[row]
		events.append({"step": row, "length": 1, "note": e["note"], "instrument": e["instrument"], "volume": e["volume"], "arp": -1, "drum": 1})
	return NesArranger._to_notes(events, rows)


## The arrangement as a ChipSong with one channel per voice, for the
## timeline and MIDI export: the Mega Drive arrangement's patterns, at the
## tempo the card plays.
static func _build_source(opl: OplSong, md: MdSong, song: ChipSong, speed: Dictionary) -> ChipSong:
	var data: Dictionary = md.source.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(float(speed["bpm"]), 0.0001)
	data["meta"]["target"] = "pc"
	var insts: Array = []
	var channels: Array = []
	var layers: Array = []
	for i in opl.layout.size():
		var v: Dictionary = opl.layout[i]
		var drum := str(v["drum"]) != ""
		insts.append({"name": v["name"], "wave": "noise" if drum else "sine", "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.05, "volume": 0.4})
		channels.append({"name": v["name"], "instrument": i, "layer": "Drums" if drum else str(v["name"]), "volume": 1.0, "pan": 0.0, "polyphony": 1})
		layers.append({"name": v["name"], "channels": [i]})
	data["instruments"] = insts
	data["channels"] = channels
	data["layers"] = layers
	var md_layout := []
	for v in layout_for(opl.chip):
		md_layout.append(int(v["src"]) if str(v["drum"]) == "" else (MdSong.FM5 if str(v["drum"]) in ["bd", "tom"] else MdSong.MD_NOISE))
	for section in data["sections"]:
		var ids: Array = section["patterns"]
		var mapped: Array = []
		for src in md_layout:
			mapped.append(ids[src] if src < ids.size() else -1)
		section["patterns"] = mapped
	var out := ChipSong.new()
	out.data = data
	return out


static func _write_report(opl: OplSong, song: ChipSong, speed: Dictionary, dropped_pad: int) -> void:
	var lines := PackedStringArray()
	var name := func(index: int) -> String: return str(opl.instruments[index]["name"])
	match opl.chip:
		"dual_opl2":
			lines.append("Two OPL2 chips, one per speaker. Both play the lead (%s; the right one a few cents sharp for width), the bass (%s), the pad and the drums; the harmony (%s) is on the left and the arpeggio (%s) on the right." % [name.call(LEAD), name.call(BASS), name.call(HARMONY), name.call(ARP)])
		"opl3":
			lines.append("OPL3: the lead (%s) and bass (%s) in the middle, the lead doubled a few cents sharp; harmony (%s) and pad on the left, arpeggio (%s) and pad on the right." % [name.call(LEAD), name.call(BASS), name.call(HARMONY), name.call(ARP)])
		_:
			lines.append("Channels 1 to 4 play the lead (%s), harmony (%s), arpeggio (%s) and bass (%s); channels 5 and 6 the pad's chords (%s)." % [name.call(LEAD), name.call(HARMONY), name.call(ARP), name.call(BASS), name.call(PAD)])
	lines.append("The drums play in the rhythm mode: bass drum, snare, tom, cymbal and hi-hat on channels 7 to 9.")
	if dropped_pad > 0:
		lines.append("%d pad notes dropped where a chord had a third note (one OPL2 has room for two)." % dropped_pad)
	var promoted: Array = opl.stats.get("promoted", [])
	if not promoted.is_empty():
		lines.append("The lead's channel plays another part in %d section(s) with no lead." % promoted.size())
	var octave: Dictionary = opl.stats.get("octave", {})
	for part in octave:
		lines.append("%d %s notes moved by an octave to fit the range." % [int(octave[part]), part])
	if int(opl.stats.get("merged", 0)) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step." % int(opl.stats["merged"]))
	if float(song.data.get("timing", {}).get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: the driver plays even frames.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the card has none.")
	var groove := "-".join(PackedStringArray(Array(opl.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row at 70 Hz)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	opl.report = lines
