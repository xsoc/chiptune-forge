class_name MidiWriter
extends RefCounted
## Writes a song as a type 1 MIDI file: a conductor track with tempo, time
## signature and section markers, then one track per channel. Drums go to
## General MIDI channel 10, and chip arpeggio chords become real chords.

const PPQ := 96
## General MIDI programs per generated channel.
const PROGRAMS := [80, 80, 81, 89, 38, 0, 0]
## General MIDI drum notes per drum instrument index (see DrumWriter).
const DRUM_NOTES := {5: 36, 6: 38, 7: 42, 8: 46, 9: 49, 10: 45, 11: 51}


static func encode(song: ChipSong) -> PackedByteArray:
	var data := song.data
	var spb := song.get_steps_per_beat()
	var ticks_per_step := PPQ / spb
	var swing := float(data["timing"].get("swing", 0.0))
	var swing_ticks := int(swing * ticks_per_step * 0.667)
	var channels: Array = data["channels"]
	var per_channel: Array = []
	for c in channels.size():
		per_channel.append([])

	var section_start := 0
	var markers: Array = []
	for index in data["order"]:
		var section: Dictionary = data["sections"][int(index)]
		markers.append([section_start * ticks_per_step, str(section["name"])])
		var ids: Array = section["patterns"]
		for c in mini(ids.size(), channels.size()):
			if int(ids[c]) < 0:
				continue
			for note in data["patterns"][int(ids[c])]["notes"]:
				var step := section_start + int(note[0])
				var tick := step * ticks_per_step
				if spb % 2 == 0 and step % spb == spb / 2:
					tick += swing_ticks
				var length := maxi(int(note[1]) * ticks_per_step - 2, 1)
				var velocity := int(note[3]) if note.size() > 3 else 100
				var inst := int(note[4]) if note.size() > 4 else -1
				var pitches: Array = [int(note[2])]
				if note.size() > 5 and note[5] is Array:
					pitches.clear()
					for offset in note[5]:
						pitches.append(int(note[2]) + int(offset))
				if inst >= 0 and DRUM_NOTES.has(inst):
					pitches = [DRUM_NOTES[inst]]
					if inst == 10:
						pitches = [45 + clampi((int(note[2]) - 43) / 3, 0, 5)]
				for pitch in pitches:
					per_channel[c].append([tick, length, clampi(pitch, 0, 127), clampi(velocity, 1, 127)])
		section_start += int(section["length"])

	var tracks: Array[PackedByteArray] = []
	tracks.append(_conductor(song, markers, ticks_per_step))
	var midi_channel := 0
	for c in channels.size():
		if per_channel[c].is_empty():
			continue
		var is_drums := str(channels[c].get("layer", "")) == "Drums"
		var ch := 9 if is_drums else midi_channel
		if not is_drums:
			midi_channel += 1
			if midi_channel == 9:
				midi_channel = 10
		tracks.append(_note_track(str(channels[c].get("name", "Channel")), per_channel[c], ch, PROGRAMS[c] if c < PROGRAMS.size() else 80, is_drums))

	var out := PackedByteArray()
	out.append_array("MThd".to_ascii_buffer())
	out.append_array(_be32(6))
	out.append_array(_be16(1))
	out.append_array(_be16(tracks.size()))
	out.append_array(_be16(PPQ))
	for track in tracks:
		out.append_array("MTrk".to_ascii_buffer())
		out.append_array(_be32(track.size()))
		out.append_array(track)
	return out


static func _conductor(song: ChipSong, markers: Array, ticks_per_step: int) -> PackedByteArray:
	var events: Array = []
	events.append([0, _meta(0x03, song.get_title().to_utf8_buffer())])
	events.append([0, _meta(0x01, str(song.data["meta"].get("license", "")).to_utf8_buffer())])
	var tempo := int(60000000.0 / song.get_bpm())
	events.append([0, _meta(0x51, PackedByteArray([(tempo >> 16) & 0xFF, (tempo >> 8) & 0xFF, tempo & 0xFF]))])
	events.append([0, _meta(0x58, PackedByteArray([song.get_beats_per_bar(), 2, 24, 8]))])
	for marker in markers:
		events.append([marker[0], _meta(0x06, str(marker[1]).to_utf8_buffer())])
	if bool(song.data["timing"].get("loop", true)):
		events.append([song.get_loop_start_step() * ticks_per_step, _meta(0x06, "loopStart".to_ascii_buffer())])
		events.append([song.get_loop_end_step() * ticks_per_step, _meta(0x06, "loopEnd".to_ascii_buffer())])
	return _track_bytes(events, song.get_length_steps() * ticks_per_step)


static func _note_track(track_name: String, notes: Array, channel: int, program: int, is_drums: bool) -> PackedByteArray:
	var events: Array = []
	events.append([0, _meta(0x03, track_name.to_utf8_buffer())])
	if not is_drums:
		events.append([0, PackedByteArray([0xC0 | channel, program])])
	var end := 0
	for note in notes:
		events.append([note[0], PackedByteArray([0x90 | channel, note[2], note[3]])])
		events.append([note[0] + note[1], PackedByteArray([0x80 | channel, note[2], 0])])
		end = maxi(end, note[0] + note[1])
	return _track_bytes(events, end)


static func _track_bytes(events: Array, end_tick: int) -> PackedByteArray:
	# Note-offs sort before note-ons at the same tick, so repeated notes retrigger.
	events.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return _order(a[1]) < _order(b[1]))
	var out := PackedByteArray()
	var last := 0
	for event in events:
		out.append_array(_vlq(int(event[0]) - last))
		out.append_array(event[1])
		last = int(event[0])
	out.append_array(_vlq(maxi(end_tick - last, 0)))
	out.append_array(PackedByteArray([0xFF, 0x2F, 0x00]))
	return out


static func _order(bytes: PackedByteArray) -> int:
	var status := bytes[0] & 0xF0
	if bytes[0] == 0xFF:
		return 0
	if status == 0xC0:
		return 1
	if status == 0x80:
		return 2
	return 3


static func _meta(kind: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([0xFF, kind])
	out.append_array(_vlq(payload.size()))
	out.append_array(payload)
	return out


static func _vlq(value: int) -> PackedByteArray:
	var bytes := [value & 0x7F]
	value >>= 7
	while value > 0:
		bytes.push_front((value & 0x7F) | 0x80)
		value >>= 7
	return PackedByteArray(bytes)


static func _be32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


static func _be16(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 8) & 0xFF, value & 0xFF])
