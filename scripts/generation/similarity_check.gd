class_name SimilarityCheck
extends RefCounted
## Looks for accidental likeness between a song's lead melody and well-known
## tunes before export. The generator only ever makes new notes, but short
## stepwise phrases can land on a familiar tune by chance.
##
## The check compares the shape of the melody (each interval in semitones,
## and whether each note is shorter, the same or longer than the one
## before), so a tune is found in any key and at any tempo. A run of
## [constant MATCH_NOTES] notes in a row counts as a match.
##
## The reference tunes are all old enough to be in the public domain, so
## this is a check for recognisable phrases, not a copyright search: the app
## cannot carry a library of protected melodies to compare against.

const MATCH_NOTES := 8
## Each tune: [name, [pitch, beats, pitch, beats, ...]] (MIDI pitches).
const TUNES := [
	["Twinkle, Twinkle, Little Star", [60, 1, 60, 1, 67, 1, 67, 1, 69, 1, 69, 1, 67, 2, 65, 1, 65, 1, 64, 1, 64, 1, 62, 1, 62, 1, 60, 2, 67, 1, 67, 1, 65, 1, 65, 1, 64, 1, 64, 1, 62, 2]],
	["Ode to Joy", [64, 1, 64, 1, 65, 1, 67, 1, 67, 1, 65, 1, 64, 1, 62, 1, 60, 1, 60, 1, 62, 1, 64, 1, 64, 1.5, 62, 0.5, 62, 2, 64, 1, 64, 1, 65, 1, 67, 1, 67, 1, 65, 1, 64, 1, 62, 1, 60, 1, 60, 1, 62, 1, 64, 1, 62, 1.5, 60, 0.5, 60, 2]],
	["Mary Had a Little Lamb", [64, 1, 62, 1, 60, 1, 62, 1, 64, 1, 64, 1, 64, 2, 62, 1, 62, 1, 62, 2, 64, 1, 67, 1, 67, 2, 64, 1, 62, 1, 60, 1, 62, 1, 64, 1, 64, 1, 64, 1, 64, 1, 62, 1, 62, 1, 64, 1, 62, 1, 60, 4]],
	["Frère Jacques", [60, 1, 62, 1, 64, 1, 60, 1, 60, 1, 62, 1, 64, 1, 60, 1, 64, 1, 65, 1, 67, 2, 64, 1, 65, 1, 67, 2, 67, 0.5, 69, 0.5, 67, 0.5, 65, 0.5, 64, 1, 60, 1, 67, 0.5, 69, 0.5, 67, 0.5, 65, 0.5, 64, 1, 60, 1, 60, 1, 55, 1, 60, 2]],
	["Happy Birthday", [67, 0.75, 67, 0.25, 69, 1, 67, 1, 72, 1, 71, 2, 67, 0.75, 67, 0.25, 69, 1, 67, 1, 74, 1, 72, 2, 67, 0.75, 67, 0.25, 79, 1, 76, 1, 72, 1, 71, 1, 69, 2, 77, 0.75, 77, 0.25, 76, 1, 72, 1, 74, 1, 72, 2]],
	["Row, Row, Row Your Boat", [60, 1.5, 60, 1.5, 60, 1, 62, 0.5, 64, 1.5, 64, 1, 62, 0.5, 64, 1, 65, 0.5, 67, 3, 72, 0.5, 72, 0.5, 72, 0.5, 67, 0.5, 67, 0.5, 67, 0.5, 64, 0.5, 64, 0.5, 64, 0.5, 60, 0.5, 60, 0.5, 60, 0.5, 67, 1, 65, 0.5, 64, 1, 62, 0.5, 60, 3]],
	["Jingle Bells", [64, 1, 64, 1, 64, 2, 64, 1, 64, 1, 64, 2, 64, 1, 67, 1, 60, 1.5, 62, 0.5, 64, 4, 65, 1, 65, 1, 65, 1.5, 65, 0.5, 65, 1, 64, 1, 64, 1, 64, 0.5, 64, 0.5, 64, 1, 62, 1, 62, 1, 64, 1, 62, 2, 67, 2]],
	["Für Elise", [76, 0.5, 75, 0.5, 76, 0.5, 75, 0.5, 76, 0.5, 71, 0.5, 74, 0.5, 72, 0.5, 69, 1, 60, 0.5, 64, 0.5, 69, 0.5, 71, 1, 64, 0.5, 68, 0.5, 71, 0.5, 72, 1, 64, 0.5, 76, 0.5, 75, 0.5, 76, 0.5, 75, 0.5, 76, 0.5, 71, 0.5, 74, 0.5, 72, 0.5, 69, 1]],
	["Korobeiniki", [76, 1, 71, 0.5, 72, 0.5, 74, 1, 72, 0.5, 71, 0.5, 69, 1, 69, 0.5, 72, 0.5, 76, 1, 74, 0.5, 72, 0.5, 71, 1.5, 72, 0.5, 74, 1, 76, 1, 72, 1, 69, 1, 69, 2, 74, 1.5, 77, 0.5, 81, 1, 79, 0.5, 77, 0.5, 76, 1.5, 72, 0.5, 76, 1, 74, 0.5, 72, 0.5, 71, 1, 71, 0.5, 72, 0.5, 74, 1, 76, 1, 72, 1, 69, 1, 69, 2]],
	["In the Hall of the Mountain King", [59, 0.5, 61, 0.5, 62, 0.5, 64, 0.5, 66, 0.5, 62, 0.5, 66, 1, 65, 0.5, 61, 0.5, 65, 1, 64, 0.5, 60, 0.5, 64, 1, 59, 0.5, 61, 0.5, 62, 0.5, 64, 0.5, 66, 0.5, 62, 0.5, 66, 0.5, 71, 0.5, 69, 0.5, 66, 0.5, 62, 0.5, 66, 0.5, 69, 2]],
	["Amazing Grace", [62, 1, 67, 2, 71, 0.5, 67, 0.5, 71, 2, 69, 1, 67, 2, 64, 1, 62, 2, 62, 1, 67, 2, 71, 0.5, 67, 0.5, 71, 2, 69, 0.5, 71, 0.5, 74, 3]],
	["When the Saints Go Marching In", [60, 1, 64, 1, 65, 1, 67, 4, 60, 1, 64, 1, 65, 1, 67, 4, 60, 1, 64, 1, 65, 1, 67, 2, 64, 2, 60, 2, 64, 2, 62, 4]],
	["Old MacDonald Had a Farm", [67, 1, 67, 1, 67, 1, 62, 1, 64, 1, 64, 1, 62, 2, 71, 1, 71, 1, 69, 1, 69, 1, 67, 3, 62, 1, 67, 1, 67, 1, 67, 1, 62, 1, 64, 1, 64, 1, 62, 2, 71, 1, 71, 1, 69, 1, 69, 1, 67, 3]],
	["Yankee Doodle", [60, 1, 60, 1, 62, 1, 64, 1, 60, 1, 64, 1, 62, 2, 60, 1, 60, 1, 62, 1, 64, 1, 60, 2, 59, 2, 60, 1, 60, 1, 62, 1, 64, 1, 65, 1, 64, 1, 62, 1, 60, 1, 59, 1, 55, 1, 57, 1, 59, 1, 60, 2, 60, 2]],
	["Greensleeves", [69, 1, 72, 2, 74, 1, 76, 1.5, 77, 0.5, 76, 1, 74, 2, 71, 1, 67, 1.5, 69, 0.5, 71, 1, 72, 2, 69, 1, 69, 1.5, 68, 0.5, 69, 1, 71, 2, 68, 1, 64, 2]],
]

static var _tune_shapes: Array = []


## The lead melody as [[start step, pitch], ...], the highest note at each
## start, in play order.
static func lead_notes(song: ChipSong) -> Array:
	var data := song.data
	var lead := 0
	var channels: Array = data.get("channels", [])
	for c in channels.size():
		if str(channels[c].get("layer", channels[c].get("name", ""))) == "Lead":
			lead = c
			break
	var top := {}
	var offset := 0
	for section_index in data.get("order", []):
		var section: Dictionary = data["sections"][int(section_index)]
		var patterns: Array = section.get("patterns", [])
		var pattern := int(patterns[lead]) if lead < patterns.size() else -1
		if pattern >= 0 and pattern < data.get("patterns", []).size():
			for note: Array in data["patterns"][pattern].get("notes", []):
				var start := offset + int(note[0])
				top[start] = maxi(int(top.get(start, -1)), int(note[2]))
		offset += int(section.get("length", 0))
	var starts := top.keys()
	starts.sort()
	var out: Array = []
	for start in starts:
		out.append([start, top[start]])
	return out


## The first well-known tune the lead follows for [constant MATCH_NOTES]
## notes, as {tune, notes, step} (the step where the phrase starts), or {}.
static func find(song: ChipSong) -> Dictionary:
	var notes := lead_notes(song)
	var times := PackedFloat64Array()
	var pitches := PackedInt32Array()
	for note: Array in notes:
		times.append(note[0])
		pitches.append(note[1])
	var shape := _shape(pitches, times)
	for tune: Array in _tunes():
		var run := _longest_run(shape, tune[1])
		if run[0] + 1 >= MATCH_NOTES:
			return {"tune": tune[0], "notes": run[0] + 1, "step": int(times[run[1]])}
	return {}


## A line for the export report: a warning naming the tune, or a note that
## nothing matched.
static func report_line(song: ChipSong, warn_colour := "#f0a050") -> String:
	var found := find(song)
	if found.is_empty():
		return "Originality: no %d-note phrase of the lead matches the %d well-known tunes checked." % [MATCH_NOTES, TUNES.size()]
	var seconds := int(found.step * song.get_step_seconds())
	return "[color=%s]Sounds like %s: %d notes of the lead from %d:%02d follow its tune. Regenerate the lead or try another seed.[/color]" % [warn_colour, found.tune, found.notes, seconds / 60, seconds % 60]


static func _tunes() -> Array:
	if _tune_shapes.is_empty():
		for tune: Array in TUNES:
			var pitches := PackedInt32Array()
			var times := PackedFloat64Array()
			var at := 0.0
			var flat: Array = tune[1]
			for i in range(0, flat.size(), 2):
				pitches.append(flat[i])
				times.append(at)
				at += float(flat[i + 1])
			times.append(at)
			_tune_shapes.append([tune[0], _shape(pitches, times)])
	return _tune_shapes


## Per note after the first: the interval from the note before, and how its
## time to the next note compares with the previous note's (-1, 0 or 1).
static func _shape(pitches: PackedInt32Array, times: PackedFloat64Array) -> Array[PackedInt32Array]:
	var intervals := PackedInt32Array()
	var rhythms := PackedInt32Array()
	for k in range(1, pitches.size()):
		var rhythm := 0
		if k + 1 < times.size():
			var before := times[k] - times[k - 1]
			var after := times[k + 1] - times[k]
			rhythm = 0 if absf(after - before) <= 0.2 * before else (1 if after > before else -1)
		intervals.append(pitches[k] - pitches[k - 1])
		rhythms.append(rhythm)
	return [intervals, rhythms]


## The longest run where the song's shape follows the tune's, as [intervals
## matched, index of the run's first note in the song]. The first interval
## of a run only needs its size to match, since the note before the phrase
## is not part of it.
static func _longest_run(song: Array[PackedInt32Array], tune: Array[PackedInt32Array]) -> Array:
	var best := [0, 0]
	var song_intervals := song[0]
	var song_rhythms := song[1]
	var tune_intervals := tune[0]
	var tune_rhythms := tune[1]
	var previous := PackedInt32Array()
	previous.resize(tune_intervals.size() + 1)
	for i in song_intervals.size():
		var current := PackedInt32Array()
		current.resize(tune_intervals.size() + 1)
		for j in tune_intervals.size():
			if song_intervals[i] != tune_intervals[j]:
				continue
			var run := previous[j] + 1 if previous[j] > 0 and song_rhythms[i] == tune_rhythms[j] else 1
			current[j + 1] = run
			if run > best[0]:
				best = [run, i + 1 - run]
		previous = current
	return best
