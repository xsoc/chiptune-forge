class_name PcCards
extends RefCounted
## The PC sound cards of the late 1980s to the mid 1990s that the "pc"
## target can play and export for. Each card's music goes through one of
## the arrangers: [OplArranger] for the FM cards.

const CARDS: PackedStringArray = ["adlib", "sb", "sbpro", "sb16"]
const DEFAULT := "adlib"
const INFO := {
	"adlib": {
		"name": "AdLib",
		"year": 1987,
		"chip": "opl2",
		"description": "Yamaha YM3812 (OPL2): 9 FM voices, or 6 and five drums. Exports IMF, DRO and VGM.",
	},
	"sb": {
		"name": "Sound Blaster",
		"year": 1989,
		"chip": "opl2",
		"description": "The AdLib's OPL2 plus an 8-bit sample channel for sound effects. Exports IMF, DRO, VGM and VOC.",
	},
	"sbpro": {
		"name": "Sound Blaster Pro",
		"year": 1991,
		"chip": "dual_opl2",
		"description": "Two OPL2s, one per speaker, for 18 FM voices in stereo, and stereo samples. Exports DRO, VGM and VOC.",
	},
	"sb16": {
		"name": "Sound Blaster 16",
		"year": 1992,
		"chip": "opl3",
		"description": "Yamaha YMF262 (OPL3): 18 FM voices, eight waveforms and stereo panning, and 16-bit samples. Exports DRO, VGM and WAV sound effects.",
	},
}


static func chip_of(card: String) -> String:
	return str(INFO.get(card, INFO[DEFAULT])["chip"])


static func name_of(card: String) -> String:
	return str(INFO.get(card, INFO[DEFAULT])["name"])


static func is_card(card: String) -> bool:
	return CARDS.has(card)


## Music export formats for a card: "imf" (OPL2 only), "dro" and "vgm".
static func music_formats(card: String) -> PackedStringArray:
	if chip_of(card) == "opl2":
		return PackedStringArray(["imf", "dro", "vgm"])
	return PackedStringArray(["dro", "vgm"])
