class_name SongEdit
extends RefCounted
## Edits a song above the level of single notes: whole parts of a section,
## bars, the sections themselves and their play order, the loop, the tempo,
## and new blank songs. [PatternEdit] handles single notes.
##
## Every function changes [code]song.data[/code] in place and keeps the song
## valid: after a change to the sections or the order, the section cues and
## the loop are worked out again (see [method refresh_cues]).

const DEFAULT_ENERGY := 0.6
const MAX_BARS := 64


# Positions and steps ---------------------------------------------------------

static func bar_steps(song: ChipSong) -> int:
	return song.get_steps_per_beat() * song.get_beats_per_bar()


## The first step of each entry of the play order.
static func order_starts(song: ChipSong) -> PackedInt32Array:
	var starts := PackedInt32Array()
	var step := 0
	for index in song.data["order"]:
		starts.append(step)
		step += int(song.data["sections"][int(index)]["length"])
	return starts


## The entry of the play order that plays at [param step] (from the song
## start), as Vector2i(order position, step within that section), or
## (-1, -1) past the end.
static func locate(song: ChipSong, step: int) -> Vector2i:
	var start := 0
	var order: Array = song.data["order"]
	for pos in order.size():
		var length := int(song.data["sections"][int(order[pos])]["length"])
		if step >= start and step < start + length:
			return Vector2i(pos, step - start)
		start += length
	return Vector2i(-1, -1)


## The loop as order positions, Vector2i(first, last).
static func loop_positions(song: ChipSong) -> Vector2i:
	var starts := order_starts(song)
	var order: Array = song.data["order"]
	if order.is_empty():
		return Vector2i.ZERO
	var loop_start := song.get_loop_start_step()
	var loop_end := song.get_loop_end_step()
	var first := 0
	var last := order.size() - 1
	for pos in starts.size():
		if starts[pos] <= loop_start:
			first = pos
	for pos in range(starts.size() - 1, -1, -1):
		var end := starts[pos] + int(song.data["sections"][int(order[pos])]["length"])
		if end >= loop_end:
			last = pos
	return Vector2i(first, maxi(first, last))


## Loops the song from the start of order position [param first] to the end
## of [param last].
static func set_loop(song: ChipSong, first: int, last: int) -> void:
	refresh_cues(song, first, last)


## Works out the section cues and the loop again after the order changed.
## The loop runs from order position [param first] to the end of
## [param last] (both clamped to the order).
static func refresh_cues(song: ChipSong, first: int, last: int) -> void:
	var order: Array = song.data["order"]
	var count := order.size()
	first = clampi(first, 0, maxi(count - 1, 0))
	last = clampi(last, first, maxi(count - 1, 0))
	var cues: Array = []
	var step := 0
	var loop_start := 0
	var loop_end := 0
	for pos in count:
		var section: Dictionary = song.data["sections"][int(order[pos])]
		cues.append({"name": "section:%s" % section["name"], "step": step})
		if pos == first:
			loop_start = step
		step += int(section["length"])
		if pos == last:
			loop_end = step
	if count == 0:
		loop_end = 0
	# Cues the user added (any not made from the sections or loop) stay.
	for cue in song.data.get("cues", []):
		var cue_name := str(cue.get("name", ""))
		if not cue_name.begins_with("section:") and cue_name != "loop_start" and cue_name != "loop_end" and int(cue.get("step", 0)) < step:
			cues.append(cue)
	cues.append({"name": "loop_start", "step": loop_start})
	cues.append({"name": "loop_end", "step": loop_end})
	song.data["cues"] = cues
	song.data["timing"]["loop_start"] = loop_start
	song.data["timing"]["loop_end"] = loop_end


# Sections and order ----------------------------------------------------------

## A name for a new section that no other section has: the next free letter.
static func free_name(song: ChipSong) -> String:
	var used := {}
	for s in song.data["sections"]:
		used[str(s["name"])] = true
	for code in range(65, 91):
		var letter := String.chr(code)
		if not used.has(letter):
			return letter
	var n := 2
	while used.has("Z%d" % n):
		n += 1
	return "Z%d" % n


## Adds a new, silent section of [param bars] bars at [param pos] in the play
## order. Returns its section index.
static func add_section(song: ChipSong, pos: int, bars: int, section_name := "") -> int:
	var loop := loop_positions(song)
	var ids: Array = []
	for c in song.data["channels"].size():
		ids.append(-1)
	var sections: Array = song.data["sections"]
	sections.append({
		"name": section_name if section_name != "" else free_name(song),
		"length": clampi(bars, 1, MAX_BARS) * bar_steps(song),
		"patterns": ids,
		"energy": DEFAULT_ENERGY,
		"chords": [],
	})
	var order: Array = song.data["order"]
	pos = clampi(pos, 0, order.size())
	order.insert(pos, sections.size() - 1)
	_after_insert(song, loop, pos)
	return sections.size() - 1


## Plays the section at order position [param pos] again, right after it.
## Both entries are the same section, so editing one changes both.
static func repeat_section(song: ChipSong, pos: int) -> void:
	var order: Array = song.data["order"]
	if pos < 0 or pos >= order.size():
		return
	var loop := loop_positions(song)
	order.insert(pos + 1, order[pos])
	_after_insert(song, loop, pos + 1)


## Copies the section at order position [param pos] into a new section with
## its own patterns, placed right after it, so it can be changed on its own.
## Returns the new section index.
static func copy_section(song: ChipSong, pos: int) -> int:
	var order: Array = song.data["order"]
	if pos < 0 or pos >= order.size():
		return -1
	var loop := loop_positions(song)
	var source: Dictionary = song.data["sections"][int(order[pos])]
	var copy: Dictionary = source.duplicate(true)
	copy["name"] = free_name(song)
	var patterns: Array = song.data["patterns"]
	var ids: Array = copy["patterns"]
	for c in ids.size():
		if int(ids[c]) >= 0:
			patterns.append({"notes": (patterns[int(ids[c])]["notes"] as Array).duplicate(true)})
			ids[c] = patterns.size() - 1
	var sections: Array = song.data["sections"]
	sections.append(copy)
	order.insert(pos + 1, sections.size() - 1)
	_after_insert(song, loop, pos + 1)
	return sections.size() - 1


## Takes order position [param pos] out of the play order. The last entry
## stays. Sections and patterns nothing plays any more are dropped.
static func remove_at(song: ChipSong, pos: int) -> void:
	var order: Array = song.data["order"]
	if order.size() <= 1 or pos < 0 or pos >= order.size():
		return
	var loop := loop_positions(song)
	order.remove_at(pos)
	if pos < loop.x:
		loop.x -= 1
	if pos <= loop.y:
		loop.y -= 1
	compact(song)
	refresh_cues(song, loop.x, maxi(loop.y, loop.x))


## Moves order position [param pos] by [param delta] places. Returns where it
## ended up.
static func move(song: ChipSong, pos: int, delta: int) -> int:
	var order: Array = song.data["order"]
	if pos < 0 or pos >= order.size():
		return pos
	var to := clampi(pos + delta, 0, order.size() - 1)
	if to == pos:
		return pos
	var loop := loop_positions(song)
	var entry: Variant = order[pos]
	order.remove_at(pos)
	order.insert(to, entry)
	refresh_cues(song, loop.x, loop.y)
	return to


static func rename_section(song: ChipSong, section: int, section_name: String) -> void:
	section_name = section_name.strip_edges()
	if section_name == "" or section < 0 or section >= song.data["sections"].size():
		return
	song.data["sections"][section]["name"] = section_name
	var loop := loop_positions(song)
	refresh_cues(song, loop.x, loop.y)


## Makes a section [param bars] bars long. Notes past the new end are dropped
## or cut short; a pattern other sections share is copied first, so they
## keep theirs.
static func set_section_bars(song: ChipSong, section: int, bars: int) -> void:
	var info: Dictionary = song.data["sections"][section]
	var steps := clampi(bars, 1, MAX_BARS) * bar_steps(song)
	if steps == int(info["length"]):
		return
	var loop := loop_positions(song)
	var shrinking := steps < int(info["length"])
	info["length"] = steps
	if shrinking:
		var ids: Array = info["patterns"]
		for c in ids.size():
			if int(ids[c]) < 0:
				continue
			if PatternEdit.sharing(song, section, c) > 1:
				make_unique(song, section, c)
			var notes: Array = song.data["patterns"][int(ids[c])]["notes"]
			var kept: Array = []
			for n in notes:
				if int(n[0]) >= steps:
					continue
				n[1] = mini(int(n[1]), steps - int(n[0]))
				kept.append(n)
			notes.assign(kept)
	refresh_cues(song, loop.x, loop.y)


## Gives [param section] its own copy of the pattern it plays on
## [param channel], so changing it leaves other sections alone. Returns the
## pattern index.
static func make_unique(song: ChipSong, section: int, channel: int) -> int:
	var id := PatternEdit.pattern_id(song, section, channel)
	if id < 0 or PatternEdit.sharing(song, section, channel) <= 1:
		return id
	var patterns: Array = song.data["patterns"]
	patterns.append({"notes": (patterns[id]["notes"] as Array).duplicate(true)})
	song.data["sections"][section]["patterns"][channel] = patterns.size() - 1
	return patterns.size() - 1


## Drops sections the order no longer plays and patterns no section uses,
## and renumbers what is left.
static func compact(song: ChipSong) -> void:
	var sections: Array = song.data["sections"]
	var order: Array = song.data["order"]
	var section_map := {}
	var kept_sections: Array = []
	for i in sections.size():
		if order.has(i):
			section_map[i] = kept_sections.size()
			kept_sections.append(sections[i])
	for pos in order.size():
		order[pos] = section_map[int(order[pos])]
	var patterns: Array = song.data["patterns"]
	var pattern_map := {}
	var kept_patterns: Array = []
	for s in kept_sections:
		var ids: Array = s["patterns"]
		for c in ids.size():
			var id := int(ids[c])
			if id < 0:
				continue
			if not pattern_map.has(id):
				pattern_map[id] = kept_patterns.size()
				kept_patterns.append(patterns[id])
			ids[c] = pattern_map[id]
	song.data["sections"] = kept_sections
	song.data["patterns"] = kept_patterns


# Bars ------------------------------------------------------------------------

## The notes of one part between steps [param from] and [param to] of a
## section, with their steps made relative to [param from]. For drums pass
## the channels of both drum parts.
static func copy_steps(song: ChipSong, section: int, channels: Array, from: int, to: int) -> Array:
	var clip: Array = []
	for c in channels:
		for n in PatternEdit.notes_at(song, section, int(c)):
			var start := int(n[0])
			if start >= from and start < to:
				var copy: Array = n.duplicate(true)
				copy[0] = start - from
				copy[1] = mini(int(n[1]), to - start)
				clip.append([int(c), copy])
	return clip


## Removes the notes that start between [param from] and [param to].
static func clear_steps(song: ChipSong, section: int, channels: Array, from: int, to: int) -> void:
	for c in channels:
		var notes := PatternEdit.notes_at(song, section, int(c))
		var kept: Array = []
		for n in notes:
			if int(n[0]) < from or int(n[0]) >= to:
				kept.append(n)
		if kept.size() != notes.size():
			PatternEdit.set_notes(song, section, int(c), kept)


## Puts a clip from [method copy_steps] at step [param at], replacing what
## was in the steps it covers ([param span] steps long). Notes past the
## section's end are dropped.
static func paste_steps(song: ChipSong, section: int, clip: Array, at: int, span: int) -> void:
	var channels := {}
	for entry in clip:
		channels[int(entry[0])] = true
	clear_steps(song, section, channels.keys(), at, at + span)
	var steps := int(song.data["sections"][section]["length"])
	var by_channel := {}
	for entry in clip:
		var note: Array = (entry[1] as Array).duplicate(true)
		note[0] = int(note[0]) + at
		if int(note[0]) >= steps or int(note[0]) < 0:
			continue
		if not by_channel.has(entry[0]):
			by_channel[entry[0]] = PatternEdit.notes_at(song, section, int(entry[0]))
		by_channel[entry[0]].append(note)
	for c in by_channel:
		PatternEdit.set_notes(song, section, int(c), by_channel[c])


## Moves the pitched notes that start between [param from] and [param to] by
## [param semitones].
static func transpose_steps(song: ChipSong, section: int, channel: int, from: int, to: int, semitones: int) -> void:
	var notes := PatternEdit.notes_at(song, section, channel)
	for n in notes:
		if int(n[0]) >= from and int(n[0]) < to:
			n[2] = clampi(int(n[2]) + semitones, 0, 127)
	PatternEdit.set_notes(song, section, channel, notes)


## Snaps the starts (and lengths) of the notes between [param from] and
## [param to] to a grid of [param grid] steps.
static func quantize_steps(song: ChipSong, section: int, channel: int, from: int, to: int, grid: int) -> void:
	grid = maxi(grid, 1)
	var notes := PatternEdit.notes_at(song, section, channel)
	for n in notes:
		if int(n[0]) >= from and int(n[0]) < to:
			n[0] = int(roundf(float(n[0]) / grid)) * grid
			n[1] = maxi(int(roundf(float(n[1]) / grid)) * grid, grid)
	PatternEdit.set_notes(song, section, channel, notes)


# Song ------------------------------------------------------------------------

static func set_tempo(song: ChipSong, bpm: float) -> void:
	song.data["timing"]["bpm"] = clampf(snappedf(bpm, 1.0), 40.0, 300.0)


static func set_swing(song: ChipSong, swing: float) -> void:
	song.data["timing"]["swing"] = snappedf(clampf(swing, 0.0, 1.0), 0.01)


## A new song with the instruments, channels, timing, layers and states of
## [param from] and one silent section of [param bars] bars, for writing a
## song from scratch.
static func blank_song(from: ChipSong, bars := 4, title := "New song") -> ChipSong:
	var data: Dictionary = from.data.duplicate(true)
	data["patterns"] = []
	data["sections"] = []
	data["order"] = []
	data["cues"] = []
	data["meta"]["title"] = title
	data["meta"]["form"] = "custom"
	data["timing"]["loop"] = true
	var song := ChipSong.new()
	song.data = data
	add_section(song, 0, bars, "A")
	refresh_cues(song, 0, 0)
	return song


static func _after_insert(song: ChipSong, loop: Vector2i, pos: int) -> void:
	if song.data["order"].size() == 1:
		refresh_cues(song, 0, 0)
		return
	if pos <= loop.x:
		loop.x += 1
	if pos <= loop.y + 1:
		loop.y += 1
	refresh_cues(song, loop.x, loop.y)
