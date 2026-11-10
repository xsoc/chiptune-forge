class_name GbSong
extends RefCounted
## A song arranged for the Game Boy, in hUGEDriver's own terms: four channels
## of tracker rows (note, instrument, effect), plus the instruments and waves
## they use. [GbArranger] makes one from a [ChipSong]; [GbCWriter] writes it
## as C for GBDK-2020, and [GbSequencer] plays it through an emulation of the
## driver and the sound chip, so the preview matches the console.
##
## One row is one step of the source song (a 16th note in 4/4).

const CHANNEL_NAMES: PackedStringArray = ["Pulse 1", "Pulse 2", "Wave", "Noise"]
## Most rows in one hUGEDriver pattern.
const PATTERN_ROWS := 64
## hUGEDriver's "no note" value. Notes run from 0 (C-3 in hUGETracker) to 71.
const NO_NOTE := 90
const LAST_NOTE := 72
## MIDI note that hUGE note 0 sounds on each channel. The wave channel plays
## an octave below the pulse channels for the same note.
const BASE_MIDI := [36, 36, 24, 36]

const FX_ARPEGGIO := 0x0
const FX_VIBRATO := 0x4
const FX_POSITION_JUMP := 0xB
const FX_SET_VOLUME := 0xC
const FX_PATTERN_BREAK := 0xD
const FX_NOTE_CUT := 0xE

## Game Boy timer clocks: TAC value -> input clock in Hz (normal speed).
const TIMER_CLOCKS := {0x04: 4096.0, 0x07: 16384.0}
## Usable data in one 16 KB ROM bank, after the driver itself.
const BANK_BYTES := 16384

var title := "song"
## The arrangement as a four-channel [ChipSong]: its timing, sections, cues
## and notes. Used for the timeline and for MIDI and WAV export.
var source: ChipSong
var steps_per_bar := 16
var ticks_per_row := 6
## Timer setup for the driver's tick: TAC and TMA register values.
var timer_tac := 0x04
var timer_tma := 0
var tick_hz := 60.0
var row_count := 0
## Per channel, four ints per row: note, instrument, effect, parameter.
var cells: Array[PackedInt32Array] = []
var looping := true
var loop_start_row := 0
## Sections in play order: [{name, row, length}]. Patterns break on them.
var section_rows: Array = []
## Instruments, numbered from 1 in the order they appear here.
## Duty: {name, sweep, duty (0 to 3), envelope, length, length_on}.
var duty_instruments: Array = []
## Wave: {name, level (0 to 3, NR32 code), wave, length, length_on}.
var wave_instruments: Array = []
## Noise: {name, envelope, narrow (7-bit LFSR), length, length_on}.
var noise_instruments: Array = []
## Wave tables: 32 four-bit samples each.
var waves: Array[PackedByteArray] = []
## Channel (0 to 3) that game sound effects may interrupt, or -1.
var sfx_channel := -1
## True when that channel was left empty for sound effects.
var sfx_free := false
## Which source song channels feed each Game Boy channel, by row:
## [{row, sources: [[...], [...], [...], [...]]}] in row order. Lets the
## preview follow the Layers screen's mutes and fades.
var feeds: Array = []
## What the arranger changed to fit the chip, one line each.
var report: PackedStringArray = []

var _tracks: Dictionary = {}


func _init() -> void:
	for c in 4:
		cells.append(PackedInt32Array())


## Clears the rows to [param rows] empty rows per channel.
func resize(rows: int) -> void:
	row_count = rows
	for c in 4:
		var data := PackedInt32Array()
		data.resize(rows * 4)
		for r in rows:
			data[r * 4] = NO_NOTE
		cells[c] = data
	_tracks = {}


func get_cell(channel: int, row: int) -> PackedInt32Array:
	return cells[channel].slice(row * 4, row * 4 + 4)


func set_cell(channel: int, row: int, note: int, instrument: int, effect := 0, param := 0) -> void:
	var data := cells[channel]
	var i := row * 4
	data[i] = note
	data[i + 1] = instrument
	data[i + 2] = effect
	data[i + 3] = param
	_tracks = {}


func set_effect(channel: int, row: int, effect: int, param: int) -> void:
	var i := row * 4
	cells[channel][i + 2] = effect
	cells[channel][i + 3] = param
	_tracks = {}


func has_effect(channel: int, row: int) -> bool:
	var i := row * 4
	return cells[channel][i + 2] != 0 or cells[channel][i + 3] != 0


func get_bpm() -> float:
	return tick_hz / ticks_per_row * 60.0 / maxf(source.get_steps_per_beat() if source else 4, 1)


## The hUGEDriver bytes for a duty instrument: sweep, length and duty,
## envelope, then the high mask (trigger, length enable, table).
static func duty_bytes(inst: Dictionary) -> PackedByteArray:
	return PackedByteArray([
		int(inst.get("sweep", 0x08)),
		(int(inst.get("duty", 2)) << 6) | (int(inst.get("length", 0)) & 0x3F),
		int(inst.get("envelope", 0xF0)),
		0x80 | (0x40 if inst.get("length_on", false) else 0),
	])


static func wave_bytes(inst: Dictionary) -> PackedByteArray:
	return PackedByteArray([
		int(inst.get("length", 0)) & 0xFF,
		(int(inst.get("level", 1)) & 3) << 5,
		int(inst.get("wave", 0)),
		0x80 | (0x40 if inst.get("length_on", false) else 0),
	])


static func noise_bytes(inst: Dictionary) -> PackedByteArray:
	return PackedByteArray([
		int(inst.get("envelope", 0xF1)),
		(0x80 if inst.get("narrow", false) else 0) | (0x40 if inst.get("length_on", false) else 0) | (int(inst.get("length", 0)) & 0x3F),
	])


## A wave as the 16 bytes of wave RAM (two samples per byte, high nibble first).
func wave_ram(index: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(16)
	var samples: PackedByteArray = waves[index] if index < waves.size() else PackedByteArray()
	for i in 16:
		var hi := samples[i * 2] if i * 2 < samples.size() else 0
		var lo := samples[i * 2 + 1] if i * 2 + 1 < samples.size() else 0
		out[i] = ((hi & 0x0F) << 4) | (lo & 0x0F)
	return out


## Picks the driver speed for a tempo: rows of [param ticks_per_row] ticks,
## with the tick from the Game Boy timer. Returns {ticks_per_row, tac, tma,
## tick_hz, bpm}. The tempo is matched as closely as the timer allows, with
## ticks near 60 Hz so arpeggios and note cuts sound as usual.
static func choose_timing(bpm: float, steps_per_beat: int) -> Dictionary:
	var rows_per_second := bpm * steps_per_beat / 60.0
	var best := {}
	var best_score := INF
	for tac in TIMER_CLOCKS:
		var clock: float = TIMER_CLOCKS[tac]
		for ticks in range(1, 25):
			var wanted := rows_per_second * ticks
			if wanted < 30.0 or wanted > 140.0:
				continue
			var divider := clampi(roundi(clock / wanted), 1, 256)
			var hz := clock / divider
			var actual := hz / ticks * 60.0 / steps_per_beat
			var error := absf(actual - bpm) / bpm
			var score := error * 1000.0 + absf(hz - 64.0) / 64.0
			if score < best_score:
				best_score = score
				best = {"ticks_per_row": ticks, "tac": tac, "tma": 256 - divider, "tick_hz": hz, "bpm": actual}
	if best.is_empty():
		best = {"ticks_per_row": 6, "tac": 0x04, "tma": 256 - 68, "tick_hz": 4096.0 / 68.0, "bpm": 4096.0 / 68.0 / 6.0 * 60.0 / steps_per_beat}
	return best


## Splits the rows into hUGEDriver patterns and orders. Returns
## {patterns: Array[PackedInt32Array] (four ints per row), orders: four
## Arrays of pattern indexes, order_rows: the first song row of each order
## (-1 for the closing silence), loop_order}.
##
## Patterns break at section boundaries and every whole number of bars up to
## 64 rows. A pattern shorter than 64 rows ends with a pattern break (D01);
## the last one jumps back to the loop start (Bxx), or, for a song that ends,
## to a short pattern of silence that repeats.
func build_tracks() -> Dictionary:
	if not _tracks.is_empty():
		return _tracks
	var chunk_rows := maxi((PATTERN_ROWS / maxi(steps_per_bar, 1)) * steps_per_bar, 1)
	if steps_per_bar > PATTERN_ROWS:
		chunk_rows = PATTERN_ROWS
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
		chunks.append([0, maxi(mini(row_count, PATTERN_ROWS), 1)])
	var loop_order := 0
	for i in chunks.size():
		if int(chunks[i][0]) == loop_start_row:
			loop_order = i
			break

	var slices: Array = []
	for i in chunks.size():
		var start: int = chunks[i][0]
		var n: int = chunks[i][1]
		var per_channel: Array[PackedInt32Array] = []
		for c in 4:
			per_channel.append(_slice_rows(c, start, n))
		var last := i == chunks.size() - 1
		if last and looping:
			_place_global(per_channel, n - 1, FX_POSITION_JUMP, loop_order + 1)
		elif n < PATTERN_ROWS:
			_place_global(per_channel, n - 1, FX_PATTERN_BREAK, 1)
		slices.append(per_channel)
	var order_rows: Array = []
	for chunk in chunks:
		order_rows.append(int(chunk[0]))
	if not looping:
		# Silence every channel, then hold on this pattern for good.
		var end_order := slices.size()
		var tail: Array[PackedInt32Array] = []
		for c in 4:
			var rows := PackedInt32Array([NO_NOTE, 0, FX_NOTE_CUT, 0, NO_NOTE, 0, 0, 0])
			tail.append(rows)
		tail[0][6] = FX_POSITION_JUMP
		tail[0][7] = end_order + 1
		slices.append(tail)
		order_rows.append(-1)

	var patterns: Array[PackedInt32Array] = []
	var index_of := {}
	var orders: Array = [[], [], [], []]
	for per_channel in slices:
		for c in 4:
			var rows: PackedInt32Array = per_channel[c]
			var key := rows.to_byte_array().hex_encode()
			if not index_of.has(key):
				index_of[key] = patterns.size()
				patterns.append(rows)
			orders[c].append(index_of[key])
	_tracks = {"patterns": patterns, "orders": orders, "order_rows": order_rows, "loop_order": loop_order}
	return _tracks


## Bytes the song data takes in ROM: patterns, orders, instruments, waves
## and the song descriptor.
func data_size() -> int:
	var tracks := build_tracks()
	var bytes := 21
	for rows in tracks["patterns"]:
		bytes += rows.size() / 4 * 3
	bytes += tracks["orders"][0].size() * 2 * 4 + 1
	bytes += (duty_instruments.size() + wave_instruments.size() + noise_instruments.size()) * 6
	bytes += waves.size() * 16
	return bytes


## Source song channels feeding Game Boy [param channel] at [param row].
func sources_at(row: int, channel: int) -> Array:
	var found: Array = []
	for feed in feeds:
		if int(feed["row"]) > row:
			break
		found = feed["sources"][channel]
	return found


func _slice_rows(channel: int, start: int, count: int) -> PackedInt32Array:
	return cells[channel].slice(start * 4, (start + count) * 4)


## Puts a global effect (one that affects the whole song, such as a pattern
## break) on a row, in the effect column of a channel that is not using it.
## If every channel has an effect there, the noise channel's gives way.
static func _place_global(per_channel: Array[PackedInt32Array], row: int, effect: int, param: int) -> void:
	var target := 3
	for c in [3, 2, 1, 0]:
		var rows: PackedInt32Array = per_channel[c]
		if rows[row * 4 + 2] == 0 and rows[row * 4 + 3] == 0:
			target = c
			break
	per_channel[target][row * 4 + 2] = effect
	per_channel[target][row * 4 + 3] = param
