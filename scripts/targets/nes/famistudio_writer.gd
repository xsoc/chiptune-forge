class_name FamiStudioWriter
extends RefCounted
## Writes NES songs and sound effects as FamiStudio text projects (.txt).
##
## FamiStudio (MIT, famistudio.org) opens these with File > Import, or on the
## command line, and exports them for its sound engine (ca65, asm6, NESASM
## and SDAS), as NSF, or as a ROM. The format is FamiStudio's own text
## export, written without a version so any current FamiStudio reads it.

const AUTHOR := "Chiptune Forge"


## A project with one song.
static func song_project(nes: NesSong, project_name: String, credit := "") -> String:
	return project([nes], project_name, credit)


## A project with one song per sound effect, ready for FamiStudio's sound
## effect export.
static func sfx_project(sounds: Array, project_name: String) -> String:
	var songs: Array = []
	for sfx: NesSfx in sounds:
		songs.append(sfx.to_song())
	return project(songs, project_name, "")


## Writes [param songs] into one project. Instruments and arpeggios are
## shared by name: give each song's instruments distinct names unless they
## are the same instrument.
static func project(songs: Array, project_name: String, credit := "") -> String:
	var lines: PackedStringArray = []
	var head := "Project%s%s%s" % [_attr("TempoMode", "FamiStudio"), _attr("Name", project_name), _attr("Author", AUTHOR)]
	if credit != "":
		head += _attr("Copyright", credit)
	lines.append(head)
	var seen := {}
	for nes: NesSong in songs:
		for inst: Dictionary in nes.instruments:
			if seen.has("i:" + str(inst["name"])):
				continue
			seen["i:" + str(inst["name"])] = true
			lines.append("\tInstrument%s" % _attr("Name", inst["name"]))
			for env in [["volume", "Volume"], ["arp", "Arpeggio"], ["pitch", "Pitch"], ["duty", "DutyCycle"]]:
				var values: Array = inst.get(env[0], [])
				if values.is_empty():
					continue
				var line := "\t\tEnvelope%s%s" % [_attr("Type", env[1]), _attr("Length", values.size())]
				var loop := int(inst.get(env[0] + "_loop", -1))
				if loop >= 0:
					line += _attr("Loop", loop)
				line += _attr("Values", _join(values, ","))
				lines.append(line)
	for nes: NesSong in songs:
		for arp: Dictionary in nes.arpeggios:
			if seen.has("a:" + str(arp["name"])):
				continue
			seen["a:" + str(arp["name"])] = true
			var values: Array = arp["values"]
			lines.append("\tArpeggio%s%s%s%s" % [_attr("Name", arp["name"]), _attr("Length", values.size()), _attr("Loop", int(arp.get("loop", 0))), _attr("Values", _join(values, ","))])
	for nes: NesSong in songs:
		lines.append_array(_song_lines(nes))
	return "\n".join(lines) + "\n"


static func _song_lines(nes: NesSong) -> PackedStringArray:
	var lines: PackedStringArray = []
	var chunks := nes.pattern_chunks()
	# The most common pattern length is the song's; others get custom settings.
	var counts := {}
	var default_rows := int(chunks[0][1])
	for chunk in chunks:
		var rows := int(chunk[1])
		counts[rows] = int(counts.get(rows, 0)) + 1
		if int(counts[rows]) > int(counts.get(default_rows, 0)):
			default_rows = rows
	var note_length := 999
	for f in nes.groove:
		note_length = mini(note_length, f)
	var groove := _join(Array(nes.groove), "-")
	var beat := mini(nes.steps_per_beat, default_rows)
	var loop_point := -1
	if nes.looping:
		loop_point = 0
		for i in chunks.size():
			if int(chunks[i][0]) <= nes.loop_start_row:
				loop_point = i
	lines.append("\tSong%s%s%s%s%s%s%s%s" % [
		_attr("Name", nes.title),
		_attr("Length", chunks.size()),
		_attr("LoopPoint", loop_point),
		_attr("PatternLength", default_rows),
		_attr("BeatLength", beat),
		_attr("NoteLength", note_length),
		_attr("Groove", groove),
		_attr("GroovePaddingMode", "Middle"),
	])
	for i in chunks.size():
		var rows := int(chunks[i][1])
		if rows != default_rows:
			lines.append("\t\tPatternCustomSettings%s%s%s%s%s%s" % [
				_attr("Time", i),
				_attr("Length", rows),
				_attr("NoteLength", note_length),
				_attr("Groove", groove),
				_attr("GroovePaddingMode", "Middle"),
				_attr("BeatLength", mini(nes.steps_per_beat, rows)),
			])
	for c in 4:
		lines.append("\t\tChannel%s" % _attr("Type", NesSong.FAMISTUDIO_CHANNELS[c]))
		var list: Array = nes.notes[c]
		var names := {}
		var instances: Array = []
		var bodies: Array = []
		var k := 0
		for chunk in chunks:
			var start := int(chunk[0])
			var end := start + int(chunk[1])
			var body: PackedStringArray = []
			while k < list.size() and int(list[k]["row"]) < start:
				k += 1
			var j := k
			while j < list.size() and int(list[j]["row"]) < end:
				body.append(_note_line(nes, c, list[j], start))
				j += 1
			if body.is_empty():
				instances.append("")
				continue
			var key := "\n".join(body)
			if not names.has(key):
				names[key] = "%s %d" % [NesSong.CHANNEL_NAMES[c], names.size() + 1]
				bodies.append([names[key], body])
			instances.append(names[key])
		for entry in bodies:
			lines.append("\t\t\tPattern%s" % _attr("Name", entry[0]))
			lines.append_array(entry[1])
		for i in instances.size():
			if instances[i] != "":
				lines.append("\t\t\tPatternInstance%s%s" % [_attr("Time", i), _attr("Pattern", instances[i])])
	return lines


static func _note_line(nes: NesSong, channel: int, n: Dictionary, pattern_start: int) -> String:
	var line := "\t\t\t\tNote%s%s%s" % [
		_attr("Time", int(n["row"]) - pattern_start),
		_attr("Value", NesSong.note_name(int(n["note"]))),
		_attr("Duration", maxi(int(n["length"]), 1)),
	]
	var inst := int(n["instrument"])
	if inst >= 0 and inst < nes.instruments.size():
		line += _attr("Instrument", nes.instruments[inst]["name"])
	var arp := int(n.get("arp", -1))
	if arp >= 0 and arp < nes.arpeggios.size():
		line += _attr("Arpeggio", nes.arpeggios[arp]["name"])
	# The volume column is sticky in FamiStudio, so every note sets it. The
	# triangle has none.
	if channel != NesSong.TRIANGLE:
		line += _attr("Volume", clampi(int(n.get("volume", 15)), 0, 15))
	return line


static func _attr(key: String, value: Variant) -> String:
	return " %s=\"%s\"" % [key, str(value).replace("\"", "\"\"")]


static func _join(values: Array, separator: String) -> String:
	return separator.join(PackedStringArray(values.map(func(v: Variant) -> String: return str(int(v)))))


## How to use the exported project, for the README inside the zip.
static func readme(kind: String, file_name: String) -> String:
	var lines: Array[String] = [
		"%s: a FamiStudio project" % file_name,
		"",
		"FamiStudio is a free, open-source NES music editor (MIT licence): https://famistudio.org",
		"",
		"Open it: start FamiStudio, then File > Import and pick %s." % file_name,
		"Or convert it on the command line:",
	]
	if kind == "sfx":
		lines.append_array([
			"  FamiStudio %s famistudio-asm-sfx-export sfx.s -famistudio-asm-format:ca65" % file_name,
			"",
			"Each sound is one song in the project. Export them together with",
			"File > Export > Sound Effects (pick your assembler) and play them with",
			"famistudio_sfx_play from FamiStudio's sound engine. The engine plays a sound",
			"over the music on that channel and gives the channel back when it ends.",
		])
	else:
		lines.append_array([
			"  FamiStudio %s famistudio-asm-export music.s -famistudio-asm-format:ca65" % file_name,
			"  FamiStudio %s nsf-export music.nsf" % file_name,
			"  FamiStudio %s rom-export music.nes" % file_name,
			"",
			"Use the exported data with FamiStudio's sound engine (famistudio_ca65.s and the",
			"other assembler versions ship with FamiStudio). Call famistudio_init with the",
			"music data, famistudio_music_play 0, and famistudio_update once per frame.",
			"See https://famistudio.org/doc/soundengine/ for the details.",
		])
	lines.append_array([
		"",
		"The project uses only the 2A03's own channels (no expansion audio), the",
		"FamiStudio tempo mode, and volume, arpeggio, pitch and duty envelopes, so it",
		"exports to every sound engine format FamiStudio offers.",
	])
	return "\n".join(lines) + "\n"
