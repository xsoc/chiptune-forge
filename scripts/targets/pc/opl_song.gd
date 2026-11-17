class_name OplSong
extends NesSong
## A song arranged for a PC sound card's FM chip: the AdLib's and Sound
## Blaster's OPL2, the Sound Blaster Pro's two OPL2s (one per speaker) or
## the Sound Blaster 16's OPL3.
##
## It keeps [NesSong]'s rows, groove, notes, instruments and arpeggios, with
## these differences:[br]
## - [member layout] says what each channel of [member notes] is: a
##   melodic FM channel (bank and channel 0 to 8, a detune in cents and its
##   speakers), or one of the rhythm mode's five drums.[br]
## - Notes are MIDI note numbers. Volumes are levels from 0 (silent) to 15
##   (full) in 2 dB steps, which lower the carrier's total level.[br]
## - An instrument is an [OplPatches] patch under "opl", or for the drums a
##   rhythm piece.[br]
## The driver runs at 70 Hz, the VGA refresh many DOS games timed music by,
## which also divides evenly into the IMF format's 700 Hz ticks.
## [OplArranger] makes one, [OplPlayer] plays it and [OplWriter] writes it
## as IMF, DRO and VGM files.

const FRAME_HZ := 70.0
const DRUMS: PackedStringArray = ["bd", "sd", "tom", "cym", "hh"]
## The rhythm mode's key bits in register $BD.
const DRUM_BIT := {"bd": 0x10, "sd": 0x08, "tom": 0x04, "cym": 0x02, "hh": 0x01}
const DRUM_NAMES := {"bd": "Bass drum", "sd": "Snare", "tom": "Tom", "cym": "Cymbal", "hh": "Hi-hat"}
## Notes stay in the range the chip plays cleanly.
const LOWEST := 24
const HIGHEST := 108

## Card id from [constant PcCards.CARDS].
var card := "adlib"
## "opl2", "dual_opl2" or "opl3".
var chip := "opl2"
## One entry per channel of [member notes]: {name, bank, ch, drum, detune,
## pan}. "drum" is "" for a melodic channel or one of [constant DRUMS];
## "pan" is "L", "R" or "LR" (OPL3 only; on two OPL2s the bank is the
## speaker).
var layout: Array = []


func _init() -> void:
	frame_hz = FRAME_HZ
	notes = []


func channel_names() -> PackedStringArray:
	var names := PackedStringArray()
	for v in layout:
		names.append(str(v["name"]))
	return names


func note_count() -> int:
	var total := 0
	for list in notes:
		total += (list as Array).size()
	return total


## Uses the rhythm mode on bank [param bank].
func rhythm_on(bank: int) -> bool:
	for v in layout:
		if str(v["drum"]) != "" and int(v["bank"]) == bank:
			return true
	return false


## Block and F-number for a frequency: the lowest block that keeps the
## F-number within 10 bits, for the finest tuning. Returns [block, fnum].
static func fnum_of(hz: float) -> PackedInt32Array:
	for block in 8:
		var fnum := roundi(hz * pow(2.0, 20 - block) / Opl.CHIP_RATE)
		if fnum <= 1023:
			return PackedInt32Array([block, maxi(fnum, 1)])
	return PackedInt32Array([7, 1023])


static func midi_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Extra total level (0.75 dB steps) for a level of 0 to 15 in 2 dB steps.
static func level_atten(level: int) -> int:
	if level <= 0:
		return 63
	return roundi((15 - clampi(level, 0, 15)) * 2.0 / 0.75)


## The register writes that load [param patch] into channel [param ch] (0
## to 8) of a bank, as [register, value] pairs. [param atten] is added to
## the carrier's total level (and the modulator's, in additive mode).
static func patch_registers(ch: int, patch: Dictionary, atten := 0, pan := 0x30) -> Array:
	var out: Array = []
	var mod_off: int = Opl.OP_OFFSET[ch]
	var car_off := mod_off + 3
	var additive := int(patch.get("cnt", 0)) == 1
	var m := OplPatches.op_bytes(patch["mod"], atten if additive else 0)
	var c := OplPatches.op_bytes(patch["car"], atten)
	var bases := [0x20, 0x40, 0x60, 0x80, 0xE0]
	for k in 5:
		out.append([bases[k] + mod_off, m[k]])
		out.append([bases[k] + car_off, c[k]])
	out.append([0xC0 + ch, pan | ((int(patch.get("fb", 0)) & 7) << 1) | (int(patch.get("cnt", 0)) & 1)])
	return out
