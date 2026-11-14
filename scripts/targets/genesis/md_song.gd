class_name MdSong
extends NesSong
## A song arranged for the Mega Drive / Genesis: six YM2612 FM channels and
## the SN76489's three squares and noise, ten channels in all.
##
## It keeps [NesSong]'s rows, groove, notes, instruments and arpeggios, with
## these differences:[br]
## - [member notes] has ten channels: FM 1 to 6, then Square 1 to 3 and Noise.[br]
## - A note on an FM or square channel is a MIDI note number; on the noise
##   channel it is the noise rate, 0 (highest) to 2.[br]
## - Volumes and volume envelopes are levels from 0 (silent) to 15 (full) in
##   2 dB steps, as on the Master System. On an FM channel the level lowers
##   the carriers' total level.[br]
## - An FM instrument has an "fm" patch (see [method patch_registers]).
##   Pitch envelopes are in cents on FM channels and in tone period steps on
##   the squares.[br]
## [MdArranger] makes one, [MdPlayer] plays it, and [MdVgmWriter] writes it
## as a VGM file, which SGDK's rescomp turns into XGM music.

const CHANNEL_COUNT := 10
const MD_CHANNEL_NAMES: PackedStringArray = ["FM 1", "FM 2", "FM 3", "FM 4", "FM 5", "FM 6", "Square 1", "Square 2", "Square 3", "Noise"]
const FM1 := 0
const FM2 := 1
const FM3 := 2
const FM4 := 3
const FM5 := 4
const FM6 := 5
const SQUARE1 := 6
const SQUARE2 := 7
const SQUARE3 := 8
const MD_NOISE := 9
## NTSC frame rate: the rate XGM's driver and our VGM waits run at.
const FRAME_HZ := SmsSong.FRAME_HZ
## FM notes stay in the range the arranger writes for (C1 to C8).
const FM_LOWEST := 24
const FM_HIGHEST := 108


func _init() -> void:
	frame_hz = FRAME_HZ
	notes = []
	for c in CHANNEL_COUNT:
		notes.append([])


static func is_fm(channel: int) -> bool:
	return channel < SQUARE1


## Block and F-number for a frequency, the block as low as keeps the
## F-number within 11 bits, for the finest tuning. Returns [block, fnum].
static func fm_pitch(hz: float) -> PackedInt32Array:
	for block in 8:
		var fnum := roundi(hz * 1048576.0 / (Ym2612.CHIP_RATE * pow(2.0, block - 1)))
		if fnum <= 2047:
			return PackedInt32Array([block, maxi(fnum, 1)])
	return PackedInt32Array([7, 2047])


static func midi_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## A MIDI note moved by octaves into the FM range. Returns {note, moved}.
static func fit_fm(midi: int) -> Dictionary:
	var note := midi
	var moved := false
	while note < FM_LOWEST:
		note += 12
		moved = true
	while note > FM_HIGHEST:
		note -= 12
		moved = true
	return {"note": note, "moved": moved}


## The register writes that load a patch into FM channel [param channel]
## (0 to 5), as [port, register, value] triples. A patch is {alg, fb, ops}
## with four operators (1 to 4, Yamaha's numbering), each {mul, dt, tl, ks,
## ar, d1r, d2r, d1l, rr}. [param carrier_atten] is added to the total level
## of the operators the algorithm sends to the output.
static func patch_registers(channel: int, patch: Dictionary, carrier_atten := 0) -> Array:
	var port := channel / 3
	var ch := channel % 3
	var out: Array = []
	var carriers: Array = Ym2612.ROUTES[int(patch["alg"])][1]
	var ops: Array = patch["ops"]
	for slot in 4:
		var op: int = Ym2612.SLOT_OPERATOR[slot]
		var o: Dictionary = ops[op]
		var r := ch + slot * 4
		out.append([port, 0x30 + r, ((int(o.get("dt", 0)) & 7) << 4) | (int(o.get("mul", 1)) & 15)])
		out.append([port, 0x40 + r, operator_tl(patch, op, carrier_atten)])
		out.append([port, 0x50 + r, ((int(o.get("ks", 0)) & 3) << 6) | (int(o.get("ar", 31)) & 31)])
		out.append([port, 0x60 + r, int(o.get("d1r", 0)) & 31])
		out.append([port, 0x70 + r, int(o.get("d2r", 0)) & 31])
		out.append([port, 0x80 + r, ((int(o.get("d1l", 0)) & 15) << 4) | (int(o.get("rr", 15)) & 15)])
		out.append([port, 0x90 + r, 0])
	out.append([port, 0xB0 + ch, ((int(patch.get("fb", 0)) & 7) << 3) | (int(patch["alg"]) & 7)])
	# Both speakers on, no LFO sensitivity.
	out.append([port, 0xB4 + ch, 0xC0])
	return out


## Total level for operator [param op] (0 to 3), with [param carrier_atten]
## more on carriers.
static func operator_tl(patch: Dictionary, op: int, carrier_atten: int) -> int:
	var carriers: Array = Ym2612.ROUTES[int(patch["alg"])][1]
	var tl := int(patch["ops"][op].get("tl", 0))
	if carriers[op]:
		tl += carrier_atten
	return clampi(tl, 0, 127)


## Extra carrier attenuation, in total level steps (0.75 dB), for a level
## of 0 to 15 in 2 dB steps.
static func level_atten(level: int) -> int:
	if level <= 0:
		return 127
	return roundi((15 - clampi(level, 0, 15)) * 2.0 / 0.75)
