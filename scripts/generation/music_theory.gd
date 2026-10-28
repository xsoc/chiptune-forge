class_name MusicTheory
extends RefCounted
## Scales, chords and Roman numeral parsing. Pitches are MIDI note numbers;
## pitch classes are 0 to 11 with C as 0.

const NOTE_NAMES: PackedStringArray = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

const SCALES := {
	"major": [0, 2, 4, 5, 7, 9, 11],
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"major_pentatonic": [0, 2, 4, 7, 9],
	"minor_pentatonic": [0, 3, 5, 7, 10],
	"blues": [0, 3, 5, 6, 7, 10],
	"whole_tone": [0, 2, 4, 6, 8, 10],
	"diminished": [0, 2, 3, 5, 6, 8, 9, 11],
	"hijaz": [0, 1, 4, 5, 7, 8, 10],
	"japanese": [0, 1, 5, 7, 8],
}

## Display names for the mode picker.
const MODE_NAMES := {
	"major": "Major",
	"minor": "Minor",
	"harmonic_minor": "Harmonic minor",
	"dorian": "Dorian",
	"phrygian": "Phrygian",
	"lydian": "Lydian",
	"mixolydian": "Mixolydian",
	"major_pentatonic": "Major pentatonic",
	"minor_pentatonic": "Minor pentatonic",
	"blues": "Blues",
	"whole_tone": "Whole tone",
	"diminished": "Diminished",
	"hijaz": "Hijaz",
	"japanese": "In (Japanese)",
}

## Whether each scale's tonic chord is minor. Decides which progression book
## a mode draws from.
const MINOR_FEEL := {
	"minor": true, "harmonic_minor": true, "dorian": true, "phrygian": true,
	"minor_pentatonic": true, "blues": true, "diminished": true, "hijaz": false,
	"japanese": true,
}

const CHORD_INTERVALS := {
	"maj": [0, 4, 7],
	"min": [0, 3, 7],
	"dim": [0, 3, 6],
	"aug": [0, 4, 8],
	"sus2": [0, 2, 7],
	"sus4": [0, 5, 7],
	"maj7": [0, 4, 7, 11],
	"min7": [0, 3, 7, 10],
	"dom7": [0, 4, 7, 10],
	"hdim7": [0, 3, 6, 10],
	"dim7": [0, 3, 6, 9],
	"add9": [0, 4, 7, 14],
	"madd9": [0, 3, 7, 14],
	"maj6": [0, 4, 7, 9],
	"min6": [0, 3, 7, 9],
	"5": [0, 7],
}

const _NUMERALS := {"I": 0, "II": 2, "III": 4, "IV": 5, "V": 7, "VI": 9, "VII": 11}


static func is_minor_mode(mode: String) -> bool:
	return MINOR_FEEL.get(mode, false)


static func scale_of(mode: String) -> Array:
	return SCALES.get(mode, SCALES["major"])


static func note_name(pitch: int) -> String:
	return "%s%d" % [NOTE_NAMES[posmod(pitch, 12)], floori(pitch / 12.0) - 1]


static func key_name(key: int, mode: String) -> String:
	return "%s %s" % [NOTE_NAMES[posmod(key, 12)], MODE_NAMES.get(mode, mode)]


## Every pitch of a scale between [param low] and [param high], ascending.
static func scale_pitches(key: int, mode: String, low: int, high: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var scale := scale_of(mode)
	for pitch in range(low, high + 1):
		if scale.has(posmod(pitch - key, 12)):
			out.append(pitch)
	return out


## Parses a Roman numeral such as "bVII", "ii7", "V7", "viio" or "IVmaj7"
## into [code]{root, quality}[/code], with root in semitones above the key.
static func parse_numeral(numeral: String) -> Dictionary:
	var text := numeral
	var shift := 0
	while text.begins_with("b") or text.begins_with("#"):
		shift += -1 if text[0] == "b" else 1
		text = text.substr(1)
	var letters := ""
	for c in text:
		if "IViv".contains(c):
			letters += c
		else:
			break
	var suffix := text.substr(letters.length())
	var upper := letters.to_upper()
	var is_upper := letters == upper
	var root := int(_NUMERALS.get(upper, 0)) + shift
	var quality := "maj" if is_upper else "min"
	match suffix:
		"7":
			quality = "dom7" if is_upper else "min7"
		"maj7":
			quality = "maj7"
		"o", "dim":
			quality = "dim"
		"o7":
			quality = "dim7"
		"h7":
			quality = "hdim7"
		"+":
			quality = "aug"
		"sus2":
			quality = "sus2"
		"sus4":
			quality = "sus4"
		"add9":
			quality = "add9" if is_upper else "madd9"
		"madd9":
			quality = "madd9"
		"6":
			quality = "maj6" if is_upper else "min6"
		"5":
			quality = "5"
	return {"root": posmod(root, 12), "quality": quality}


## Adds a seventh, sixth or ninth to a triad. Leaves other chords alone.
static func colour_chord(quality: String, rng: Pcg32) -> String:
	match quality:
		"maj":
			return ["maj7", "add9", "maj6"][rng.range_int(0, 2)]
		"min":
			return ["min7", "madd9", "min7"][rng.range_int(0, 2)]
	return quality


static func chord_intervals(quality: String) -> Array:
	return CHORD_INTERVALS.get(quality, CHORD_INTERVALS["maj"])


## Pitch classes of a chord.
static func chord_pitch_classes(root_pc: int, quality: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for interval in chord_intervals(quality):
		out.append(posmod(root_pc + int(interval), 12))
	return out


## The pitch nearest to [param pitch] whose class is in [param classes].
## Ties go downwards.
static func nearest_in_classes(pitch: int, classes: PackedInt32Array) -> int:
	for distance in 7:
		if classes.has(posmod(pitch - distance, 12)):
			return pitch - distance
		if classes.has(posmod(pitch + distance, 12)):
			return pitch + distance
	return pitch


## Lowest pitch of [param pc] at or above [param low].
static func pitch_at_or_above(pc: int, low: int) -> int:
	return low + posmod(pc - low, 12)


## Moves [param pitch] by octaves until it lies between [param low] and
## [param high], keeping its pitch class. Use this, never a clamp, on pitches.
static func fold(pitch: int, low: int, high: int) -> int:
	var out := pitch
	while out > high and out - 12 >= low:
		out -= 12
	while out < low and out + 12 <= high:
		out += 12
	if out > high:
		out -= 12
	elif out < low:
		out += 12
	return out
