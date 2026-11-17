class_name GusArranger
extends RefCounted
## Arranges a song for the Gravis Ultrasound: the SNES arrangement (lead,
## harmony, arpeggio, bass, two pad voices and drums on generated sampled
## instruments) as an Impulse Tracker module with 16-bit samples, at
## Impulse Tracker's own tick rate, with no echo. The GUS has 32 voices, so
## sound effects play on voices the music leaves free.


static func arrange(song: ChipSong) -> GusSong:
	var gus := GusSong.new()
	SnesArranger.arrange(song, gus)
	gus.echo = {"edl": 0, "efb": 0, "evol": 0, "fir": [127, 0, 0, 0, 0, 0, 0, 0], "eon": 0}
	gus.source.data["meta"]["target"] = "pc"
	var lines := PackedStringArray()
	for line in gus.report:
		if line.begins_with("Echo from") or line.begins_with("A light echo") or line.begins_with("Audio RAM"):
			continue
		line = line.replace("Voice 8 is left free for SNESMod's sound effects.", "Sound effects play on voices the music leaves free.")
		line = line.replace("Voices", "Channels").replace("Voice", "Channel").replace("voice", "channel")
		lines.append(line.replace("SNESMod", "the player"))
	var bytes := 0
	for name in gus.samples:
		bytes += (SnesSamples.get_sample(name)["pcm"] as PackedInt32Array).size() * 2
	lines.insert(lines.size() - 1, "Samples are 16-bit, %.0f KB in all, which fits the GUS's 256 KB. The GF1 interpolates them and pans each channel to one of 16 positions. No echo: the GUS has none." % (bytes / 1024.0))
	gus.report = lines
	return gus
