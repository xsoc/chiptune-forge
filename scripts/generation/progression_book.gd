class_name ProgressionBook
extends RefCounted
## Chord progressions by family, written as Roman numerals relative to the
## major scale of the key (so minor keys use bIII, bVI and bVII).
##
## Each family has a book for major-feel modes and one for minor-feel modes.
## Weights within a list are equal; families are weighted by vibe and style.

const MAJOR := {
	"pop": [
		["I", "V", "vi", "IV"], ["I", "vi", "IV", "V"], ["vi", "IV", "I", "V"],
		["I", "IV", "vi", "V"], ["I", "V", "IV", "V"], ["IV", "I", "V", "vi"],
		["I", "iii", "IV", "V"], ["I", "IV", "I", "V"],
	],
	"rock": [
		["I", "bVII", "IV", "I"], ["I", "IV", "V", "IV"], ["I", "V", "IV", "IV"],
		["I", "bIII", "IV", "I"], ["I", "IV", "I", "V"], ["I", "bVII", "bVI", "bVII"],
	],
	"jazz": [
		["Imaj7", "vi7", "ii7", "V7"], ["ii7", "V7", "Imaj7", "Imaj7"],
		["Imaj7", "IV7", "iii7", "VI7"], ["iii7", "VI7", "ii7", "V7"],
		["Imaj7", "bIIImaj7", "bVImaj7", "bIImaj7"], ["IVmaj7", "iii7", "ii7", "Imaj7"],
	],
	"blues": [
		["I7", "IV7", "I7", "V7"], ["I7", "I7", "IV7", "I7"], ["I7", "IV7", "V7", "IV7"],
	],
	"epic": [
		["I", "bVI", "bVII", "I"], ["I", "V", "vi", "iii"], ["IV", "V", "iii", "vi"],
		["I", "bVII", "IV", "V"], ["vi", "IV", "I", "V"], ["I", "iii", "IV", "V"],
	],
	"folk": [
		["I", "IV", "I", "V"], ["I", "V", "I", "IV"], ["I", "I", "IV", "V"],
		["I", "vi", "IV", "V"], ["I", "IV", "V", "I"],
	],
	"classical": [
		["I", "IV", "V", "I"], ["I", "ii", "V", "I"], ["I", "vi", "ii", "V"],
		["I", "IV", "ii", "V"], ["I", "V", "vi", "IV"], ["I", "vi", "IV", "V7"],
	],
	"modal": [
		["I", "II", "I", "II"], ["I", "bVII", "IV", "I"], ["I", "II", "IV", "I"],
		["Imaj7", "IImaj7", "Imaj7", "vii"], ["I", "bVII", "I", "bVII"],
	],
	"dark": [
		["I", "bVI", "bII", "I"], ["I", "bIII", "bVI", "bII"], ["I", "iv", "I", "bVI"],
	],
	"strange": [
		["I+", "II+", "I+", "bVII+"], ["I", "bV", "I", "bV"], ["I", "bII", "bIII", "bII"],
		["Imaj7", "bVImaj7", "IIImaj7", "Imaj7"],
	],
	"dreamy": [
		["Imaj7", "IVmaj7", "Imaj7", "IVmaj7"], ["Imaj7", "iii7", "vi7", "IVmaj7"],
		["IVmaj7", "V", "iii7", "vi7"], ["Iadd9", "vi7", "IVmaj7", "Vsus4"],
	],
	"cadence": [
		["IV", "V", "I", "I"], ["ii", "V", "I", "I"], ["bVI", "bVII", "I", "I"],
	],
}

const MINOR := {
	"pop": [
		["i", "bVI", "bIII", "bVII"], ["i", "bVII", "bVI", "bVII"], ["i", "iv", "bVI", "V"],
		["bVI", "bVII", "i", "i"], ["i", "bVI", "iv", "bVII"], ["i", "bIII", "bVII", "iv"],
	],
	"rock": [
		["i", "bVII", "bVI", "bVII"], ["i", "iv", "bVII", "i"], ["i", "bVI", "bVII", "i"],
		["i", "bIII", "iv", "bVI"], ["i", "i", "bVI", "bVII"],
	],
	"jazz": [
		["iih7", "V7", "i7", "i7"], ["i7", "iv7", "bVII7", "bIIImaj7"],
		["i7", "bVImaj7", "iih7", "V7"], ["i6", "iv7", "iih7", "V7"],
	],
	"blues": [
		["i7", "iv7", "i7", "v7"], ["i7", "i7", "iv7", "i7"], ["i7", "bVI7", "V7", "i7"],
	],
	"epic": [
		["i", "bVI", "bIII", "bVII"], ["i", "bVI", "bVII", "i"], ["i", "iv", "bVI", "V"],
		["bVI", "bVII", "i", "bIII"], ["i", "bVII", "bVI", "V"],
	],
	"folk": [
		["i", "bVII", "i", "bVII"], ["i", "bIII", "bVII", "i"], ["i", "iv", "i", "bVII"],
		["i", "bVII", "bVI", "bVII"],
	],
	"classical": [
		["i", "iv", "V", "i"], ["i", "bVI", "iv", "V"], ["i", "iio", "V", "i"],
		["i", "iv", "bVII", "bIII"], ["i", "bVI", "iio", "V7"],
	],
	"modal": [
		["i", "IV", "i", "IV"], ["i7", "IV7", "i7", "IV7"], ["i", "bII", "i", "bII"],
		["i", "bVII", "IV", "i"], ["i", "ii", "i", "bVII"],
	],
	"dark": [
		["i", "bII", "i", "bII"], ["i", "iv", "i", "V"], ["i", "bVI", "bII", "V"],
		["i", "i", "bVI", "V"], ["i", "#ivo", "iv", "V"], ["i", "bII", "bVI", "V"],
	],
	"strange": [
		["i", "#ivo", "i", "bii"], ["i", "bV", "i", "bV"], ["io7", "bIIIo7", "io7", "#ivo7"],
		["I+", "bVI+", "I+", "bII+"], ["i", "bii", "i", "vii"],
	],
	"dreamy": [
		["i7", "bVImaj7", "bIIImaj7", "bVII"], ["i7", "iv7", "i7", "bVImaj7"],
		["imadd9", "bVImaj7", "iv7", "bVII"],
	],
	"cadence": [
		["iv", "V", "i", "i"], ["bVI", "bVII", "i", "i"], ["iih7", "V7", "i", "i"],
	],
}


## Returns one progression for a family, falling back to "pop".
static func pick(family: String, minor: bool, rng: Pcg32) -> Array:
	var book: Dictionary = MINOR if minor else MAJOR
	var options: Array = book.get(family, book["pop"])
	return options[rng.range_int(0, options.size() - 1)]
