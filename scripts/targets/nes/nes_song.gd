class_name NesSong
extends RefCounted
## A song arranged for the NES, in FamiStudio's own terms: four channels of
## notes (each with a duration, an instrument, a volume and an optional
## arpeggio), the instruments' envelopes, and a groove of video frames per
## row. [NesArranger] makes one from a [ChipSong]; [FamiStudioWriter] writes
## it as a FamiStudio text project, and [NesSequencer] plays it the way
## FamiStudio's sound engine does, through an emulated 2A03.
##
## One row is one step of the source song (a 16th note in 4/4).

const CHANNEL_NAMES: PackedStringArray = ["Pulse 1", "Pulse 2", "Triangle", "Noise"]
## FamiStudio's internal channel names, in the same order.
const FAMISTUDIO_CHANNELS: PackedStringArray = ["Square1", "Square2", "Triangle", "Noise"]
const PULSE1 := 0
const PULSE2 := 1
const TRIANGLE := 2
const NOISE := 3
## FamiStudio note values run from 1 ("C0") to 96 ("B7"). Value 1 is 32.7 Hz
## on the pulse channels (MIDI 24) and an octave lower on the triangle.
const FIRST_NOTE := 1
const LAST_NOTE := 96
## MIDI note of FamiStudio note value 0 on each tonal channel.
const MIDI_OFFSET := [23, 23, 11, 0]
## Lowest note value whose period fits the 11-bit timer.
const LOWEST_TONAL_NOTE := 10
## FamiStudio's song length limit, in patterns.
const MAX_PATTERNS := 256
## Most rows in one pattern (FamiStudio allows longer; this keeps them tidy).
const MAX_PATTERN_ROWS := 64
## Envelope length limit.
const MAX_ENVELOPE := 255

var title := "song"
## Video frames per second: the rate the sound driver runs at.
var frame_hz := NesApu.FRAME_HZ
## The arrangement as a four-channel [ChipSong]: its timing, sections, cues
## and notes. Used for the timeline and for MIDI export.
var source: ChipSong
var steps_per_bar := 16
var steps_per_beat := 4
## Frames per row, cycled. FamiStudio requires every value to be the
## shortest one or one more.
var groove := PackedInt32Array([6])
var row_count := 0
var looping := true
var loop_start_row := 0
## Sections in play order: [{name, row, length}]. Patterns break on them.
var section_rows: Array = []
## Per channel, notes in row order: {row, length, note, instrument,
## volume (1 to 15), arp (index into [member arpeggios], or -1)}.
var notes: Array = [[], [], [], []]
## {name, volume: Array[int], volume_loop, arp: Array[int], arp_loop,
## pitch: Array[int], pitch_loop, duty: Array[int], duty_loop}. Missing or
## empty envelopes play FamiStudio's defaults (volume 15, no offset, duty 0).
var instruments: Array = []
## {name, values: Array[int], loop}: semitone offsets, one per frame.
var arpeggios: Array = []
## Which source song channels feed each NES channel, by row (see
## [member GbSong.feeds]).
var feeds: Array = []
## What the arranger changed to fit the chip, one line each.
var report: PackedStringArray = []
## The arranger's tallies behind [member report] (parts promoted, moved or
## dropped), so other targets built on this arrangement can report too.
var stats: Dictionary = {}


## Frames per row on average.
func frames_per_row() -> float:
	var total := 0
	for f in groove:
		total += f
	return float(total) / maxf(groove.size(), 1)


func get_bpm() -> float:
	return frame_hz / frames_per_row() * 60.0 / maxf(steps_per_beat, 1)


## Frames from the start of the song to the start of [param row].
func frames_before(row: int) -> int:
	var full := row / groove.size()
	var total := 0
	for f in groove:
		total += f
	var frames := full * total
	for i in row % groove.size():
		frames += groove[i]
	return frames


## Frames row [param row] lasts.
func frames_in_row(row: int) -> int:
	return groove[row % groove.size()]


## The groove for a tempo. Returns {groove, bpm}. Grooves of 1, 2 or 4 rows
## divide any bar, so every pattern starts at the same point in the groove.
static func choose_groove(bpm: float, steps_per_beat: int, frame_rate := NesApu.FRAME_HZ) -> Dictionary:
	var rows_per_second := bpm * steps_per_beat / 60.0
	var wanted := frame_rate / maxf(rows_per_second, 0.1)
	var base := clampi(int(floor(wanted)), 2, 30)
	var best := PackedInt32Array([base])
	var best_error := INF
	for size in [1, 2, 4]:
		for longer in size + 1:
			var error := absf(base + float(longer) / size - wanted)
			if error < best_error - 0.0001:
				best_error = error
				best = PackedInt32Array()
				for i in size:
					best.append(base + 1 if i < longer else base)
	# A groove where every row is one frame longer is just a slower tempo.
	if best.size() > 1 and best[best.size() - 1] == best[0]:
		best = PackedInt32Array([best[0]])
	var total := 0
	for f in best:
		total += f
	var actual := frame_rate / (float(total) / best.size()) * 60.0 / maxf(steps_per_beat, 1)
	return {"groove": best, "bpm": actual}


## The timer period for a note value on a pulse or the triangle channel, as
## in FamiStudio's NTSC note table: value 1 is 32.7 Hz on a pulse channel.
static func note_period(note: int) -> int:
	if note < FIRST_NOTE:
		return 0
	var hz := 32.7032 * pow(2.0, (note - 1) / 12.0)
	return roundi(NesApu.CPU_HZ / (16.0 * hz)) - 1


## FamiStudio's name for a note value, such as "C#4".
static func note_name(note: int) -> String:
	var names: PackedStringArray = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
	var v := clampi(note, FIRST_NOTE, LAST_NOTE) - 1
	return "%s%d" % [names[v % 12], v / 12]


## The note value for a MIDI note on a tonal channel, moved by octaves into
## the range the channel can play. Returns {note, moved}.
static func fit_note(channel: int, midi: int) -> Dictionary:
	var note: int = midi - MIDI_OFFSET[channel]
	var moved := false
	while note < LOWEST_TONAL_NOTE:
		note += 12
		moved = true
	while note > LAST_NOTE:
		note -= 12
		moved = true
	return {"note": note, "moved": moved}


## The MIDI note a note value sounds on [param channel].
static func midi_of(channel: int, note: int) -> int:
	return note + MIDI_OFFSET[channel]


## FamiStudio's volume table: a note's volume column times its envelope,
## rounded, and never zero unless one of them is.
static func mix_volume(note_volume: int, envelope: int) -> int:
	if note_volume <= 0 or envelope <= 0:
		return 0
	return maxi(1, roundi(note_volume * envelope / 15.0))


## Splits the rows into patterns: sections break patterns, and within a
## section every [param bars] bars. Returns [[first_row, rows], ...].
func pattern_chunks() -> Array:
	var bars := 1
	while true:
		var chunks := _chunks(bars)
		if chunks.size() <= MAX_PATTERNS or bars * steps_per_bar >= MAX_PATTERN_ROWS * 4:
			return chunks
		bars *= 2
	return []


func _chunks(bars: int) -> Array:
	var chunk_rows := maxi(bars * steps_per_bar, 1)
	var chunks: Array = []
	for section in section_rows:
		var start := int(section["row"])
		var end := mini(start + int(section["length"]), row_count)
		var r := start
		while r < end:
			var n := mini(chunk_rows, end - r)
			chunks.append([r, n])
			r += n
	if chunks.is_empty():
		chunks.append([0, maxi(row_count, 1)])
	return chunks


## Source song channels feeding NES [param channel] at [param row].
func sources_at(row: int, channel: int) -> Array:
	var found: Array = []
	for feed in feeds:
		if int(feed["row"]) > row:
			break
		found = feed["sources"][channel]
	return found


## Total notes in the song, for reports and tests.
func note_count() -> int:
	var total := 0
	for c in 4:
		total += (notes[c] as Array).size()
	return total
