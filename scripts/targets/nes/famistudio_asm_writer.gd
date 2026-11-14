class_name FamiStudioAsmWriter
extends RefCounted
## Writes NES songs as music data for FamiStudio's sound engine, in ca65
## assembly: the same file FamiStudio's "FamiStudio Sound Engine (ca65)"
## export makes from the project [FamiStudioWriter] writes, so a game can use
## it without opening FamiStudio.
##
## This follows FamiStudio 4.5's exporter (FamitoneMusicFile.cs, MIT,
## https://github.com/BleuBleu/FamiStudio) for the features Chiptune Forge
## uses: 2A03 channels only, FamiStudio tempo, instruments with volume,
## arpeggio, pitch and duty envelopes, arpeggios and the volume column. It
## repeats the steps FamiStudio takes after loading the text project (notes
## to stops, grooves to frames, instrument merging and ordering, envelope
## packing, and the song data compression), so the output matches
## FamiStudio's byte for byte. CI checks that against FamiStudio itself.
##
## The data plays with famistudio_ca65.s from the same FamiStudio version
## (bundled in assets/nes/famistudio). Song data format changes between
## FamiStudio versions, so keep the two together.

const ENGINE_VERSION := "4.5.4"

const VOLUME := 0
const ARPEGGIO := 1
const PITCH := 2
const DUTY := 3

const OPCODE_EXTENDED_NOTE := 0x40
const OPCODE_SET_REFERENCE := 0x41
const OPCODE_LOOP := 0x42
const OPCODE_END_SONG := 0x44
const OPCODE_SET_TEMPO_ENV := 0x47
const OPCODE_RESET_TEMPO_ENV := 0x48
const OPCODE_OVERRIDE_ARP_ENV := 0x4b
const OPCODE_CLEAR_ARP_ENV_OVERRIDE := 0x4c
const OPCODE_RESET_ARP_ENV := 0x4d
const OPCODE_VOLUME_BITS := 0x70
const SINGLE_BYTE_NOTE_MIN := 12
const SINGLE_BYTE_NOTE_MAX := SINGLE_BYTE_NOTE_MIN + 0x3f
const MAX_REPEAT_COUNT := 63
const CHANNEL_COUNT := 5
const DPCM := 4

static var _crc_table := PackedInt64Array()

var _lines: PackedStringArray = []
var _project: Dictionary
var _env_names := {}
var _uses_volume_track := false
var _uses_arpeggio := false


## The music data for [param songs] (one or more [NesSong]) as one ca65
## file. [param project_name] names the data: music_data_<nice name>.
static func song_data(songs: Array, project_name: String) -> String:
	var writer := FamiStudioAsmWriter.new()
	return writer._save(songs, project_name)


## The label of the music data for [param project_name], as ca65 and C see
## it (C adds a leading underscore).
static func data_label(project_name: String) -> String:
	return "music_data_" + nice_name(project_name)


## FamiStudio's assembler-friendly name: letters and digits in lower case,
## spaces to underscores.
static func nice_name(name: String) -> String:
	var nice := ""
	for ch in name:
		var code := ch.unicode_at(0)
		if _is_letter_or_digit(ch):
			nice += ch.to_lower()
		elif (ch == " " or ch == "\t" or ch == "\n") and not nice.ends_with("_"):
			nice += "_"
		elif ch == "-":
			nice += "-"
		elif ch == "_":
			nice += ch
		elif code > 127 and ch.to_lower() != ch.to_upper():
			nice += ch.to_lower()
	return nice


static func _is_letter_or_digit(ch: String) -> bool:
	var code := ch.unicode_at(0)
	return (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)


func _save(songs: Array, project_name: String) -> String:
	_project = _load(songs, project_name)
	_cleanup()
	_remove_empty_arpeggios()
	_merge_identical_instruments()
	for song in _project["songs"]:
		_apply_grooves(song)
	_sort_instruments()
	_cleanup_envelopes()
	_output_header()
	_output_instruments()
	_lines.append("@samples:")
	_lines.append("")
	_output_tempo_envelopes()
	for i in _project["songs"].size():
		_process_and_output_song(i)
	var flags: PackedStringArray = ["; Required flags for %s:" % project_name]
	if _uses_volume_track:
		flags.append("; FAMISTUDIO_USE_VOLUME_TRACK = 1")
	if _uses_arpeggio:
		flags.append("; FAMISTUDIO_USE_ARPEGGIO = 1")
	var out: PackedStringArray = [_lines[0]]
	out.append_array(flags)
	out.append_array(_lines.slice(1))
	return "\n".join(out) + "\n"


## Required engine settings for the data, as "NAME = 1" lines.
func required_flags() -> PackedStringArray:
	var flags: PackedStringArray = []
	if _uses_volume_track:
		flags.append("FAMISTUDIO_USE_VOLUME_TRACK = 1")
	if _uses_arpeggio:
		flags.append("FAMISTUDIO_USE_ARPEGGIO = 1")
	return flags


# --- Loading: the project FamiStudio builds from FamiStudioWriter's text. ---

func _load(songs: Array, project_name: String) -> Dictionary:
	var instruments: Array = []
	var arpeggios: Array = []
	var inst_by_name := {}
	var arp_by_name := {}
	for nes: NesSong in songs:
		for inst: Dictionary in nes.instruments:
			var name := str(inst["name"])
			if inst_by_name.has(name):
				continue
			var envs: Array = [_default_env(VOLUME), _default_env(ARPEGGIO), _default_env(PITCH), _default_env(DUTY)]
			for pair in [[VOLUME, "volume"], [ARPEGGIO, "arp"], [PITCH, "pitch"], [DUTY, "duty"]]:
				var values: Array = inst.get(pair[1], [])
				if values.is_empty():
					continue
				envs[pair[0]] = _env_from(values, int(inst.get(pair[1] + "_loop", -1)), pair[0])
			inst_by_name[name] = instruments.size()
			instruments.append({"name": name, "envs": envs, "id": instruments.size()})
		for arp: Dictionary in nes.arpeggios:
			var name := str(arp["name"])
			if arp_by_name.has(name):
				continue
			arp_by_name[name] = arpeggios.size()
			arpeggios.append({"name": name, "env": _env_from(arp["values"], int(arp.get("loop", 0)), ARPEGGIO), "id": arpeggios.size()})
	var loaded_songs: Array = []
	for nes: NesSong in songs:
		loaded_songs.append(_load_song(nes, inst_by_name, arp_by_name))
	var project := {"name": project_name, "instruments": instruments, "arpeggios": arpeggios, "songs": loaded_songs}
	# FamiStudio keeps instruments and arpeggios sorted by name.
	_sort_by_name(instruments)
	_sort_by_name(arpeggios)
	for song in loaded_songs:
		_convert_to_simple_notes(song)
	return project


func _load_song(nes: NesSong, inst_by_name: Dictionary, arp_by_name: Dictionary) -> Dictionary:
	var layout := FamiStudioWriter.song_layout(nes)
	var chunks: Array = layout["chunks"]
	var note_length: int = layout["note_length"]
	var lengths: Array = []
	for chunk in chunks:
		lengths.append(int(chunk[1]) * note_length)
	var channels: Array = []
	for c in CHANNEL_COUNT:
		var patterns: Array = []
		var instances: Array = []
		instances.resize(chunks.size())
		instances.fill(-1)
		if c < 4:
			var channel: Dictionary = layout["channels"][c]
			var index_of := {}
			for name in channel["order"]:
				var notes := {}
				for n: Dictionary in channel["patterns"][name]:
					var note := {
						"value": clampi(int(n["note"]), NesSong.FIRST_NOTE, NesSong.LAST_NOTE),
						"duration": int(n["duration"]),
						"instrument": -1,
						"arp": -1,
						"volume": -1,
					}
					var inst := int(n["instrument"])
					if inst >= 0 and inst < nes.instruments.size():
						note["instrument"] = inst_by_name[str(nes.instruments[inst]["name"])]
					var arp := int(n.get("arp", -1))
					if arp >= 0 and arp < nes.arpeggios.size():
						note["arp"] = arp_by_name[str(nes.arpeggios[arp]["name"])]
					if c != NesSong.TRIANGLE:
						note["volume"] = clampi(int(n.get("volume", 15)), 0, 15)
					notes[int(n["time"])] = note
				index_of[name] = patterns.size()
				patterns.append(notes)
			var names: Array = channel["instances"]
			for i in names.size():
				if names[i] != "":
					instances[i] = index_of[names[i]]
		channels.append({"patterns": patterns, "instances": instances})
	return {
		"name": nes.title,
		"length": chunks.size(),
		"loop_point": layout["loop_point"],
		"groove": Array(nes.groove),
		"pattern_lengths": lengths,
		"channels": channels,
	}


static func _default_env(type: int) -> Dictionary:
	var length := 1 if type == VOLUME or type == DUTY else 8
	var value := 15 if type == VOLUME else 0
	var values: Array = []
	values.resize(length)
	values.fill(value)
	return {"values": values, "loop": -1, "release": -1, "relative": false, "type": type}


static func _env_from(values: Array, loop: int, type: int) -> Dictionary:
	var env := {"values": values.map(func(v: Variant) -> int: return int(v)), "loop": -1, "release": -1, "relative": false, "type": type}
	if loop >= 0:
		env["loop"] = mini(loop, values.size())
		if env["loop"] >= values.size():
			env["loop"] = -1
	return env


static func _sort_by_name(list: Array) -> void:
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _alpha_numeric_compare(a["name"], b["name"]) < 0)


## FamiStudio's AlphaNumericComparer: runs of digits compare as numbers.
static func _alpha_numeric_compare(s1: String, s2: String) -> int:
	var m1 := 0
	var m2 := 0
	while m1 < s1.length() and m2 < s2.length():
		var c1 := _chunk(s1, m1)
		var c2 := _chunk(s2, m2)
		m1 += c1.length()
		m2 += c2.length()
		var result := 0
		if c1[0].is_valid_int() and c2[0].is_valid_int():
			result = signi(c1.to_int() - c2.to_int())
		else:
			result = _culture_compare(c1, c2)
		if result != 0:
			return result
	return s1.length() - s2.length()


static func _chunk(s: String, start: int) -> String:
	var digit := s[start].is_valid_int()
	var end := start + 1
	while end < s.length() and s[end].is_valid_int() == digit:
		end += 1
	return s.substr(start, end - start)


# Invariant culture order for the names Chiptune Forge uses: letters ignore
# case first, then lower case comes first.
static func _culture_compare(a: String, b: String) -> int:
	var la := a.to_lower()
	var lb := b.to_lower()
	if la != lb:
		return -1 if la < lb else 1
	if a == b:
		return 0
	for i in a.length():
		if a[i] != b[i]:
			return -1 if a[i] == a[i].to_lower() else 1
	return 0


# --- The project clean-up FamiStudio's exporter does first. ---

func _cleanup() -> void:
	var used_inst := {}
	var used_arp := {}
	for song in _project["songs"]:
		for channel in song["channels"]:
			for p in song["length"]:
				var index: int = channel["instances"][p]
				if index < 0:
					continue
				for note: Dictionary in channel["patterns"][index].values():
					if note["instrument"] >= 0:
						used_inst[note["instrument"]] = true
					if note["arp"] >= 0:
						used_arp[note["arp"]] = true
	_remap("instrument", "instruments", func(i: int) -> bool: return used_inst.has(i))
	_remap("arp", "arpeggios", func(i: int) -> bool: return used_arp.has(i))


# Keeps the entries of _project[list_key] that [param keep] accepts (called
# with each entry's index into the original loading order) and updates the
# notes' [param note_key] to match. Notes refer to entries by "id", their
# index in loading order, so sorting the lists never breaks them.
func _remap(note_key: String, list_key: String, keep: Callable, replace := {}) -> void:
	var list: Array = _project[list_key]
	var kept: Array = []
	for entry in list:
		if keep.call(entry["id"]):
			kept.append(entry)
	_project[list_key] = kept
	for song in _project["songs"]:
		for channel in song["channels"]:
			for pattern: Dictionary in channel["patterns"]:
				for note: Dictionary in pattern.values():
					var id: int = note.get(note_key, -1)
					if replace.has(id):
						note[note_key] = replace[id]
					elif id >= 0 and not keep.call(id):
						note[note_key] = -1


func _remove_empty_arpeggios() -> void:
	var empty := {}
	for arp in _project["arpeggios"]:
		if _env_is_empty(arp["env"]):
			empty[arp["id"]] = true
	if not empty.is_empty():
		_remap("arp", "arpeggios", func(i: int) -> bool: return not empty.has(i))


func _merge_identical_instruments() -> void:
	var by_key := {}
	var replace := {}
	for inst in _project["instruments"]:
		var key := str(inst["envs"].map(func(e: Dictionary) -> Array: return [e["values"], e["loop"], e["release"], e["relative"]]))
		if by_key.has(key):
			replace[inst["id"]] = by_key[key]
		else:
			by_key[key] = inst["id"]
	if not replace.is_empty():
		_remap("instrument", "instruments", func(i: int) -> bool: return not replace.has(i), replace)


# Notes have durations in the editor; the engine wants explicit stop notes.
# FamiStudio adds a stop where a note ends before the next one starts. A stop
# that falls into the next pattern goes into that pattern, shared or not.
func _convert_to_simple_notes(song: Dictionary) -> void:
	var length: int = song["length"]
	var lengths: Array = song["pattern_lengths"]
	for channel in song["channels"]:
		var instances: Array = channel["instances"]
		var patterns: Array = channel["patterns"]
		# Every musical note in song order: [pattern index, time, note].
		var events: Array = []
		for p in length:
			if instances[p] < 0:
				continue
			var pattern: Dictionary = patterns[instances[p]]
			var times := pattern.keys()
			times.sort()
			for t in times:
				if t < lengths[p]:
					events.append([p, t, pattern[t]])
		var stops: Array = []
		var crossing := {}
		for i in events.size():
			var e: Array = events[i]
			var duration: int = e[2]["duration"]
			if i + 1 < events.size():
				duration = mini(duration, _distance(lengths, e[0], e[1], events[i + 1][0], events[i + 1][1]))
			var loc := _advance(lengths, e[0], e[1], duration)
			if loc[0] >= length:
				continue
			if loc[0] != e[0]:
				if instances[loc[0]] < 0:
					instances[loc[0]] = patterns.size()
					patterns.append({})
				crossing[loc[0]] = loc[1]
			stops.append(loc)
		# Patterns that get a stop from the pattern before are copied where
		# their instances need different stops.
		var visited := {}
		var copies := {}
		for p in length:
			if not crossing.has(p):
				continue
			var index: int = instances[p]
			var key := "%d:%d" % [index, crossing[p]]
			if not visited.has(index):
				visited[index] = true
				copies[key] = index
			elif copies.has(key):
				instances[p] = copies[key]
			else:
				var copy: Dictionary = {}
				for t in patterns[index]:
					copy[t] = patterns[index][t].duplicate()
				instances[p] = patterns.size()
				patterns.append(copy)
				copies[key] = instances[p]
		for loc in stops:
			var pattern: Dictionary = patterns[instances[loc[0]]]
			if not pattern.has(loc[1]):
				pattern[loc[1]] = {"value": 0, "duration": 1, "instrument": -1, "arp": -1, "volume": -1}


static func _distance(lengths: Array, p0: int, t0: int, p1: int, t1: int) -> int:
	var d := t1 - t0
	for p in range(p0, p1):
		d += lengths[p]
	return d


static func _advance(lengths: Array, p: int, t: int, count: int) -> Array:
	t += count
	while p < lengths.size() and t >= lengths[p]:
		t -= lengths[p]
		p += 1
	return [p, t]


# FamiStudio tempo: rows of a groove like 7-6 become whole frames, with the
# extra frame of the longer rows padded in the middle. After this one unit
# is one frame and the groove is 1.
func _apply_grooves(song: Dictionary) -> void:
	var groove: Array = song["groove"]
	var lengths: Array = song["pattern_lengths"]
	if groove.size() > 1:
		for channel in song["channels"]:
			var done := {}
			for p in song["length"]:
				var index: int = channel["instances"][p]
				if index < 0 or done.has(index):
					continue
				done[index] = true
				var max_len := 0
				for q in song["length"]:
					if channel["instances"][q] == index:
						max_len = maxi(max_len, lengths[q])
				var original: Dictionary = channel["patterns"][index]
				var moved := {}
				var it := GrooveIterator.new(groove)
				for i in max_len:
					if it.is_pad_frame():
						it.advance()
					if original.has(i):
						moved[it.frame_index] = original[i]
					it.advance()
				channel["patterns"][index] = moved
	for p in lengths.size():
		lengths[p] = frames_for_groove(lengths[p], groove)
	song["groove"] = [1]


static func frames_for_groove(length: int, groove: Array) -> int:
	var it := GrooveIterator.new(groove)
	for i in length:
		if it.is_pad_frame():
			it.advance()
		it.advance()
	if it.is_pad_frame():
		it.advance()
	return it.frame_index


# Most used instruments first, so the common ones get short codes. Matches
# .NET's List.Sort for small lists (insertion sort; special cases for 2 and 3).
func _sort_instruments() -> void:
	var changes: Array = []
	for song in _project["songs"]:
		for c in CHANNEL_COUNT:
			if c == DPCM:
				continue
			var channel: Dictionary = song["channels"][c]
			var prev := -1
			for p in song["length"]:
				var index: int = channel["instances"][p]
				if index < 0:
					continue
				var pattern: Dictionary = channel["patterns"][index]
				var times := pattern.keys()
				times.sort()
				for t in times:
					if t >= song["pattern_lengths"][p]:
						continue
					var note: Dictionary = pattern[t]
					if note["value"] == 0 or note["instrument"] < 0 or note["instrument"] == prev:
						continue
					var found := false
					for entry in changes:
						if entry[0] == note["instrument"]:
							entry[1] += 1
							found = true
					if not found:
						changes.append([note["instrument"], 1])
					prev = note["instrument"]
	_dotnet_sort(changes, func(a: Array, b: Array) -> int: return signi(b[1] - a[1]))
	var by_id := {}
	for inst in _project["instruments"]:
		by_id[inst["id"]] = inst
	var ordered: Array = _project["instruments"].duplicate()
	for i in range(changes.size() - 1, -1, -1):
		var inst: Dictionary = by_id[changes[i][0]]
		ordered.erase(inst)
		ordered.insert(0, inst)
	_project["instruments"] = ordered


static func _dotnet_sort(a: Array, compare: Callable) -> void:
	var swap_if_greater := func(i: int, j: int) -> void:
		if compare.call(a[i], a[j]) > 0:
			var t: Variant = a[i]
			a[i] = a[j]
			a[j] = t
	if a.size() < 2:
		return
	if a.size() == 2:
		swap_if_greater.call(0, 1)
		return
	if a.size() == 3:
		swap_if_greater.call(0, 1)
		swap_if_greater.call(0, 2)
		swap_if_greater.call(1, 2)
		return
	for i in a.size() - 1:
		var t: Variant = a[i + 1]
		var j := i
		while j >= 0 and compare.call(t, a[j]) < 0:
			a[j + 1] = a[j]
			j -= 1
		a[j + 1] = t


func _cleanup_envelopes() -> void:
	for inst in _project["instruments"]:
		var env: Dictionary = inst["envs"][VOLUME]
		var all_max := true
		for v in env["values"]:
			if v != 15:
				all_max = false
		if env["values"].is_empty() or all_max:
			env["values"] = [15]
			env["loop"] = -1
			env["release"] = -1


# --- Output. ---

func _output_header() -> void:
	var name := nice_name(_project["name"])
	_lines.append("; This file is for the FamiStudio Sound Engine and was generated by FamiStudio")
	_lines.append("")
	_lines.append(".export _music_data_%s:=music_data_%s" % [name, name])
	_lines.append("")
	_lines.append("music_data_%s:" % name)
	_lines.append("\t.byte %d" % _project["songs"].size())
	_lines.append("\t.word @instruments")
	_lines.append("\t.word @samples-4")
	for i in _project["songs"].size():
		var song: Dictionary = _project["songs"][i]
		_lines.append("; %02x : %s" % [i, song["name"]])
		for c in CHANNEL_COUNT:
			_lines.append("\t.word @song%dch%d" % [i, c])
		var groove := _groove_name(song["groove"])
		_lines.append("\t.byte .lobyte(@tempo_env_%s), .hibyte(@tempo_env_%s), 0, 0" % [groove, groove])
	_lines.append("")
	_lines.append(".export music_data_%s" % name)
	_lines.append(".global FAMISTUDIO_DPCM_PTR")
	_lines.append("")


static func _groove_name(groove: Array) -> String:
	return "_".join(PackedStringArray(groove.map(func(v: int) -> String: return str(v)))) + "_mid"


func _output_instruments() -> void:
	var default_env := PackedByteArray([0xc0, 0x7f, 0x00, 0x01])
	var default_duty_env := PackedByteArray([0x7f, 0x00, 0x00])
	var default_pitch_env := PackedByteArray([0x00, 0xc0, 0x7f, 0x00, 0x02])
	var unique := {}
	unique[crc32(default_env)] = default_env
	unique[crc32(default_pitch_env)] = default_pitch_env
	unique[crc32(default_duty_env)] = default_duty_env
	var inst_crcs: Array = []
	for inst in _project["instruments"]:
		var crcs: Array = [0, 0, 0, 0]
		for type in 4:
			var processed: Variant = _process_envelope(inst["envs"][type], type == VOLUME, type == PITCH)
			if processed == null:
				if type == PITCH or type == VOLUME:
					crcs[type] = crc32(default_pitch_env)
				elif type == DUTY:
					crcs[type] = crc32(default_duty_env)
				else:
					crcs[type] = crc32(default_env)
			else:
				crcs[type] = crc32(processed)
				unique[crcs[type]] = processed
		inst_crcs.append(crcs)
	var arp_crcs := {}
	for arp in _project["arpeggios"]:
		var processed: Variant = _process_envelope(arp["env"], false, false)
		arp_crcs[arp["id"]] = crc32(processed)
		unique[arp_crcs[arp["id"]]] = processed
	var keys := unique.keys()
	keys.sort()
	var index_of := {}
	for i in keys.size():
		index_of[keys[i]] = i
	_lines.append("@instruments:")
	for i in _project["instruments"].size():
		var inst: Dictionary = _project["instruments"][i]
		var crcs: Array = inst_crcs[i]
		_lines.append("\t.word @env%d,@env%d,@env%d,@env%d ; %02x : %s" % [index_of[crcs[VOLUME]], index_of[crcs[ARPEGGIO]], index_of[crcs[DUTY]], index_of[crcs[PITCH]], i, inst["name"]])
		inst["index"] = i
		_env_names["inst_arp:%d" % inst["id"]] = "@env%d" % index_of[crcs[ARPEGGIO]]
	_lines.append("")
	for i in keys.size():
		var bytes: PackedByteArray = unique[keys[i]]
		_lines.append("@env%d:" % i)
		_lines.append("\t.byte " + ",".join(PackedStringArray(Array(bytes).map(func(b: int) -> String: return "$%02x" % b))))
	_lines.append("")
	_env_names["none"] = "@env%d" % index_of[crc32(default_env)]
	for id in arp_crcs:
		_env_names["arp:%d" % id] = "@env%d" % index_of[arp_crcs[id]]


func _output_tempo_envelopes() -> void:
	var seen := {}
	for song in _project["songs"]:
		var name := _groove_name(song["groove"])
		if seen.has(name):
			continue
		seen[name] = true
		var env := tempo_envelope(song["groove"])
		_lines.append("@tempo_env_%s:" % name)
		_lines.append("\t.byte " + ",".join(PackedStringArray(Array(env).map(func(b: int) -> String: return "$%02x" % b))))
	_lines.append("")


func _process_and_output_song(song_index: int) -> void:
	var data := _song_data(_project["songs"][song_index], song_index)
	var best_size := 1 << 30
	var best_min := 0
	for i in range(8, 41):
		var size := _compress_and_output(data, song_index, i, false)
		if size <= best_size:
			best_size = size
			best_min = i
	_compress_and_output(data, song_index, best_min, true)


func _song_data(song: Dictionary, song_index: int) -> Array:
	var all_channels: Array = []
	var loop_point: int = song["loop_point"]
	for c in CHANNEL_COUNT:
		var channel: Dictionary = song["channels"][c]
		var instrument := -1
		var arpeggio := -1
		var last_volume := 15
		var first_in_loop := -1
		var last_in_loop := -1
		var previous_groove: Array = song["groove"]
		var data: Array = ["@song%dch%d:" % [song_index, c]]
		all_channels.append(data)
		var uses_arpeggios := false
		for pattern: Dictionary in channel["patterns"]:
			for note: Dictionary in pattern.values():
				if note["arp"] >= 0:
					uses_arpeggios = true
		if loop_point >= 0:
			for p in range(loop_point, song["length"]):
				var index: int = channel["instances"][p]
				if index < 0:
					continue
				var pattern: Dictionary = channel["patterns"][index]
				var times := pattern.keys()
				times.sort()
				for t in times:
					var note: Dictionary = pattern[t]
					if note["value"] != 0 and note["instrument"] >= 0:
						if first_in_loop < 0:
							first_in_loop = note["instrument"]
						last_in_loop = note["instrument"]
		for p in song["length"]:
			var index: int = channel["instances"][p]
			var pattern: Dictionary = {} if index < 0 else channel["patterns"][index]
			if p == loop_point:
				data.append("@song%dch%dloop:" % [song_index, c])
				if last_in_loop != first_in_loop:
					instrument = -1
				last_volume = -1
				if uses_arpeggios:
					data.append("$%02x+" % OPCODE_CLEAR_ARP_ENV_OVERRIDE)
			if c == 0:
				var groove: Array = song["groove"]
				if groove != previous_groove or p == loop_point:
					var name := _groove_name(groove)
					data.append("$%02x+" % OPCODE_SET_TEMPO_ENV)
					data.append(".lobyte(@tempo_env_%s)" % name)
					data.append(".hibyte(@tempo_env_%s)" % name)
					previous_groove = groove
				elif p != 0:
					data.append("$%02x+" % OPCODE_RESET_TEMPO_ENV)
			var pattern_length: int = song["pattern_lengths"][p]
			var time := 0
			while time < pattern_length:
				var note: Variant = pattern.get(time)
				time += 1
				if note != null and note["volume"] >= 0:
					if note["volume"] != last_volume:
						data.append("$%02x+" % (OPCODE_VOLUME_BITS | note["volume"]))
						last_volume = note["volume"]
					_uses_volume_track = true
				var musical: bool = note != null and note["value"] != 0
				if musical:
					if note["arp"] != arpeggio:
						data.append("$%02x+" % OPCODE_OVERRIDE_ARP_ENV)
						var env_name: String
						if note["arp"] < 0:
							env_name = _env_names["none"] if instrument < 0 else _env_names["inst_arp:%d" % instrument]
						else:
							env_name = _env_names["arp:%d" % note["arp"]]
						data.append(".lobyte(%s)" % env_name)
						data.append(".hibyte(%s)" % env_name)
						if note["arp"] < 0:
							data.append("$%02x+" % OPCODE_CLEAR_ARP_ENV_OVERRIDE)
						arpeggio = note["arp"]
						_uses_arpeggio = true
					elif arpeggio >= 0:
						data.append("$%02x+" % OPCODE_RESET_ARP_ENV)
				if note != null:
					if musical and note["instrument"] >= 0 and c != DPCM and note["instrument"] != instrument:
						var inst_index := _instrument_index(note["instrument"])
						data.append("$%02x+" % ((0x80 | (inst_index << 1)) & 0xff))
						instrument = note["instrument"]
					var value: int = note["value"]
					if musical and (value <= SINGLE_BYTE_NOTE_MIN or value > SINGLE_BYTE_NOTE_MAX):
						data.append("$%02x+" % OPCODE_EXTENDED_NOTE)
						data.append("$%02x*" % clampi(value, 1, 96))
					else:
						data.append("$%02x+*" % ((clampi(value, 1, 96) - SINGLE_BYTE_NOTE_MIN) if musical else 0))
				else:
					var empty := 0
					while time < pattern_length:
						var next: Variant = pattern.get(time)
						if empty >= MAX_REPEAT_COUNT or (next != null and (next["value"] >= 0 or next["volume"] >= 0)):
							break
						empty += 1
						time += 1
					data.append("$%02x+*" % ((0x81 | (empty << 1)) & 0xff))
		if loop_point < 0:
			data.append("$%02x+" % OPCODE_END_SONG)
			data.append("$00*")
		else:
			data.append("$%02x+" % OPCODE_LOOP)
			data.append("@song%dch%dloop" % [song_index, c])
	# Channels whose data is the same share it. (FamiStudio compares each
	# channel with the first channels by position, as here.)
	var regex := RegEx.create_from_string("ch\\d+")
	var joined: Array = []
	for data in all_channels:
		joined.append(regex.sub("\n".join(PackedStringArray(data)), "ch", true))
	var unique: Array = [all_channels[0]]
	for i in range(1, all_channels.size()):
		var is_unique := true
		for j in unique.size():
			if joined[i] == joined[j]:
				unique[j].insert(0, "@song%dch%d:" % [song_index, i])
				is_unique = false
				break
		if is_unique:
			unique.append(all_channels[i])
	var out: Array = []
	for data in unique:
		out.append_array(data)
	return out


func _instrument_index(id: int) -> int:
	for inst in _project["instruments"]:
		if inst["id"] == id:
			return inst["index"]
	return 0


static func _is_label_or_ref(s: String) -> bool:
	return s.begins_with("@")


static func _is_label(s: String) -> bool:
	return s.ends_with(":")


static func _is_ref(s: String) -> bool:
	return s.begins_with("@") and not s.ends_with(":")


static func _is_note(s: String) -> bool:
	return s.ends_with("*")


static func _is_opcode(s: String) -> bool:
	return s.ends_with("+") or (s.length() >= 2 and s[s.length() - 2] == "+")


static func _clean(s: String) -> String:
	while s.ends_with("*") or s.ends_with("+"):
		s = s.left(s.length() - 1)
	return s


# Replaces repeated runs of notes with jumps to their first copy
# (FamiStudio's CompressAndOutputSongData). Returns the size in bytes.
func _compress_and_output(data: Array, song_index: int, min_notes: int, write: bool) -> int:
	const HASH_BYTES := 4
	var refs := {}
	var jumps := {}
	var hashes := {}
	var compressed: Array = []
	var i := 0
	while i < data.size():
		var crc := 0
		var compressible := _is_opcode(data[i])
		if compressible:
			for k in range(i, mini(data.size(), i + HASH_BYTES)):
				if _is_label_or_ref(data[k]):
					compressible = false
					break
				crc = crc32(data[k].to_ascii_buffer(), crc)
			if compressible and hashes.has(crc):
				var best_index := -1
				var best_len := -1
				var best_notes := -1
				for idx: int in hashes[crc]:
					var last_note := -1
					var notes := 0
					var j := idx
					var k := i
					while j < compressed.size() and k < data.size() and notes < 250:
						if compressed[j] != data[k] or _is_label_or_ref(compressed[j]):
							break
						if _is_note(compressed[j]):
							notes += 1
							last_note = j
						j += 1
						k += 1
					if notes >= min_notes:
						var match_len := last_note - idx + 1
						if match_len > best_len:
							best_index = idx
							best_len = match_len
							best_notes = notes
				if best_index > 0:
					refs[best_index] = true
					jumps[compressed.size()] = true
					compressed.append("$%02x" % OPCODE_SET_REFERENCE)
					compressed.append("$%02x" % best_notes)
					compressed.append("@song%dref%d" % [song_index, best_index])
					i += best_len
					continue
		compressed.append(data[i])
		i += 1
		if compressed.size() >= HASH_BYTES:
			crc = 0
			var start := compressed.size() - HASH_BYTES
			for j in range(start, compressed.size()):
				crc = crc32(compressed[j].to_ascii_buffer(), crc)
			if not hashes.has(crc):
				hashes[crc] = []
			hashes[crc].append(start)
	var size := 0
	var bytes := ""
	for n in compressed.size():
		var b := _clean(compressed[n])
		var is_ref := refs.has(n)
		var is_label := _is_label(b)
		var is_jump := jumps.has(n)
		var is_jump_label := _is_ref(b)
		if bytes != "" and (is_jump_label or is_label or is_ref or is_jump or bytes.length() > 120):
			if write:
				_lines.append(bytes)
			bytes = ""
		if is_ref and write:
			_lines.append("@song%dref%d:" % [song_index, n])
		if is_label:
			if write:
				_lines.append(b)
		elif is_jump_label:
			if write:
				_lines.append("\t.word " + b)
			size += 2
		else:
			bytes = ("\t.byte " + b) if bytes == "" else (bytes + ", " + b)
			size += 1
	if write and bytes != "":
		_lines.append(bytes)
	return size


# --- Envelopes. ---

static func _env_is_empty(env: Dictionary) -> bool:
	var values: Array = env["values"]
	if values.is_empty():
		return true
	# FamiStudio checks against 0 for every type here (volume included).
	for v in values:
		if v != 0:
			return false
	return true


static func _optimize(env: Dictionary) -> void:
	var values: Array = env["values"]
	if values.is_empty() or env["relative"]:
		return
	var all_same := true
	for v in values:
		if v != values[0]:
			all_same = false
	if all_same:
		env["loop"] = -1
		env["release"] = -1
		env["values"] = [values[0]]
		return
	if env["loop"] >= 0:
		return
	var i := values.size() - 2
	while i >= 0 and i > env["release"]:
		if values[i] != values[i + 1]:
			break
		i -= 1
	_set_length(env, i + 2)


static func _set_length(env: Dictionary, length: int) -> void:
	env["values"] = env["values"].slice(0, length)
	if env["loop"] >= length:
		env["loop"] = -1
	if env["release"] >= length:
		env["release"] = -1


## FamiStudio's envelope packing (ProcessEnvelope): values offset by 192,
## runs of equal values as a count, then 0 and the loop position.
static func _process_envelope(env: Dictionary, allow_releases: bool, new_pitch: bool) -> Variant:
	if _env_is_empty(env):
		return null
	_optimize(env)
	var values: Array = env["values"]
	var length := values.size()
	var loop: int = env["loop"]
	var release: int = env["release"]
	var relative: bool = env["relative"]
	if length == 1 and not relative and release < 0:
		var v := (192 + int(values[0])) & 0xff
		if new_pitch or allow_releases:
			return PackedByteArray([0x00, v, 0x7f, 0x00, 0x02])
		return PackedByteArray([v, 0x7f, 0x00, 0x00])
	var data := PackedByteArray()
	if allow_releases or new_pitch:
		data.append(0)
	if new_pitch:
		data[0] = 0x80 if relative else 0x00
	var ptr_loop := 0xff
	var rel_count := 0
	var prev := (int(values[0]) + 1) & 0xff
	var found_release := false
	var allow_rle := not relative
	for j in length:
		var val := (clampi(int(values[j]), -64, 63) + 192) & 0xff
		if prev != val or not allow_rle or j == loop or (allow_releases and j == release) or j == length - 1 or (rel_count == 127 and new_pitch):
			if rel_count != 0:
				if rel_count == 1:
					data.append(prev)
				else:
					while rel_count > 127:
						data.append(127)
						rel_count -= 127
					data.append(rel_count)
				rel_count = 0
			if j == loop:
				ptr_loop = data.size()
			if j == release and allow_releases:
				found_release = true
				data.append(0)
				data.append(ptr_loop)
				data[0] = data.size()
			data.append(val)
			prev = val
		else:
			rel_count += 1
	if ptr_loop == 0xff or found_release:
		if new_pitch and relative and data[data.size() - 1] != 192:
			data.append(192)
		ptr_loop = data.size() - 1
	data.append(0)
	data.append(ptr_loop & 0xff)
	return data


## FamiStudio's tempo envelope for a groove (FamiStudioTempoUtils.
## GetTempoEnvelope, NTSC source): which frames to skip on PAL.
static func tempo_envelope(groove: Array, pal_source := false) -> PackedByteArray:
	var dst_factor := 6 if pal_source else 5
	var src_factor := 5 if pal_source else 6
	var note_length: int = groove.min()
	var groove_sum := 0
	for g in groove:
		groove_sum += g
	var frames := groove_sum
	var repeat := 1
	while frames % src_factor != 0:
		frames += groove_sum
		repeat += 1
	var adapted := frames / src_factor * dst_factor
	var important: Array = []
	important.resize(frames)
	important.fill(false)
	var frame := 0
	for r in repeat:
		for g in groove:
			if g == note_length:
				important[frame] = true
				important[frame + note_length - 1] = true
			else:
				# Middle padding.
				important[frame] = true
				important[frame + note_length] = true
			frame += g
	var skips := adapted - frames if pal_source else frames - adapted
	var skip: Array = []
	skip.resize(frames)
	skip.fill(false)
	frame = src_factor / 2
	for i in skips:
		skip[frame] = true
		frame += src_factor
	var cost := func(idx: int) -> int:
		if not skip[idx]:
			return 0
		var c := 0
		if important[idx]:
			c += src_factor
		for i in range(1, src_factor):
			var next := idx + i
			if next >= skip.size():
				next -= skip.size()
			if skip[next]:
				c += src_factor - i
				break
		for i in range(1, src_factor):
			var prev := idx - i
			if prev < 0:
				prev += skip.size()
			if skip[prev]:
				c += src_factor - i
				break
		return c
	for attempt in 100:
		var max_cost := -10
		var max_index := -1
		for j in frames:
			var c: int = cost.call(j)
			if c > max_cost:
				max_cost = c
				max_index = j
		if max_cost == 0:
			break
		var current: int = cost.call(max_index)
		if max_index > 0 and not skip[max_index - 1] and not important[max_index - 1]:
			skip[max_index] = false
			skip[max_index - 1] = true
			if cost.call(max_index - 1) < current:
				continue
			skip[max_index] = true
			skip[max_index - 1] = false
		if max_index < frames - 1 and not skip[max_index + 1] and not important[max_index + 1]:
			skip[max_index] = false
			skip[max_index + 1] = true
			if cost.call(max_index + 1) < current:
				continue
			skip[max_index] = true
			skip[max_index + 1] = false
		break
	var env := PackedByteArray()
	var last := -1
	var first := -1
	var total := 0
	for i in frames:
		if skip[i]:
			var delta := i - last
			env.append((delta + (1 if pal_source else -1)) & 0xff)
			total += delta
			last = i
			if first < 0:
				first = i
	if pal_source:
		env[0] -= 1
	var remaining := frames - total
	if remaining != 0:
		env.append((remaining + first + 1 + (1 if pal_source else -1)) & 0xff)
	env.append(0x80)
	return env


## CRC-32 (IEEE), continuing from [param initial] as FamiStudio's does.
static func crc32(data: PackedByteArray, initial := 0) -> int:
	if _crc_table.is_empty():
		_crc_table.resize(256)
		for i in 256:
			var c := i
			for j in 8:
				c = (0xEDB88320 ^ (c >> 1)) if (c & 1) != 0 else (c >> 1)
			_crc_table[i] = c
	var c := (initial ^ 0xFFFFFFFF) & 0xFFFFFFFF
	for b in data:
		c = _crc_table[(c ^ b) & 0xff] ^ (c >> 8)
	return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF


class GrooveIterator:
	var groove: Array
	var note_length: int
	var groove_frame := 0
	var groove_index := 0
	var frame_index := 0

	func _init(g: Array) -> void:
		groove = g
		note_length = g.min()

	func advance() -> void:
		frame_index += 1
		groove_frame += 1
		if groove_frame == groove[groove_index]:
			groove_frame = 0
			groove_index += 1
			if groove_index == groove.size():
				groove_index = 0

	# Middle padding.
	func is_pad_frame() -> bool:
		return groove[groove_index] != note_length and groove_frame == note_length / 2


# --- Sound effects. ---

## Sound effects for FamiStudio's engine (famistudio_sfx_init and
## famistudio_sfx_play), in the format of FamiStudio's sound effect export:
## per sound, the 2A03 register changes frame by frame, recorded from
## [NesPlayer]. NTSC timing; the PAL table points at the same data.
static func sfx_data(sounds: Array) -> String:
	const REGISTER_MAP := [0x80, 0, 0x81, 0x82, 0x83, 0, 0x84, 0x85, 0x86, 0, 0x87, 0x88, 0x89, 0, 0x8a]
	var lines: PackedStringArray = [
		"; This file is for the FamiStudio Sound Engine and was generated by Chiptune Forge",
		"",
		".export _sounds=sounds",
		"",
		"sounds:",
		"\t.word @ntsc",
		"\t.word @ntsc",
		"@ntsc:",
	]
	for sfx: NesSfx in sounds:
		lines.append("\t.word @sfx_ntsc_" + nice_name(sfx.name))
	lines.append("")
	for sfx: NesSfx in sounds:
		var writes := record_writes(sfx.to_song())
		var regs: Array = []
		regs.resize(32)
		regs.fill(-1)
		regs[0x00] = 0x30
		regs[0x04] = 0x30
		regs[0x08] = 0x80
		regs[0x0c] = 0x30
		var volume := [0, 0, 0, 0]
		var all_zero := true
		var last_zero := -1
		var last_change := 0
		var effect := PackedByteArray()
		for w in writes:
			var reg: int = w[1] - 0x4000
			if reg < 0 or reg >= REGISTER_MAP.size() or REGISTER_MAP[reg] == 0 or regs[reg] == w[2]:
				continue
			if w[0] != last_change:
				var empty: int = w[0] - last_change
				while empty >= 0:
					effect.append(mini(empty, 127))
					empty -= 127
			match reg:
				0x00: volume[0] = w[2] & 0x0f
				0x04: volume[1] = w[2] & 0x0f
				0x08: volume[2] = w[2] & 0x7f
				0x0c: volume[3] = w[2] & 0x0f
			var silent: bool = volume[0] == 0 and volume[1] == 0 and volume[2] == 0 and volume[3] == 0
			if not all_zero and silent:
				all_zero = true
				last_zero = effect.size()
			elif all_zero and not silent:
				all_zero = false
			effect.append(REGISTER_MAP[reg])
			effect.append(w[2])
			regs[reg] = w[2]
			last_change = w[0]
		if not all_zero and not writes.is_empty():
			var empty: int = writes[writes.size() - 1][0] - last_change
			while empty > 0:
				effect.append(mini(empty, 127))
				empty -= 127
		elif last_zero >= 0:
			effect = effect.slice(0, last_zero)
		effect.append(0)
		lines.append("@sfx_ntsc_%s:" % nice_name(sfx.name))
		for i in range(0, effect.size(), 16):
			var chunk := effect.slice(i, mini(i + 16, effect.size()))
			lines.append("\t.byte " + ",".join(PackedStringArray(Array(chunk).map(func(b: int) -> String: return "$%02x" % b))))
	lines.append("")
	lines.append(".export sounds")
	return "\n".join(lines) + "\n"


## Every register write [NesPlayer] makes playing [param song] once:
## [frame, address, value].
static func record_writes(song: NesSong) -> Array:
	var rec := _Recorder.new()
	var player := NesPlayer.new(song, rec)
	var total := song.frames_before(song.row_count)
	rec.writes.clear()
	for f in total:
		rec.frame = f
		player.tick()
	return rec.writes


class _Recorder:
	var frame := 0
	var writes: Array = []

	func reset() -> void:
		pass

	func write(address: int, value: int) -> void:
		writes.append([frame, address, value & 0xff])


# --- Example projects. ---

const ENGINE_DIR := "res://assets/nes/famistudio"
const ENGINE_FILES: PackedStringArray = ["famistudio_ca65.s", "famistudio_cc65.h", "LICENSE.txt"]


## A ca65 project that plays [param nes]: the music data, FamiStudio's
## engine, an example main.s, the linker config and a Makefile. Paths are
## relative to the project folder.
static func song_project(nes: NesSong, prefix: String, credit: String) -> Dictionary:
	var name := ExportJob.sanitize(prefix)
	var writer := FamiStudioAsmWriter.new()
	var data := writer._save([nes], nes.title)
	var files := {}
	files["%s.s" % name] = ("; %s\n" % credit if credit != "" else "").to_utf8_buffer() + data.to_utf8_buffer()
	files["main.s"] = _main_s(nes.title, name, data_label(nes.title), "", writer.required_flags()).to_utf8_buffer()
	_add_common(files, name)
	files["README.txt"] = _readme(name, data_label(nes.title), false).to_utf8_buffer()
	return files


## A ca65 project for a sound kit: the sounds for famistudio_sfx_play and an
## example that plays each one in turn.
static func sfx_project(sounds: Array, prefix: String) -> Dictionary:
	var name := ExportJob.sanitize(prefix)
	var silence := NesSong.new()
	silence.title = "silence"
	silence.row_count = 1
	silence.looping = false
	var files := {}
	files["%s.s" % name] = sfx_data(sounds).to_utf8_buffer()
	files["silence.s"] = song_data([silence], "silence").to_utf8_buffer()
	files["main.s"] = _main_s(prefix, "silence", data_label("silence"), name, PackedStringArray(), sounds.size()).to_utf8_buffer()
	_add_common(files, name)
	files["README.txt"] = _readme(name, "sounds", true, sounds).to_utf8_buffer()
	return files


static func _add_common(files: Dictionary, name: String) -> void:
	files["nes.cfg"] = NES_CFG.to_utf8_buffer()
	files["Makefile"] = MAKEFILE.replace("{name}", name).to_utf8_buffer()
	for file in ENGINE_FILES:
		var bytes := FileAccess.get_file_as_bytes(ENGINE_DIR.path_join(file))
		if not bytes.is_empty():
			files[file] = bytes


static func _main_s(title: String, music_file: String, music_label: String, sfx_file: String, flags: PackedStringArray, sfx_count := 0) -> String:
	var lines: PackedStringArray = [
		"; %s: plays %s with FamiStudio's sound engine." % [title, "the sounds one after another" if sfx_file != "" else "the song"],
		"; Made with Chiptune Forge. Build with cc65 (make), run the .nes in any emulator.",
		"",
		".segment \"HEADER\"",
		"    .byte \"NES\", $1a",
		"    .byte 2            ; 32 KB of PRG ROM (NROM-256)",
		"    .byte 0            ; CHR RAM",
		"    .byte $01, $00     ; mapper 0, vertical mirroring",
		"    .byte 0, 0, 0, 0, 0, 0, 0, 0",
		"",
		".segment \"ZEROPAGE\"",
	]
	if sfx_file != "":
		lines.append_array(["sfx_timer: .res 1", "sfx_next:  .res 1"])
	lines.append_array([
		"",
		".segment \"CODE\"",
		"",
		"; Engine settings. The music needs the features its data file lists.",
		"FAMISTUDIO_CFG_EXTERNAL     = 1",
		"FAMISTUDIO_CFG_NTSC_SUPPORT = 1",
	])
	if sfx_file != "":
		lines.append_array(["FAMISTUDIO_CFG_SFX_SUPPORT  = 1", "FAMISTUDIO_CFG_SFX_STREAMS = 1"])
	for flag in flags:
		lines.append(flag)
	lines.append_array([
		".define FAMISTUDIO_CA65_ZP_SEGMENT   ZEROPAGE",
		".define FAMISTUDIO_CA65_RAM_SEGMENT  BSS",
		".define FAMISTUDIO_CA65_CODE_SEGMENT CODE",
		".include \"famistudio_ca65.s\"",
		"",
		"reset:",
		"    sei",
		"    cld",
		"    ldx #$40",
		"    stx $4017          ; no APU frame IRQ",
		"    ldx #$ff",
		"    txs",
		"    inx",
		"    stx $2000          ; no NMI yet",
		"    stx $2001          ; screen off",
		"    stx $4010          ; no DMC IRQ",
		"    bit $2002",
		"@wait1:",
		"    bit $2002",
		"    bpl @wait1",
		"    txa",
		"@clear:",
		"    sta $0000,x",
		"    sta $0100,x",
		"    sta $0300,x",
		"    sta $0400,x",
		"    sta $0500,x",
		"    sta $0600,x",
		"    sta $0700,x",
		"    inx",
		"    bne @clear",
		"@wait2:",
		"    bit $2002",
		"    bpl @wait2",
		"",
		"    ldx #<%s" % music_label,
		"    ldy #>%s" % music_label,
		"    lda #1             ; NTSC",
		"    jsr famistudio_init",
	])
	if sfx_file != "":
		lines.append_array([
			"    ldx #<sounds",
			"    ldy #>sounds",
			"    jsr famistudio_sfx_init",
			"    lda #30",
			"    sta sfx_timer",
		])
	else:
		lines.append_array([
			"    lda #0             ; first song in the data",
			"    jsr famistudio_music_play",
		])
	lines.append_array([
		"    lda #$80",
		"    sta $2000          ; NMI on: the engine runs once per frame",
		"forever:",
		"    jmp forever",
		"",
		"nmi:",
		"    pha",
		"    txa",
		"    pha",
		"    tya",
		"    pha",
	])
	if sfx_file != "":
		lines.append_array([
			"    dec sfx_timer",
			"    bne @play",
			"    lda #75            ; next sound in 1.25 s",
			"    sta sfx_timer",
			"    lda sfx_next",
			"    ldx #FAMISTUDIO_SFX_CH0",
			"    jsr famistudio_sfx_play",
			"    inc sfx_next",
			"    lda sfx_next",
			"    cmp #%d" % sfx_count,
			"    bne @play",
			"    lda #0",
			"    sta sfx_next",
			"@play:",
		])
	lines.append_array([
		"    jsr famistudio_update",
		"    pla",
		"    tay",
		"    pla",
		"    tax",
		"    pla",
		"irq:",
		"    rti",
		"",
		".segment \"RODATA\"",
		".include \"%s.s\"" % music_file,
	])
	if sfx_file != "":
		lines.append(".include \"%s.s\"" % sfx_file)
	lines.append_array([
		"",
		".segment \"VECTORS\"",
		"    .word nmi, reset, irq",
	])
	return "\n".join(lines) + "\n"


const NES_CFG := """# NROM-256: 32 KB of PRG ROM, CHR RAM.
MEMORY {
    HEADER:  start = $0000, size = $0010, type = ro, file = %O, fill = yes;
    ZP:      start = $0000, size = $0100, type = rw, file = "";
    RAM:     start = $0300, size = $0500, type = rw, file = "";
    PRG:     start = $8000, size = $7ffa, type = ro, file = %O, fill = yes, fillval = $ff;
    VECTORS: start = $fffa, size = $0006, type = ro, file = %O, fill = yes;
}
SEGMENTS {
    HEADER:   load = HEADER,  type = ro;
    ZEROPAGE: load = ZP,      type = zp;
    BSS:      load = RAM,     type = bss;
    CODE:     load = PRG,     type = ro;
    RODATA:   load = PRG,     type = ro;
    VECTORS:  load = VECTORS, type = ro;
}
"""

const MAKEFILE := """# Builds {name}.nes with cc65 (https://cc65.github.io): ca65 and ld65.
CA65 ?= ca65
LD65 ?= ld65

{name}.nes: main.o nes.cfg
	$(LD65) -C nes.cfg -o $@ main.o

main.o: main.s {name}.s famistudio_ca65.s
	$(CA65) -o $@ main.s

clean:
	rm -f main.o {name}.nes
"""


static func _readme(name: String, label: String, sfx: bool, sounds: Array = []) -> String:
	var lines: PackedStringArray = [
		"NES: %s for FamiStudio's sound engine" % ("sound effects" if sfx else "music"),
		"",
		"%s.s       %s" % [name, "The sounds, for famistudio_sfx_init and famistudio_sfx_play." if sfx else "The song as music data for the engine (ca65)."],
		"main.s           An example program that %s." % ("plays each sound in turn" if sfx else "plays the song"),
		"famistudio_ca65.s  FamiStudio's sound engine (MIT, https://famistudio.org).",
		"famistudio_cc65.h  The engine's C header, for games written in C with cc65.",
		"nes.cfg, Makefile  Build the example: install cc65, then run make. The ROM is %s.nes." % name,
		"",
		"In your own game:",
		"  1. Include famistudio_ca65.s with the settings main.s uses (or copy them).",
	]
	if sfx:
		lines.append_array([
			"     Sound effects need FAMISTUDIO_CFG_SFX_SUPPORT = 1.",
			"  2. Call famistudio_init with your music, then famistudio_sfx_init with",
			"     x/y pointing at \"sounds\".",
			"  3. Play sound N with: lda #N, ldx #FAMISTUDIO_SFX_CH0, jsr famistudio_sfx_play.",
			"  4. Call famistudio_update once per frame (in NMI).",
			"",
			"The engine plays a sound over the music on its channel and gives the",
			"channel back when it ends. Sounds, by number:",
		])
		for i in sounds.size():
			lines.append("  %d  %s" % [i, sounds[i].name])
	else:
		lines.append_array([
			"  2. Call famistudio_init with a = 1 (NTSC) and x/y pointing at %s," % label,
			"     then famistudio_music_play with a = 0.",
			"  3. Call famistudio_update once per frame (in NMI).",
			"",
			"From C (cc65): #include \"famistudio_cc65.h\", declare",
			"  extern const unsigned char %s[];" % label,
			"and call famistudio_init(FAMISTUDIO_PLATFORM_NTSC, %s)," % label,
			"famistudio_music_play(0) and famistudio_update() once per frame.",
			"",
			"The data matches FamiStudio %s's own \"FamiStudio Sound Engine (ca65)\" export," % ENGINE_VERSION,
			"so use it with the engine from the same version (included here).",
		])
	return "\n".join(lines) + "\n"
