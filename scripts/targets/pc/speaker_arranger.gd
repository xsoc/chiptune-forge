class_name SpeakerArranger
extends RefCounted
## Fits a generated song onto the PC speaker's one square wave.
##
## It starts from the NES arrangement, so a song keeps its shape: the lead
## from Pulse 1, the bass from the triangle and every drum from the noise
## channel. The accompaniment on Pulse 2 has no room and is left out. Notes
## move by octaves into the speaker's useful range, the speaker has no
## volume (a note sounds while its envelope is up), and the tempo snaps to
## whole frames of the 70 Hz driver.

## Envelope levels below this are silent on the speaker.
const GATE := 3


static func arrange(song: ChipSong) -> SpeakerSong:
	var nes := NesArranger.arrange(song)
	var out := SpeakerSong.new()
	out.title = nes.title
	out.steps_per_bar = nes.steps_per_bar
	out.steps_per_beat = nes.steps_per_beat
	var speed := NesSong.choose_groove(song.get_bpm(), nes.steps_per_beat, SpeakerSong.FRAME_HZ)
	out.groove = speed["groove"]
	out.row_count = nes.row_count
	out.looping = nes.looping
	out.loop_start_row = nes.loop_start_row
	out.section_rows = nes.section_rows.duplicate(true)
	out.arpeggios = nes.arpeggios.duplicate(true)
	out.instruments = nes.instruments.duplicate(true)
	out.stats = nes.stats
	var moved := [0, 0]
	var parts := [NesSong.PULSE1, NesSong.TRIANGLE]
	for i in 2:
		var list: Array = []
		for n: Dictionary in nes.notes[parts[i]]:
			var note: Dictionary = n.duplicate()
			var midi := NesSong.midi_of(parts[i], int(n["note"]))
			var fitted := midi
			while fitted < SpeakerSong.LOWEST:
				fitted += 12
			while fitted > SpeakerSong.HIGHEST:
				fitted -= 12
			if fitted != midi:
				moved[i] += 1
			note["note"] = fitted
			list.append(note)
		out.notes[i] = list
	out.notes[SpeakerSong.DRUMS] = nes.notes[NesSong.NOISE].duplicate(true)
	for feed in nes.feeds:
		var sources: Array = feed["sources"]
		out.feeds.append({"row": feed["row"], "sources": [sources[NesSong.PULSE1], sources[NesSong.TRIANGLE], sources[NesSong.NOISE]]})
	out.source = _build_source(nes, speed)
	var lines := PackedStringArray()
	lines.append("One square wave: the lead and bass take turns 140 times a second while both sound, and drums take over for each hit.")
	var dropped := (nes.notes[NesSong.PULSE2] as Array).size()
	if dropped > 0:
		lines.append("%d accompaniment notes removed: the speaker has room for the lead and bass." % dropped)
	if moved[0] > 0:
		lines.append("%d lead notes moved by an octave to fit the range." % moved[0])
	if moved[1] > 0:
		lines.append("%d bass notes moved up an octave: the small speaker barely plays below C2." % moved[1])
	lines.append("Volume removed: the speaker is on or off, so each note sounds while its envelope is up.")
	if float(song.data.get("timing", {}).get("swing", 0.0)) > 0.02:
		lines.append("Swing straightened: the driver plays even frames.")
	if float(song.data.get("effects", {}).get("echo", 0.0)) > 0.0:
		lines.append("Echo removed: the speaker has none.")
	var groove := "-".join(PackedStringArray(Array(out.groove).map(func(f: int) -> String: return str(f))))
	lines.append("Tempo %s BPM plays at %.1f BPM (groove %s frames per row at 70 Hz)." % [str(snappedf(song.get_bpm(), 0.1)), float(speed["bpm"]), groove])
	out.report = lines
	return out


## The arrangement as a three-channel ChipSong, for the timeline and MIDI.
static func _build_source(nes: NesSong, speed: Dictionary) -> ChipSong:
	var data: Dictionary = nes.source.data.duplicate(true)
	data["timing"]["bpm"] = snappedf(float(speed["bpm"]), 0.0001)
	data["meta"]["target"] = "pc"
	var keep := [NesSong.PULSE1, NesSong.TRIANGLE, NesSong.NOISE]
	var insts: Array = []
	var channels: Array = []
	var layers: Array = []
	for i in 3:
		var name: String = SpeakerSong.CHANNEL_NAMES_SPEAKER[i]
		var drum := i == SpeakerSong.DRUMS
		insts.append({"name": name, "wave": "noise" if drum else "pulse", "duty": 0.5, "attack": 0.0, "decay": 0.1, "sustain": 1.0, "release": 0.01, "volume": 0.35})
		channels.append({"name": name, "instrument": i, "layer": "Drums" if drum else name, "volume": 1.0, "pan": 0.0, "polyphony": 1})
		layers.append({"name": "Drums" if drum else name, "channels": [i]})
	data["instruments"] = insts
	data["channels"] = channels
	data["layers"] = layers
	for section in data["sections"]:
		var ids: Array = section["patterns"]
		var mapped: Array = []
		for src in keep:
			mapped.append(ids[src] if src < ids.size() else -1)
		section["patterns"] = mapped
	var out := ChipSong.new()
	out.data = data
	return out
