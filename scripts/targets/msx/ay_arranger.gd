class_name AyArranger
extends RefCounted
## Fits a generated song into the AY-3-8910's three channels and its noise.
##
## It starts from the NES arrangement, so a song keeps its shape across
## targets: channel A plays the lead, B one accompaniment part per section
## (the pad's chords as fast arpeggios), C the bass, and the drums borrow B
## for as long as each hit sounds, as AY music usually does. Then it fits
## that to this chip: notes move by octaves into its range, every part
## plays a square wave, volumes become the chip's levels, and the drums use
## its noise generator. The tempo snaps to whole frames at 50 Hz.

const INST_KIT := NesArranger.INST_KIT
## The bass's level: under the lead, as a square bass is louder than the
## NES triangle it replaces.
const BASS_LEVEL := 13


static func arrange(song: ChipSong) -> AySong:
	return from_nes(NesArranger.arrange(song), song)


## Converts an NES arrangement of [param song].
static func from_nes(nes: NesSong, song: ChipSong) -> AySong:
	var ay := AySong.new()
	ay.title = nes.title
	ay.steps_per_bar = nes.steps_per_bar
	ay.steps_per_beat = nes.steps_per_beat
	var speed := NesSong.choose_groove(song.get_bpm(), nes.steps_per_beat, AySong.FRAME_HZ)
	ay.groove = speed["groove"]
	ay.row_count = nes.row_count
	ay.looping = nes.looping
	ay.loop_start_row = nes.loop_start_row
	ay.section_rows = nes.section_rows.duplicate(true)
	ay.feeds = nes.feeds.duplicate(true)
	ay.arpeggios = nes.arpeggios.duplicate(true)
	ay.stats = nes.stats
	for inst: Dictionary in nes.instruments:
		ay.instruments.append(_instrument(inst, ay.instruments.size()))
	var moved := [0, 0, 0]
	for c in 4:
		var out: Array = []
		for n: Dictionary in nes.notes[c]:
			var note: Dictionary = n.duplicate()
			if c == AySong.DRUMS:
				note["volume"] = 15
			else:
				var fitted := AySong.fit(NesSong.midi_of(c, int(n["note"])))
				if fitted["moved"]:
					moved[c] += 1
				note["note"] = fitted["note"]
				note["volume"] = BASS_LEVEL if c == AySong.BASS else AySong.level_of(int(n["volume"]))
			out.append(note)
		ay.notes[c] = out
	ay.source = _build_source(nes, speed)
	_write_report(ay, song, moved, speed)
	return ay


## An NES instrument with its volume envelope as chip levels. Duty cycles go
## (the chip only has squares). The drums keep their pitch drops, which
## step through the noise periods.
static func _instrument(inst: Dictionary, index: int) -> Dictionary:
	var out := {"name": inst["name"]}
	var volume: Array = []
	for v in inst.get("volume", [15]):
		volume.append(AySong.level_of(float(v)))
	out["volume"] = volume
	if inst.has("volume_loop"):
		out["volume_loop"] = inst["volume_loop"]
	var keys := ["arp"] if index >= INST_KIT else ["pitch", "arp"]
	for key in keys:
		if inst.has(key):
			out[key] = (inst[key] as Array).duplicate()
			if inst.has(key + "_loop"):
				out[key + "_loop"] = inst[key + "_loop"]
	return out


## The NES arrangement's four-channel ChipSong, renamed for this chip, its
## notes moved into this chip's range and its tempo the one it plays at.
static func _build_source(nes: NesSong, speed: Dictionary) -> ChipSong:
	var data: Dictionary = nes.source.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(float(speed["bpm"]), 0.0001)
	data["meta"]["target"] = "msx"
	data["instruments"] = [
		{"name": "Lead (A)", "wave": "pulse", "duty": 0.5, "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.02, "volume": 0.45},
		{"name": "Accompaniment (B)", "wave": "pulse", "duty": 0.5, "attack": 0.002, "decay": 0.15, "sustain": 0.5, "release": 0.02, "volume": 0.3},
		{"name": "Bass (C)", "wave": "pulse", "duty": 0.5, "attack": 0.002, "decay": 0.1, "sustain": 0.9, "release": 0.02, "volume": 0.4},
		{"name": "Drums (B)", "wave": "noise", "attack": 0.001, "decay": 0.12, "sustain": 0.0, "release": 0.02, "volume": 0.4},
	]
	var layers: Array = []
	for c in 4:
		data["channels"][c]["name"] = AySong.AY_CHANNEL_NAMES[c]
		data["channels"][c]["layer"] = "Drums" if c == 3 else AySong.AY_CHANNEL_NAMES[c]
		layers.append({"name": AySong.AY_CHANNEL_NAMES[c], "channels": [c]})
	data["layers"] = layers
	for section: Dictionary in data["sections"]:
		var ids: Array = section.get("patterns", [])
		for c in mini(ids.size(), 3):
			if int(ids[c]) < 0:
				continue
			for note: Array in data["patterns"][int(ids[c])]["notes"]:
				note[2] = AySong.fit(int(note[2]))["note"]
	var out := ChipSong.new()
	out.data = data
	return out


static func _write_report(ay: AySong, song: ChipSong, moved: Array, speed: Dictionary) -> void:
	var stats := ay.stats
	var lines := PackedStringArray()
	var lead_line := "Channel A plays the lead"
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
		lines.append("Channel B plays %s." % "; ".join(PackedStringArray(accomp_parts)))
	lines.append("Channel C plays the bass.")
	lines.append("The drums play on the noise generator through channel B, which leaves the accompaniment for as long as each hit sounds.")
	var dropped: Dictionary = stats.get("dropped", {})
	for part in dropped:
		lines.append("%s dropped in %s (no channel left)." % [part, ", ".join(PackedStringArray(dropped[part]))])
	if int(stats.get("merged", 0)) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step." % int(stats["merged"]))
	var names := ["lead", "accompaniment", "bass"]
	for c in 3:
		if int(moved[c]) > 0:
			lines.append("%d %s notes moved by an octave to fit the chip's range." % [int(moved[c]), names[c]])
	lines.append("Every part plays a square wave: the AY-3-8910 has no other.")
	var timing: Dictionary = song.data.get("timing", {})
	if float(timing.get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: the player plays even rows.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the chip has none.")
	var groove := "-".join(PackedStringArray(Array(ay.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row at 50 Hz)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	ay.report = lines
