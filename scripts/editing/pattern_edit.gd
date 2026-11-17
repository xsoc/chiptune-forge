class_name PatternEdit
extends RefCounted
## Edits the notes of a song: adds and removes notes in one section's
## pattern for one channel. Patterns are shared between the sections that
## use them, so an edit changes every section that plays that pattern,
## which is what a tracker does.
##
## A note is [step, length, pitch, velocity, instrument?, arp?] as the
## generator writes it (see docs/format.md).

## The drum rows of the editor, top to bottom.
const DRUM_ROWS: PackedInt32Array = [
	DrumWriter.CRASH, DrumWriter.RIDE, DrumWriter.OPEN_HAT, DrumWriter.HAT,
	DrumWriter.SNARE, DrumWriter.TOM, DrumWriter.KICK,
]
const DRUM_NAMES := {
	DrumWriter.KICK: "Kick", DrumWriter.SNARE: "Snare", DrumWriter.HAT: "Hat",
	DrumWriter.OPEN_HAT: "Open hat", DrumWriter.CRASH: "Crash", DrumWriter.TOM: "Tom",
	DrumWriter.RIDE: "Ride",
}
const NOTE_NAMES: PackedStringArray = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


static func note_name(pitch: int) -> String:
	return "%s%d" % [NOTE_NAMES[pitch % 12], pitch / 12 - 1]


## The channel a drum plays on: kick and toms on the tonal drum channel,
## the rest on noise, as [DrumWriter] writes them.
static func drum_channel(instrument: int) -> int:
	return GenContext.Channel.DRUMS if instrument == DrumWriter.KICK or instrument == DrumWriter.TOM else GenContext.Channel.NOISE


## The notes of a section on a channel (a copy). Empty for a silent slot.
static func notes_at(song: ChipSong, section: int, channel: int) -> Array:
	var id := pattern_id(song, section, channel)
	if id < 0:
		return []
	return (song.data["patterns"][id]["notes"] as Array).duplicate(true)


static func pattern_id(song: ChipSong, section: int, channel: int) -> int:
	var ids: Array = song.data["sections"][section]["patterns"]
	return int(ids[channel]) if channel < ids.size() else -1


## How many sections play the pattern of [param section] on [param channel],
## counting it.
static func sharing(song: ChipSong, section: int, channel: int) -> int:
	var id := pattern_id(song, section, channel)
	if id < 0:
		return 1
	var count := 0
	for s in song.data["sections"]:
		var ids: Array = s["patterns"]
		if channel < ids.size() and int(ids[channel]) == id:
			count += 1
	return count


## The index of the note on [param channel] that sounds at [param step] with
## [param pitch] (or, for drums, [param instrument]), or -1.
static func find_note(notes: Array, step: int, pitch: int, instrument := -1) -> int:
	for i in notes.size():
		var n: Array = notes[i]
		var start := int(n[0])
		if step < start or step >= start + int(n[1]):
			continue
		if instrument >= 0:
			if n.size() > 4 and int(n[4]) == instrument:
				return i
		elif int(n[2]) == pitch:
			return i
	return -1


## Adds a note where there is none and removes the one there otherwise.
## Returns true when it added one. On a channel that plays one note at a
## time, a new note cuts the notes it overlaps. For drums pass the
## instrument; the channel is then the drum's own.
static func toggle(song: ChipSong, section: int, channel: int, step: int, pitch: int, length := 1, instrument := -1) -> bool:
	if instrument >= 0:
		channel = drum_channel(instrument)
		pitch = int(DrumWriter.PITCH[instrument])
		length = 1
	var notes := _pattern_notes(song, section, channel)
	var at := find_note(notes, step, pitch, instrument)
	if at >= 0:
		notes.remove_at(at)
		return false
	var steps := int(song.data["sections"][section]["length"])
	if step < 0 or step >= steps:
		return false
	length = clampi(length, 1, steps - step)
	var mono := instrument < 0 and int(song.data["channels"][channel].get("polyphony", 1)) <= 1
	if mono:
		var kept: Array = []
		for n in notes:
			var start := int(n[0])
			var end := start + int(n[1])
			if start >= step and start < step + length:
				continue
			if start < step and end > step:
				n[1] = step - start
			kept.append(n)
		notes.assign(kept)
	var note: Array = [step, length, clampi(pitch, 0, 127), 100]
	if instrument >= 0:
		note.append(instrument)
	notes.append(note)
	notes.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[0] != b[0] else a[2] < b[2])
	return true


## The pattern's notes to change in place, making a pattern for a silent
## slot first.
static func _pattern_notes(song: ChipSong, section: int, channel: int) -> Array:
	var ids: Array = song.data["sections"][section]["patterns"]
	while ids.size() <= channel:
		ids.append(-1)
	if int(ids[channel]) < 0:
		var patterns: Array = song.data["patterns"]
		patterns.append({"notes": []})
		ids[channel] = patterns.size() - 1
	return song.data["patterns"][int(ids[channel])]["notes"]


## The lowest row of a two-octave view that fits the notes of a channel
## across the song, starting on a C.
static func default_low_pitch(song: ChipSong, channel: int) -> int:
	var total := 0
	var count := 0
	for s in song.data["sections"].size():
		for n in notes_at(song, s, channel):
			total += int(n[2])
			count += 1
	var centre := total / count if count > 0 else (48 if channel == GenContext.Channel.BASS else 64)
	return clampi((centre - 12) / 12 * 12, 12, 96)
