class_name SmsArranger
extends RefCounted
## Fits a generated song into the SN76489's three squares and noise channel.
##
## It starts from the NES arrangement, so a song keeps its shape across
## targets: Square 1 plays the lead, Square 2 one accompaniment part per
## section (the pad's chords as fast arpeggios), Square 3 the bass and the
## noise channel every drum. Then it fits that to this chip: notes move by
## octaves into its range (A2 and up, so most bass lines go up an octave),
## every square is a plain 50% square, volumes become the chip's 2 dB steps,
## and the drums use its three fixed noise rates. The tempo snaps to whole
## frames at the console's 59.92 Hz.

const INST_BASS := NesArranger.INST_BASS
const INST_KIT := NesArranger.INST_KIT
## The bass's volume level: under the lead, as a square bass is louder than
## the NES triangle it replaces.
const BASS_LEVEL := 13
## Noise rate for each NES noise period index: 0 is the brightest (hats and
## cymbals), 2 the darkest (kicks and low toms).
const RATE_FOR_INDEX := [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2]


static func arrange(song: ChipSong) -> SmsSong:
	return from_nes(NesArranger.arrange(song), song)


## Converts an NES arrangement of [param song].
static func from_nes(nes: NesSong, song: ChipSong) -> SmsSong:
	var sms := SmsSong.new()
	sms.title = nes.title
	sms.steps_per_bar = nes.steps_per_bar
	sms.steps_per_beat = nes.steps_per_beat
	var speed := NesSong.choose_groove(song.get_bpm(), nes.steps_per_beat, SmsSong.FRAME_HZ)
	sms.groove = speed["groove"]
	sms.row_count = nes.row_count
	sms.looping = nes.looping
	sms.loop_start_row = nes.loop_start_row
	sms.section_rows = nes.section_rows.duplicate(true)
	sms.feeds = nes.feeds.duplicate(true)
	sms.arpeggios = nes.arpeggios.duplicate(true)
	sms.stats = nes.stats
	for inst: Dictionary in nes.instruments:
		sms.instruments.append(_instrument(inst, sms.instruments.size()))
	var moved := [0, 0, 0]
	for c in 4:
		var out: Array = []
		for n: Dictionary in nes.notes[c]:
			var note: Dictionary = n.duplicate()
			if c == NesSong.NOISE:
				var index := 15 - clampi(int(n["note"]) - 16, 0, 15)
				note["note"] = RATE_FOR_INDEX[index]
				note["volume"] = 15
			else:
				var fitted := SmsSong.fit(NesSong.midi_of(c, int(n["note"])))
				if fitted["moved"]:
					moved[c] += 1
				note["note"] = fitted["note"]
				note["volume"] = BASS_LEVEL if c == SmsSong.SQUARE3 else SmsSong.level_of(int(n["volume"]))
			out.append(note)
		sms.notes[c] = out
	sms.source = _build_source(nes, speed)
	_write_report(sms, song, moved, speed)
	return sms


## An NES instrument with its volume envelope in 2 dB steps. Duty cycles go
## (the chip only has 50% squares), and so do the drums' pitch drops (the
## noise rates are fixed).
static func _instrument(inst: Dictionary, index: int) -> Dictionary:
	var out := {"name": inst["name"]}
	var volume: Array = []
	for v in inst.get("volume", [15]):
		volume.append(SmsSong.level_of(float(v)))
	out["volume"] = volume
	if inst.has("volume_loop"):
		out["volume_loop"] = inst["volume_loop"]
	if index >= INST_KIT:
		out["duty"] = [1]
		return out
	for key in ["pitch", "arp"]:
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
	data["meta"]["target"] = "sms"
	data["instruments"] = [
		{"name": "Square 1", "wave": "pulse", "duty": 0.5, "attack": 0.002, "decay": 0.2, "sustain": 0.7, "release": 0.02, "volume": 0.45},
		{"name": "Square 2", "wave": "pulse", "duty": 0.5, "attack": 0.002, "decay": 0.15, "sustain": 0.5, "release": 0.02, "volume": 0.3},
		{"name": "Square 3", "wave": "pulse", "duty": 0.5, "attack": 0.002, "decay": 0.1, "sustain": 0.9, "release": 0.02, "volume": 0.4},
		{"name": "Noise", "wave": "noise", "attack": 0.001, "decay": 0.12, "sustain": 0.0, "release": 0.02, "volume": 0.4},
	]
	var layers: Array = []
	for c in 4:
		data["channels"][c]["name"] = SmsSong.SMS_CHANNEL_NAMES[c]
		data["channels"][c]["layer"] = "Drums" if c == 3 else SmsSong.SMS_CHANNEL_NAMES[c]
		layers.append({"name": SmsSong.SMS_CHANNEL_NAMES[c], "channels": [c]})
	data["layers"] = layers
	for section: Dictionary in data["sections"]:
		var ids: Array = section.get("patterns", [])
		for c in mini(ids.size(), 3):
			if int(ids[c]) < 0:
				continue
			for note: Array in data["patterns"][int(ids[c])]["notes"]:
				note[2] = SmsSong.fit(int(note[2]))["note"]
	var out := ChipSong.new()
	out.data = data
	return out


static func _write_report(sms: SmsSong, song: ChipSong, moved: Array, speed: Dictionary) -> void:
	var stats := sms.stats
	var lines := PackedStringArray()
	var lead_line := "Square 1 plays the lead"
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
		lines.append("Square 2 plays %s." % "; ".join(PackedStringArray(accomp_parts)))
	lines.append("Square 3 plays the bass. Noise plays every drum on the chip's three noise rates.")
	var dropped: Dictionary = stats.get("dropped", {})
	for part in dropped:
		lines.append("%s dropped in %s (no channel left)." % [part, ", ".join(PackedStringArray(dropped[part]))])
	if int(stats.get("merged", 0)) > 0:
		lines.append("%d drum hits merged where two drums fell on the same step." % int(stats["merged"]))
	var names := ["lead", "accompaniment", "bass"]
	for c in 3:
		if int(moved[c]) > 0:
			var why := " (the chip's lowest note is A2)" if c == SmsSong.SQUARE3 else ""
			lines.append("%d %s notes moved by an octave to fit the chip's range%s." % [int(moved[c]), names[c], why])
	lines.append("Every part plays a plain square wave: the SN76489 has no other duty cycles.")
	var timing: Dictionary = song.data.get("timing", {})
	if float(timing.get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: PSGlib plays even rows.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the Master System has none.")
	var groove := "-".join(PackedStringArray(Array(sms.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	sms.report = lines
