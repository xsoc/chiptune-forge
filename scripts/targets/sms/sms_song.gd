class_name SmsSong
extends NesSong
## A song arranged for the Master System and Game Gear's SN76489: three
## square channels and a noise channel.
##
## It keeps [NesSong]'s rows, groove, notes, instruments and arpeggios, with
## these differences:[br]
## - A note on a square channel is a MIDI note number.[br]
## - A note on the noise channel is the noise rate, 0 (highest) to 2.[br]
## - Volumes and volume envelopes are levels from 0 (silent) to 15 (full) in
##   the chip's 2 dB steps, and they add up as attenuations do.[br]
## - Pitch envelopes are in tone period steps. A duty envelope on the noise
##   channel picks white noise (1, the default) or periodic noise (0).[br]
## [SmsArranger] makes one, [SmsPlayer] plays it, and [PsgWriter] writes it
## as PSGlib data.

const SMS_CHANNEL_NAMES: PackedStringArray = ["Square 1", "Square 2", "Square 3", "Noise"]
const SQUARE1 := 0
const SQUARE2 := 1
const SQUARE3 := 2
## NTSC frame rate, which drives PSGlib's PSGFrame.
const FRAME_HZ := 59.922743
## Lowest note: a 10-bit tone period reaches down to about 109 Hz (A2).
const LOWEST_NOTE := 45
const HIGHEST_NOTE := 108


func _init() -> void:
	frame_hz = FRAME_HZ


## The tone period for a MIDI note.
static func tone_period(midi: int) -> int:
	var hz := 440.0 * pow(2.0, (midi - 69) / 12.0)
	return clampi(roundi(SmsPsg.CLOCK / (32.0 * hz)), 1, 1023)


## A MIDI note moved by octaves into the chip's range. Returns {note, moved}.
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


## A linear volume (0 to 15, as on the NES or Game Boy) as the nearest
## SN76489 level. Anything audible stays at least 1.
static func level_of(volume: float) -> int:
	if volume <= 0.0:
		return 0
	var db := 20.0 * log(volume / 15.0) / log(10.0)
	return clampi(15 + roundi(db / 2.0), 1, 15)


## A note's volume and its envelope combined: attenuations add, so levels
## add less 15.
static func mix_level(note_level: int, envelope: int) -> int:
	if note_level <= 0 or envelope <= 0:
		return 0
	return maxi(note_level + envelope - 15, 0)
