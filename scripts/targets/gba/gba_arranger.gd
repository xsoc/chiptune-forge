class_name GbaArranger
extends RefCounted
## Arranges a song for the Game Boy Advance: the SNES arrangement (lead,
## harmony, arpeggio, bass, two pad voices and drums on sampled instruments,
## channel 8 left free for sound effects), played by Maxmod at Impulse
## Tracker's own tick rate, with 8-bit samples and no echo.


static func arrange(song: ChipSong) -> GbaSong:
	var gba := GbaSong.new()
	SnesArranger.arrange(song, gba)
	gba.echo = {"edl": 0, "efb": 0, "evol": 0, "fir": [127, 0, 0, 0, 0, 0, 0, 0], "eon": 0}
	gba.source.data["meta"]["target"] = "gba"
	var lines := PackedStringArray()
	for line in gba.report:
		if line.begins_with("Echo from") or line.begins_with("A light echo") or line.begins_with("Audio RAM"):
			continue
		line = line.replace("Voice 8 is left free for SNESMod's sound effects.", "Channel 8 is left free for Maxmod's sound effects.")
		line = line.replace("Voices", "Channels").replace("Voice", "Channel").replace("voice", "channel")
		line = line.replace("SNESMod", "Maxmod")
		lines.append(line)
	lines.insert(lines.size() - 1, "Samples are 8-bit; Maxmod mixes them at 16 kHz into the two Direct Sound channels, leaving the Game Boy channels free. No echo: the GBA has none.")
	gba.report = lines
	return gba
