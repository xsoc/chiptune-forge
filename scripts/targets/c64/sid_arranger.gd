class_name SidArranger
extends RefCounted
## Fits a generated song into the SID's three voices.
##
## It starts from the NES arrangement, so a song keeps its shape across
## targets: voice 1 plays the lead, voice 2 one accompaniment part per
## section (the pad's chords as fast arpeggios), voice 3 the bass, and the
## drums borrow voice 2 for as long as each hit sounds. Then it fits that to
## the SID: notes move by octaves into its range, the lead and
## accompaniment keep their NES duty cycles as pulse widths, the bass plays
## a narrow pulse, the drums play noise, and every NES volume envelope
## becomes the closest hardware ADSR. The tempo snaps to whole frames at
## 50 Hz (PAL).

const INST_BASS := NesArranger.INST_BASS
const INST_KIT := NesArranger.INST_KIT
const BASS_WIDTH := 1536


static func arrange(song: ChipSong) -> SidSong:
	return from_nes(NesArranger.arrange(song), song)


static func from_nes(nes: NesSong, song: ChipSong) -> SidSong:
	var sid := SidSong.new()
	sid.title = nes.title
	sid.steps_per_bar = nes.steps_per_bar
	sid.steps_per_beat = nes.steps_per_beat
	var speed := NesSong.choose_groove(song.get_bpm(), nes.steps_per_beat, SidSong.FRAME_HZ)
	sid.groove = speed["groove"]
	sid.row_count = nes.row_count
	sid.looping = nes.looping
	sid.loop_start_row = nes.loop_start_row
	sid.section_rows = nes.section_rows.duplicate(true)
	sid.feeds = nes.feeds.duplicate(true)
	sid.arpeggios = nes.arpeggios.duplicate(true)
	sid.stats = nes.stats
	for inst: Dictionary in nes.instruments:
		sid.instruments.append(instrument(inst, sid.instruments.size()))
	var moved := [0, 0, 0]
	for c in 4:
		var out: Array = []
		for n: Dictionary in nes.notes[c]:
			var note: Dictionary = n.duplicate()
			if c == SidSong.DRUMS:
				note["volume"] = 15
			else:
				var fitted := SidSong.fit(NesSong.midi_of(c, int(n["note"])))
				if fitted["moved"]:
					moved[c] += 1
				note["note"] = fitted["note"]
				note["volume"] = 15 if c == SidSong.BASS else clampi(int(n["volume"]), 1, 15)
			out.append(note)
		sid.notes[c] = out
	sid.source = _build_source(nes, speed)
	_write_report(sid, song, moved, speed)
	return sid


## An NES instrument for the SID: its waveform, the ADSR closest to its
## volume envelope, and its duty, pitch and arpeggio envelopes.
static func instrument(inst: Dictionary, index: int) -> Dictionary:
	var out := {"name": inst["name"]}
	var volume: Array = inst.get("volume", [15])
	out["volume"] = volume.duplicate()
	if inst.has("volume_loop"):
		out["volume_loop"] = inst["volume_loop"]
	var adsr := SidSong.adsr_of(volume, int(inst.get("volume_loop", -1)))
	out["ad"] = adsr[0]
	out["sr"] = adsr[1]
	if index >= INST_KIT:
		out["wave"] = "noise"
	elif index == INST_BASS:
		out["wave"] = "pulse"
		out["pw"] = BASS_WIDTH
	else:
		out["wave"] = "pulse"
		for key in ["duty", "pitch"]:
			if inst.has(key):
				out[key] = (inst[key] as Array).duplicate()
				if inst.has(key + "_loop"):
					out[key + "_loop"] = inst[key + "_loop"]
	if inst.has("arp"):
		out["arp"] = (inst["arp"] as Array).duplicate()
		if inst.has("arp_loop"):
			out["arp_loop"] = inst["arp_loop"]
	return out


static func _build_source(nes: NesSong, speed: Dictionary) -> ChipSong:
	var data: Dictionary = nes.source.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(float(speed["bpm"]), 0.0001)
	data["meta"]["target"] = "c64"
	data["instruments"] = [
		{"name": "Lead (voice 1)", "wave": "pulse", "duty": 0.25, "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.05, "volume": 0.45},
		{"name": "Accompaniment (voice 2)", "wave": "pulse", "duty": 0.5, "attack": 0.002, "decay": 0.15, "sustain": 0.5, "release": 0.05, "volume": 0.3},
		{"name": "Bass (voice 3)", "wave": "pulse", "duty": 0.375, "attack": 0.002, "decay": 0.1, "sustain": 0.9, "release": 0.05, "volume": 0.4},
		{"name": "Drums (voice 2)", "wave": "noise", "attack": 0.001, "decay": 0.12, "sustain": 0.0, "release": 0.02, "volume": 0.4},
	]
	var layers: Array = []
	for c in 4:
		data["channels"][c]["name"] = SidSong.SID_CHANNEL_NAMES[c]
		data["channels"][c]["layer"] = "Drums" if c == 3 else SidSong.SID_CHANNEL_NAMES[c]
		layers.append({"name": SidSong.SID_CHANNEL_NAMES[c], "channels": [c]})
	data["layers"] = layers
	for section: Dictionary in data["sections"]:
		var ids: Array = section.get("patterns", [])
		for c in mini(ids.size(), 3):
			if int(ids[c]) < 0:
				continue
			for note: Array in data["patterns"][int(ids[c])]["notes"]:
				note[2] = SidSong.fit(int(note[2]))["note"]
	var out := ChipSong.new()
	out.data = data
	return out


static func _write_report(sid: SidSong, song: ChipSong, moved: Array, speed: Dictionary) -> void:
	var stats := sid.stats
	var lines := PackedStringArray()
	var lead_line := "Voice 1 plays the lead"
	var promoted: Array = stats.get("promoted", [])
	if not promoted.is_empty():
		var parts: Array = []
		for entry in promoted:
			parts.append("%s in %s" % [entry[1], entry[0]])
		lead_line += ", and the %s where there is no lead" % ", ".join(PackedStringArray(parts))
	lines.append(lead_line + ".")
	var accomp: Dictionary = stats.get("accomp", {})
	var accomp_parts: Array = []
	for part in accomp:
		var where := ", ".join(PackedStringArray(accomp[part]))
		if part == "Pad":
			accomp_parts.append("the Pad's chords as arpeggios in %s" % where)
		else:
			accomp_parts.append("the %s in %s" % [part, where])
	if not accomp_parts.is_empty():
		lines.append("Voice 2 plays %s." % "; ".join(PackedStringArray(accomp_parts)))
	lines.append("Voice 3 plays the bass as a narrow pulse.")
	lines.append("The drums play noise on voice 2, which leaves the accompaniment for as long as each hit sounds.")
	var dropped: Dictionary = stats.get("dropped", {})
	for part in dropped:
		lines.append("%s dropped in %s (no voice left)." % [part, ", ".join(PackedStringArray(dropped[part]))])
	if int(stats.get("merged", 0)) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step." % int(stats["merged"]))
	var names := ["lead", "accompaniment", "bass"]
	for c in 3:
		if int(moved[c]) > 0:
			lines.append("%d %s notes moved by an octave to fit the chip's range." % [int(moved[c]), names[c]])
	lines.append("Volume envelopes became the SID's hardware ADSR envelopes; each new note restarts its envelope.")
	var timing: Dictionary = song.data.get("timing", {})
	if float(timing.get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: the player plays even rows.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the SID has none.")
	var groove := "-".join(PackedStringArray(Array(sid.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row at 50 Hz)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	sid.report = lines
