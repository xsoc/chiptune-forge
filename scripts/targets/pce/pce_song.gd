class_name PceSong
extends NesSong
## A song arranged for the PC Engine / TurboGrafx-16: six wavetable
## channels, the last two able to play noise.
##
## It keeps [NesSong]'s rows, groove, notes, instruments and arpeggios, with
## these differences:[br]
## - [member notes] has six channels (see [constant PCE_CHANNEL_NAMES]).[br]
## - A note is a MIDI note number, or with a noise instrument the noise
##   frequency, 0 (lowest) to 31 (highest).[br]
## - Volumes and volume envelopes are levels from 0 (silent) to 15 (full) in
##   2 dB steps that add up as on the Master System
##   ([method SmsSong.mix_level]); the player turns them into the chip's
##   1.5 dB volume steps.[br]
## - An instrument is {name, wave (an index into [member waves]), noise
##   (true to play noise), volume, arp, pitch}. Pitch envelopes are in
##   sixteenths of a semitone, up being higher.[br]
## [PceArranger] makes one, [PcePlayer] plays it, and [PceWriter] writes it
## as data for our C player.

const CHANNEL_COUNT := 6
const PCE_CHANNEL_NAMES: PackedStringArray = ["Lead", "Harmony", "Arp", "Bass", "Pad", "Drums"]
const LEAD := 0
const HARMONY := 1
const ARP := 2
const BASS := 3
const PAD := 4
const DRUMS := 5
## NTSC PC Engine frame rate (7.16 MHz / 455 / 263).
const FRAME_HZ := 59.826
## Lowest and highest notes the arranger writes (C1 to C8).
const LOWEST_NOTE := 24
const HIGHEST_NOTE := 108

## The waveforms, 32 steps of 0 to 31 each.
var waves: Array = []
## Wave names, for reports.
var wave_names: PackedStringArray = []
## Per channel, the balance byte: left volume in the high nibble, right in
## the low.
var balances := PackedInt32Array([0xFF, 0xDF, 0xFD, 0xFF, 0xEF, 0xFF])


func _init() -> void:
	frame_hz = FRAME_HZ
	notes = []
	for c in CHANNEL_COUNT:
		notes.append([])


## The 12-bit frequency divider for a MIDI note.
static func note_period(midi: int) -> int:
	var hz := 440.0 * pow(2.0, (midi - 69) / 12.0)
	return clampi(roundi(PcePsg.CLOCK / (32.0 * hz)), 1, 4095)


## The channel volume (0 to 31) for a level (0 to 15): 2 dB steps as the
## chip's 1.5 dB steps.
static func volume_of_level(level: int) -> int:
	if level <= 0:
		return 0
	return 31 - roundi((15 - mini(level, 15)) * 4.0 / 3.0)


## A MIDI note moved by octaves into the range. Returns {note, moved}.
static func fit(midi: int) -> Dictionary:
	var note := midi
	var moved := false
	while note < LOWEST_NOTE:
		note += 12
		moved = true
	while note > HIGHEST_NOTE:
		note -= 12
		moved = true
	return {"note": note, "moved": moved}


## A named waveform. Pulses and squares are slightly rounded, as composers
## on the console drew them, so they are less harsh than pure squares.
static func make_wave(wave_name: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in 32:
		var t := i / 32.0
		var v := 0.0
		match wave_name:
			"pulse12":
				v = 1.0 if i < 4 else -1.0
			"pulse25":
				v = 1.0 if i < 8 else -1.0
			"square":
				v = 1.0 if i < 16 else -1.0
			"saw":
				v = 1.0 - 2.0 * t
			"triangle":
				v = 1.0 - 4.0 * absf(t - 0.5)
			"sine":
				v = sin(TAU * t)
			"organ":
				v = (sin(TAU * t) + 0.5 * sin(2.0 * TAU * t) + 0.25 * sin(4.0 * TAU * t)) / 1.4
			"soft_square":
				v = clampf(1.6 * sin(TAU * t), -1.0, 1.0)
			_:
				v = 1.0 if i < 16 else -1.0
		out.append(clampi(roundi(15.5 + 15.5 * v), 0, 31))
	return out


## Index of [param wave_name] in [member waves], adding it if needed.
func wave_index(wave_name: String) -> int:
	var i := wave_names.find(wave_name)
	if i >= 0:
		return i
	wave_names.append(wave_name)
	waves.append(make_wave(wave_name))
	return waves.size() - 1


## The frame each row starts on, and the total, as the C player counts.
func total_frames() -> int:
	return frames_before(row_count)
