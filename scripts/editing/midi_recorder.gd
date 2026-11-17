class_name MidiRecorder
extends RefCounted
## Records notes played live (on a MIDI keyboard, the on-screen keys or the
## computer keyboard) while the song plays, then writes them into one part.
##
## Times are song steps as floats (the playhead), so the recorder needs no
## clock of its own and can be tested without audio. When the song loops
## while recording, later passes add to (or, with replace, take over) the
## same sections.

## Notes being held: pitch -> [start step, velocity].
var _held: Dictionary = {}
## Finished notes: [start step, end step, pitch, velocity].
var notes: Array = []
## Order positions the playhead passed while recording:
## position -> Vector2i(first step, last step) within that section.
var covered: Dictionary = {}
var _song: ChipSong
var _last_step := -1.0


func _init(song: ChipSong) -> void:
	_song = song


func is_empty() -> bool:
	return notes.is_empty() and _held.is_empty()


## Tells the recorder where the playhead is. Call it every frame.
func mark(step: float) -> void:
	if step < 0.0:
		return
	var at := SongEdit.locate(_song, int(step))
	if at.x < 0:
		return
	if covered.has(at.x):
		var span: Vector2i = covered[at.x]
		covered[at.x] = Vector2i(mini(span.x, at.y), maxi(span.y, at.y))
	else:
		covered[at.x] = Vector2i(at.y, at.y)
	# A jump back means the song looped: close held notes at the loop end.
	if _last_step >= 0.0 and step < _last_step - 1.0:
		var end := float(_song.get_loop_end_step())
		for pitch in _held.keys():
			var info: Array = _held[pitch]
			notes.append([info[0], maxf(end, float(info[0]) + 1.0), pitch, info[1]])
			_held[pitch] = [step, info[1]]
	_last_step = step


func note_on(pitch: int, velocity: int, step: float) -> void:
	mark(step)
	if _held.has(pitch):
		note_off(pitch, step)
	_held[pitch] = [step, velocity]


func note_off(pitch: int, step: float) -> void:
	if not _held.has(pitch):
		return
	var info: Array = _held[pitch]
	_held.erase(pitch)
	var start := float(info[0])
	# Released after the loop wrapped: the note ran to the loop end.
	var end := step if step >= start else float(_song.get_loop_end_step())
	notes.append([start, end, pitch, info[1]])


## Ends notes still held at [param step].
func finish(step: float) -> void:
	for pitch in _held.keys():
		note_off(pitch, step)


## Writes the take into the song. [param channel] is the part's channel, or
## -1 for drums (each note then goes to its drum's channel). [param grid] is
## the quantize grid in steps. With [param replace], notes the take passed
## over are removed first; otherwise the take is added to them. Returns how
## many notes were written.
func commit(song: ChipSong, channel: int, grid: int, replace: bool) -> int:
	grid = maxi(grid, 1)
	var order: Array = song.data["order"]
	var drums := channel < 0
	var channels: Array = SongGenerator.LAYER_CHANNELS["Drums"] if drums else [channel]
	# Work on each section once, even when the order plays it more than once.
	var work := {}
	for pos in covered:
		var section := int(order[pos])
		for c in channels:
			var key := Vector2i(section, int(c))
			if not work.has(key):
				work[key] = PatternEdit.notes_at(song, section, int(c))
		if replace:
			var span: Vector2i = covered[pos]
			for c in channels:
				var key := Vector2i(section, int(c))
				var kept: Array = []
				for n in work[key]:
					if int(n[0]) < span.x or int(n[0]) > span.y:
						kept.append(n)
				work[key] = kept
	var written := 0
	for take in notes:
		var start := int(roundf(float(take[0]) / grid)) * grid
		var at := SongEdit.locate(song, start)
		if at.x < 0:
			continue
		var section := int(order[at.x])
		var steps := int(song.data["sections"][section]["length"])
		var length := maxi(int(roundf((float(take[1]) - float(take[0])) / grid)) * grid, 1)
		length = mini(length, steps - at.y)
		var pitch := int(take[2])
		var velocity := clampi(int(take[3]), 1, 127)
		var note: Array
		var c := channel
		if drums:
			var instrument := PatternEdit.drum_for_midi(pitch)
			c = PatternEdit.drum_channel(instrument)
			note = [at.y, 1, int(DrumWriter.PITCH[instrument]), velocity, instrument]
		else:
			note = [at.y, length, pitch, velocity]
		var key := Vector2i(section, c)
		if not work.has(key):
			work[key] = PatternEdit.notes_at(song, section, c)
		work[key].append(note)
		written += 1
	for key in work:
		PatternEdit.set_notes(song, key.x, key.y, work[key])
	return written
