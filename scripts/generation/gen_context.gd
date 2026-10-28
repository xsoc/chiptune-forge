class_name GenContext
extends RefCounted
## Shared state for one run of the song pipeline. Each stage reads what the
## stages before it wrote and adds its own part.

## Channel order in every generated song. Layers map one to one, except Drums,
## which owns the last two channels.
enum Channel { LEAD, HARMONY, ARP, PAD, BASS, DRUMS, NOISE }
const CHANNEL_COUNT := 7
const CHANNEL_NAMES: PackedStringArray = ["Lead", "Harmony", "Arp", "Pad", "Bass", "Drums", "Noise"]

var settings: SongSettings
var catalog: Catalog
var seed := 0

## Resolved parameters from the vibe, style and sliders (see SongGenerator).
var p: Dictionary = {}
var tempo := 120
var beats_per_bar := 4
var steps_per_beat := 4
var steps_per_bar := 16
var key := 0
var mode := "major"
var minor := false
var form := "verse_chorus"
var loop := true

## Unique sections: {name, letter, kind, bars, energy, chords}. A section that
## appears twice in [member order] is the same entry, sharing its patterns.
var sections: Array[Dictionary] = []
var order: Array[int] = []
## Chords per letter: Array of {start, length, root, quality, pcs}.
var chords_by_letter: Dictionary = {}
## Lead notes per letter, written once and shared by every section of it.
var melody_by_letter: Dictionary = {}
## Notes per section index, then per channel.
var parts: Array = []
## Choices made once per song, such as the accompaniment types.
var choices: Dictionary = {}
var instruments: Array = []


func rng(stage: String, layer := "") -> Pcg32:
	var variation := settings.get_variation(layer) if layer != "" else 0
	return Pcg32.for_stream(seed, "%s:%d" % [stage, variation])


func section_steps(section: Dictionary) -> int:
	return int(section["bars"]) * steps_per_bar


## Chord sounding at [param step] of a section's letter.
func chord_at(letter: String, step: int) -> Dictionary:
	var chords: Array = chords_by_letter.get(letter, [])
	var found: Dictionary = chords[0] if not chords.is_empty() else {"root": key, "quality": "maj", "pcs": PackedInt32Array([key])}
	for chord in chords:
		if int(chord["start"]) <= step:
			found = chord
		else:
			break
	return found


## Adds a note: [step, length, pitch, velocity] plus an optional instrument
## and arpeggio.
func add_note(section_index: int, channel: int, step: int, length: int, pitch: int, velocity: int, instrument := -1, arp: Array = []) -> void:
	var note: Array = [step, maxi(length, 1), clampi(pitch, 0, 127), clampi(velocity, 1, 127)]
	if instrument >= 0 or not arp.is_empty():
		note.append(instrument)
	if not arp.is_empty():
		note.append(arp)
	parts[section_index][channel].append(note)
