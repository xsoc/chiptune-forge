class_name PcCards
extends RefCounted
## The PC sound cards of the late 1980s to the mid 1990s that the "pc"
## target can play and export for. Each card's music goes through one of
## the arrangers ([method arrange] picks): [SpeakerArranger] for the PC
## speaker, [SmsArranger] for the Tandy's SN76496 and [OplArranger] for the
## FM cards.

const CARDS: PackedStringArray = ["speaker", "tandy", "adlib", "sb", "sbpro", "sb16"]
const DEFAULT := "adlib"
const INFO := {
	"speaker": {
		"name": "PC speaker",
		"year": 1981,
		"chip": "speaker",
		"description": "The IBM PC's own speaker: one square wave from the 8253 timer, on or off. Exports C data and a small DOS player.",
	},
	"tandy": {
		"name": "Tandy 1000",
		"year": 1984,
		"chip": "sn76496",
		"description": "Texas Instruments SN76496: 3 square voices and noise, with volume. Exports VGM.",
	},
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


## Music export formats for a card: "imf" (OPL2 only), "dro" and "vgm";
## "c" (data and player source) and "bin" for the PC speaker.
static func music_formats(card: String) -> PackedStringArray:
	match chip_of(card):
		"speaker":
			return PackedStringArray(["c", "bin"])
		"sn76496":
			return PackedStringArray(["vgm"])
	if chip_of(card) == "opl2":
		return PackedStringArray(["imf", "dro", "vgm"])
	return PackedStringArray(["dro", "vgm"])


## True for the cards with an FM chip.
static func is_fm(card: String) -> bool:
	return chip_of(card) in ["opl2", "dual_opl2", "opl3"]


## [param song] arranged for [param card]: an [OplSong], an [SmsSong] (the
## Tandy) or a [SpeakerSong].
static func arrange(song: ChipSong, card: String) -> NesSong:
	match chip_of(card):
		"speaker":
			return SpeakerArranger.arrange(song)
		"sn76496":
			return tandy(song)
	return OplArranger.arrange(song, card)


## The Master System arrangement, on the Tandy's SN76496: the same three
## squares and noise, with the SN76496's white noise.
static func tandy(song: ChipSong) -> SmsSong:
	var sms := SmsArranger.arrange(song)
	sms.noise_taps = 0x0006
	sms.noise_width = 16
	sms.source.data["meta"]["target"] = "pc"
	var lines := PackedStringArray()
	for line in sms.report:
		lines.append(line.replace("PSGlib plays", "the driver plays").replace("the Master System has none", "the Tandy has none").replace("the SN76489 has", "the SN76496 has"))
	sms.report = lines
	return sms
