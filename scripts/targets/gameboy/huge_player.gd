class_name HugePlayer
extends RefCounted
## hUGEDriver's playback routine, hUGE_dosound, reimplemented for previews.
##
## Reads the same patterns and orders that [GbCWriter] exports, follows the
## driver's rules for notes, instruments and effects, and writes the same
## values to the same sound registers of a [GbApu]. Call [method dosound] at
## the song's tick rate, as the game's timer interrupt would.
##
## Based on hUGEDriver (public domain): https://github.com/SuperDisk/hUGEDriver

## hUGEDriver's note table: the 11-bit period for each note, C-3 to B-8.
const NOTE_TABLE := [
	44, 156, 262, 363, 457, 547, 631, 710, 786, 854, 923, 986,
	1046, 1102, 1155, 1205, 1253, 1297, 1339, 1379, 1417, 1452, 1486, 1517,
	1546, 1575, 1602, 1627, 1650, 1673, 1694, 1714, 1732, 1750, 1767, 1783,
	1798, 1812, 1825, 1837, 1849, 1860, 1871, 1881, 1890, 1899, 1907, 1915,
	1923, 1930, 1936, 1943, 1949, 1954, 1959, 1964, 1969, 1974, 1978, 1982,
	1985, 1988, 1992, 1995, 1998, 2001, 2004, 2006, 2009, 2011, 2013, 2015,
]
const NO_WAVE := 100
const ENV_REG := [GbApu.NR12, GbApu.NR22, GbApu.NR32, GbApu.NR42]

var apu: GbApu
var song: GbSong
## Channels the game has taken over (bit per channel), as hUGE_mute_channel.
var mute_mask := 0
var ticks_per_row := 6
var tick := 0
var counter := 0
var row := 0
var current_order := 0

var _patterns: Array = []
var _orders: Array = []
var _order_rows: Array = []
var _order_count := 0
var _row_break := 0
var _next_order := 0
var _current_wave := NO_WAVE
var _pattern: Array[PackedInt32Array] = []
var _period := PackedInt32Array([0, 0, 0, 0])
var _note := PackedInt32Array([0, 0, 0, 0])
var _highmask := PackedInt32Array([0, 0, 0, 0])
var _step_width := 0


func _init(gb_song: GbSong, gb_apu: GbApu) -> void:
	song = gb_song
	apu = gb_apu
	var tracks := song.build_tracks()
	_patterns = tracks["patterns"]
	_orders = tracks["orders"]
	_order_rows = tracks["order_rows"]
	_order_count = _orders[0].size()
	for c in 4:
		_pattern.append(PackedInt32Array())
	start()


## hUGE_init: resets the driver state and loads the first order. Also sets
## the sound registers the example ROM sets before it starts the song.
func start(order := 0, from_row := 0) -> void:
	ticks_per_row = song.ticks_per_row
	tick = 0
	counter = 0
	_row_break = 0
	_next_order = 0
	mute_mask = 0
	_period.fill(0)
	_note.fill(0)
	_highmask.fill(0)
	_step_width = 0
	_current_wave = NO_WAVE
	apu.reset()
	apu.write(GbApu.NR52, 0x80)
	apu.write(GbApu.NR51, 0xFF)
	apu.write(GbApu.NR50, 0x77)
	current_order = clampi(order, 0, maxi(_order_count - 1, 0))
	_load_patterns()
	row = from_row


## Song row the driver is on (0 at the start of the song), or -1 once it has
## reached the closing silence of a song that does not loop.
func get_song_row() -> int:
	if current_order >= _order_rows.size():
		return -1
	var start_row := int(_order_rows[current_order])
	return -1 if start_row < 0 else start_row + row


## Order that holds song row [param song_row], and the row within it.
func find_position(song_row: int) -> Vector2i:
	var best := Vector2i(0, 0)
	for i in _order_rows.size():
		var start_row := int(_order_rows[i])
		if start_row >= 0 and start_row <= song_row:
			best = Vector2i(i, song_row - start_row)
	return best


## One driver tick.
func dosound() -> void:
	if tick == 0:
		for c in 4:
			_process_row(c)
	else:
		for c in 4:
			if mute_mask & (1 << c):
				continue
			var cell := _cell(c)
			if cell[3] == 0:
				continue
			_do_effect(c, cell[2], cell[3])
	_tick_time()


## Moves to a row without resetting the sound, like a position jump.
func jump(order: int, to_row: int) -> void:
	current_order = clampi(order, 0, maxi(_order_count - 1, 0))
	_load_patterns()
	row = to_row
	tick = 0


func mute_channel(channel: int, mute: bool) -> void:
	mute_mask = (mute_mask & ~(1 << channel)) | ((1 if mute else 0) << channel)
	if mute:
		_note_cut(channel)


func _load_patterns() -> void:
	for c in 4:
		var index := int(_orders[c][current_order]) if current_order < _orders[c].size() else 0
		_pattern[c] = _patterns[index] if index < _patterns.size() else PackedInt32Array()


func _cell(channel: int) -> PackedInt32Array:
	var rows := _pattern[channel]
	var i := row * 4
	if i + 3 >= rows.size():
		return PackedInt32Array([GbSong.NO_NOTE, 0, 0, 0])
	return rows.slice(i, i + 4)


func _muted(channel: int) -> bool:
	return (mute_mask & (1 << channel)) != 0


func _process_row(c: int) -> void:
	var cell := _cell(c)
	var note := cell[0]
	var instrument := cell[1]
	var has_note := note < GbSong.LAST_NOTE
	if has_note:
		_note[c] = note
		if c == 3:
			_period[3] = get_note_poly(note)
		elif cell[2] != 0x3:
			_period[c] = NOTE_TABLE[note]
		if instrument == 0:
			_highmask[c] &= 0x7F
		elif not _muted(c):
			_load_instrument(c, instrument)
	_do_effect(c, cell[2], cell[3])
	if has_note:
		_play_note(c)


func _load_instrument(c: int, number: int) -> void:
	var index := number - 1
	match c:
		0, 1:
			if index >= song.duty_instruments.size():
				return
			var bytes := GbSong.duty_bytes(song.duty_instruments[index])
			if c == 0:
				apu.write(GbApu.NR10, bytes[0])
				apu.write(GbApu.NR11, bytes[1])
				apu.write(GbApu.NR12, bytes[2])
			else:
				apu.write(GbApu.NR21, bytes[1])
				apu.write(GbApu.NR22, bytes[2])
			_highmask[c] = bytes[3]
		2:
			if index >= song.wave_instruments.size():
				return
			var bytes := GbSong.wave_bytes(song.wave_instruments[index])
			apu.write(GbApu.NR31, bytes[0])
			apu.write(GbApu.NR32, bytes[1])
			if bytes[2] != _current_wave:
				_load_wave(bytes[2])
			_highmask[2] = bytes[3]
		3:
			if index >= song.noise_instruments.size():
				return
			var bytes := GbSong.noise_bytes(song.noise_instruments[index])
			apu.write(GbApu.NR42, bytes[0])
			var hm := bytes[1]
			apu.write(GbApu.NR41, hm & 0x3F)
			_step_width = (hm & 0x80) >> 4
			_period[3] |= _step_width
			_highmask[3] = (hm & 0x40) | 0x80


func _load_wave(index: int) -> void:
	_current_wave = index
	var nr51 := apu.read(GbApu.NR51)
	apu.write(GbApu.NR51, nr51 & 0xBB)
	apu.write(GbApu.NR30, 0)
	var ram := song.wave_ram(index)
	for i in 16:
		apu.write(GbApu.WAVE_RAM + i, ram[i])
	apu.write(GbApu.NR30, 0x80)
	apu.write(GbApu.NR51, nr51)


func _play_note(c: int) -> void:
	if _muted(c):
		return
	match c:
		0:
			apu.write(GbApu.NR13, _period[0] & 0xFF)
			apu.write(GbApu.NR14, _highmask[0] | (_period[0] >> 8))
		1:
			apu.write(GbApu.NR23, _period[1] & 0xFF)
			apu.write(GbApu.NR24, _highmask[1] | (_period[1] >> 8))
		2:
			# Retriggering CH3 while it reads wave RAM corrupts it, so the
			# driver pauses the channel first.
			var nr51 := apu.read(GbApu.NR51)
			apu.write(GbApu.NR51, nr51 & 0xBB)
			apu.write(GbApu.NR30, 0)
			apu.write(GbApu.NR30, 0xFF)
			apu.write(GbApu.NR33, _period[2] & 0xFF)
			apu.write(GbApu.NR34, _highmask[2] | (_period[2] >> 8))
			apu.write(GbApu.NR51, nr51)
		3:
			apu.write(GbApu.NR43, _period[3])
			apu.write(GbApu.NR44, _highmask[3])


## Sets a channel's pitch without retriggering it. For the noise channel,
## [param value] is a note, otherwise a period.
func _update_freq(c: int, value: int) -> void:
	if _muted(c):
		return
	match c:
		0:
			_period[0] = value
			apu.write(GbApu.NR13, value & 0xFF)
			apu.write(GbApu.NR14, (value >> 8) & 7)
		1:
			_period[1] = value
			apu.write(GbApu.NR23, value & 0xFF)
			apu.write(GbApu.NR24, (value >> 8) & 7)
		2:
			_period[2] = value
			apu.write(GbApu.NR33, value & 0xFF)
			apu.write(GbApu.NR34, (value >> 8) & 7)
		3:
			apu.write(GbApu.NR43, get_note_poly(value & 0xFF) | _step_width)
			apu.write(GbApu.NR44, 0)


func _do_effect(c: int, effect: int, param: int) -> void:
	if effect == 0 and param == 0:
		return
	var first_tick := tick == 0
	match effect:
		0x0:
			# Arpeggio: base note, +low nibble, +high nibble, one per tick.
			var phase := (counter - 1) & 0xFF
			while phase >= 3:
				phase -= 3
			var note := _note[c]
			if phase == 0:
				note += param & 0x0F
			elif phase == 1:
				note += param >> 4
			_update_freq(c, _period_of(note))
		0x4:
			if first_tick:
				return
			var base := _period_of(_note[c])
			if counter & (param >> 4) == 0:
				base += param & 0x0F
			_update_freq(c, base)
		0x5:
			if first_tick:
				apu.write(GbApu.NR50, param)
		0x8:
			if first_tick:
				apu.write(GbApu.NR51, param)
		0x9:
			if first_tick and not _muted(c):
				if c == 0:
					apu.write(GbApu.NR11, param)
				elif c == 1:
					apu.write(GbApu.NR21, param)
		0xB:
			if first_tick:
				if _row_break == 0:
					_row_break = 1
				_next_order = param
		0xC:
			if first_tick:
				_set_volume(c, param)
		0xD:
			if first_tick:
				_row_break = param
		0xE:
			if tick == param and not _muted(c):
				_note_cut(c)
		0xF:
			if first_tick:
				ticks_per_row = param


func _period_of(note: int) -> int:
	return NOTE_TABLE[clampi(note, 0, NOTE_TABLE.size() - 1)]


func _set_volume(c: int, param: int) -> void:
	if _muted(c):
		return
	var swapped := ((param & 0x0F) << 4) | (param >> 4)
	match c:
		0, 1:
			var reg: int = ENV_REG[c]
			apu.write(reg, (apu.read(reg) & 0x0F) | swapped)
			_play_note(c)
		2:
			var level := 0
			if swapped >= 0xA0:
				level = 0x20
			elif swapped >= 0x50:
				level = 0x40
			elif swapped != 0:
				level = 0x60
			apu.write(GbApu.NR32, level)
		3:
			apu.write(GbApu.NR42, swapped)
			_play_note(3)


func _note_cut(c: int) -> void:
	var reg: int = ENV_REG[c]
	apu.write(reg, 0)
	if c != 2:
		apu.write(reg + 1, 0xFF)


func _tick_time() -> void:
	counter = (counter + 1) & 0xFF
	tick += 1
	var speed := ticks_per_row if ticks_per_row > 0 else 256
	if tick < speed:
		return
	tick = 0
	if _row_break != 0:
		var start_row := _row_break - 1
		_row_break = 0
		if _next_order != 0:
			current_order = _next_order - 1
			_next_order = 0
		else:
			_advance_order()
		current_order = clampi(current_order, 0, maxi(_order_count - 1, 0))
		_load_patterns()
		row = start_row
		return
	row += 1
	if row >= GbSong.PATTERN_ROWS:
		_advance_order()
		_load_patterns()
		row = 0


func _advance_order() -> void:
	current_order += 1
	if current_order >= _order_count:
		current_order = 0


## hUGEDriver's mapping from a note to the noise channel's NR43 value.
static func get_note_poly(note: int) -> int:
	var a := ((note + 192) & 0xFF) ^ 0xFF
	if a < 7:
		return a
	var l := ((a >> 2) - 1) & 0xFF
	var c := (a & 3) + 4
	return c | (((l & 0x0F) << 4) | (l >> 4))
