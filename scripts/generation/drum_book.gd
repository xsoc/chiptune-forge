class_name DrumBook
extends RefCounted
## One-bar drum patterns by family, on a 16th-note grid.
##
## Each pattern has lines for kick (k), snare (s), closed hat (h), open hat (o)
## and ride (r). "x" is a hit, "a" an accented hit and "g" a quiet ghost note.
## "calm" is used for low-energy sections and "busy" for high-energy ones;
## missing lines fall back to the base pattern.

const PATTERNS := {
	"rock": {
		"base": {"k": "x.......x.x.....", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
		"busy": {"k": "x.....x.x.x...x.", "s": "....a..g....a...", "h": "xxxxxxxxxxxxxxxx"},
		"calm": {"k": "x.......x.......", "s": "....x.......x...", "h": "x...x...x...x..."},
	},
	"four_floor": {
		"base": {"k": "a...a...a...a...", "s": "....x.......x...", "h": "..x...x...x...x."},
		"busy": {"k": "a...a...a...a...", "s": "....x.......x...", "h": "xxoxxxoxxxoxxxox"},
		"calm": {"k": "x...x...x...x...", "s": "................", "h": "..x...x...x...x."},
	},
	"disco": {
		"base": {"k": "a...a...a...a...", "s": "....x.......x...", "h": "x.o.x.o.x.o.x.o."},
		"busy": {"k": "a...a...a...a...", "s": "....x.......x..g", "h": "xxoxxxoxxxoxxxox"},
	},
	"breakbeat": {
		"base": {"k": "x.........x.....", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
		"busy": {"k": "x.x.......xx....", "s": "....a..g.g..a..g", "h": "xxxxxxxxxxxxxxxx"},
		"calm": {"k": "x.........x.....", "s": "....x.......x...", "h": "x...x...x...x..."},
	},
	"dnb": {
		"base": {"k": "x.........x.....", "s": "....a.......a...", "h": "xxxxxxxxxxxxxxxx"},
		"busy": {"k": "x.x.......x..x..", "s": "....a..g....a.g.", "h": "xxxxxxxxxxxxxxxx"},
		"calm": {"k": "x.........x.....", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."},
	},
	"halftime": {
		"base": {"k": "x.....x.........", "s": "........a.......", "h": "x.x.x.x.x.x.x.x."},
		"busy": {"k": "x.....x...x..x..", "s": "........a.......", "h": "xxxxxxxxxxxxxxxx"},
		"calm": {"k": "x...............", "s": "........x.......", "h": "x...x...x...x..."},
	},
	"trap": {
		"base": {"k": "x......x..x.....", "s": "........a.......", "h": "x.x.x.x.x.xxx.x."},
		"busy": {"k": "x......x..x..x..", "s": "........a.......", "h": "xxxxx.xxxxxxxxxx"},
	},
	"funk": {
		"base": {"k": "x..x..x...x..x..", "s": "....a..g.g..a..g", "h": "xxxxxxxxxxxxxxxx"},
		"calm": {"k": "x.....x...x.....", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
	},
	"swing": {
		"base": {"k": "x.......x.......", "s": "....g.......g...", "r": "a...x.x.a...x.x.", "h": "....x.......x..."},
		"busy": {"k": "x.....x.x.......", "s": "....a..g....a..g", "r": "a...x.x.a...x.x."},
		"calm": {"k": "x...............", "s": "................", "r": "x...x.x.x...x.x."},
	},
	"shuffle": {
		"base": {"k": "x.......x.x.....", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
	},
	"march": {
		"base": {"k": "x.......x.......", "s": "a.xxa.x.a.xxa.x.", "h": "................"},
		"calm": {"k": "x.......x.......", "s": "x...x...x...x...", "h": "................"},
	},
	"reggae": {
		"base": {"k": "........a.......", "s": "........a.......", "h": "..x...x...x...x."},
		"busy": {"k": "x.......a.......", "s": "........a.......", "h": "x.xxx.xxx.xxx.xx"},
	},
	"bossa": {
		"base": {"k": "x..xx..xx..xx..x", "s": "..x..x....x..x..", "h": "x.x.x.x.x.x.x.x."},
		"calm": {"k": "x..x....x..x....", "s": "..x..x....x..x..", "h": "x...x...x...x..."},
	},
	"latin": {
		"base": {"k": "x..x....x..x....", "s": "...x..x....x..x.", "h": "x.xxx.xxx.xxx.xx"},
	},
	"polka": {
		"base": {"k": "x.......x.......", "s": "....x.......x...", "h": "..x...x...x...x."},
	},
	"ska": {
		"base": {"k": "x.......x.......", "s": "....a.......a...", "h": "..o...o...o...o."},
	},
	"metal": {
		"base": {"k": "x.x.x.x.x.x.x.x.", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
		"busy": {"k": "xxxxxxxxxxxxxxxx", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
		"calm": {"k": "x.......x.......", "s": "....a.......a...", "h": "x...x...x...x..."},
	},
	"punk": {
		"base": {"k": "x...x...x...x...", "s": "..a...a...a...a.", "h": "x.x.x.x.x.x.x.x."},
	},
	"driving": {
		"base": {"k": "x...x...x...x...", "s": "....a.......a...", "h": "xxxxxxxxxxxxxxxx"},
		"busy": {"k": "x.x.x...x.x.x...", "s": "....a..g....a..g", "h": "xxxxxxxxxxxxxxxx"},
		"calm": {"k": "x.......x.......", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."},
	},
	"chip": {
		"base": {"k": "x.....x...x.....", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
		"busy": {"k": "x.....x.x.x.....", "s": "....a..g....a.g.", "h": "xxxxxxxxxxxxxxxx"},
		"calm": {"k": "x.......x.......", "s": "....x.......x...", "h": "x...x...x...x..."},
	},
	"boom_bap": {
		"base": {"k": "x......x..x.....", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
	},
	"trip_hop": {
		"base": {"k": "x......x.x......", "s": "....a.......a...", "h": "x.x.x.x.x.x.x.x."},
		"calm": {"k": "x.........x.....", "s": "....x.......x...", "h": "x...x...x...x..."},
	},
	"train": {
		"base": {"k": "x...x...x...x...", "s": "..a...a...a...a.", "h": "gxggxggxgxggxggx"},
	},
	"tango": {
		"base": {"k": "a..x..x.a.......", "s": "....x.......x.x.", "h": "x...x...x...x..."},
	},
	"jig": {
		"base": {"k": "x.....x.....x...", "s": "....x.......x...", "h": "x.xx.xx.xx.xx.x."},
	},
	"sparse": {
		"base": {"k": "x...............", "s": "................", "h": "........x......."},
		"busy": {"k": "x.......x.......", "s": "....x.......x...", "h": "x...x...x...x..."},
		"calm": {"k": "x...............", "s": "................", "h": "................"},
	},
	"none": {
		"base": {"k": "................", "s": "................", "h": "................"},
	},
}

## Patterns for three beats to the bar (12 steps).
const PATTERNS_3 := {
	"waltz": {
		"base": {"k": "x...........", "s": "....x...x...", "h": "x...x...x..."},
		"busy": {"k": "x.....x.....", "s": "....a...a...", "h": "x.x.x.x.x.x."},
	},
	"jig": {
		"base": {"k": "x.....x.....", "s": "...x.....x..", "h": "x.xx.xx.xx.x"},
	},
	"flamenco": {
		"base": {"k": "x.....x.....", "s": "...a..a..a..", "h": "x.x.x.x.x.x."},
	},
	"sparse": {
		"base": {"k": "x...........", "s": "............", "h": "........x..."},
	},
	"none": {
		"base": {"k": "............", "s": "............", "h": "............"},
	},
}


## Returns the pattern lines for a family, energy level and bar length.
## Bars of other lengths get a pattern built from the 4/4 one.
static func get_pattern(family: String, energy: float, steps_per_bar: int) -> Dictionary:
	var book: Dictionary = PATTERNS_3 if steps_per_bar == 12 else PATTERNS
	if not book.has(family):
		family = "waltz" if steps_per_bar == 12 else "rock"
	var variants: Dictionary = book[family]
	var base: Dictionary = variants["base"]
	var chosen := base
	if energy < 0.35 and variants.has("calm"):
		chosen = variants["calm"]
	elif energy > 0.7 and variants.has("busy"):
		chosen = variants["busy"]
	var lines := {}
	for key in ["k", "s", "h", "o", "r"]:
		var line: String = chosen.get(key, base.get(key, ""))
		if line == "":
			continue
		lines[key] = _fit(line, steps_per_bar)
	return lines


static func _fit(line: String, steps: int) -> String:
	if line.length() == steps:
		return line
	var out := ""
	for i in steps:
		out += line[i % line.length()]
	return out
