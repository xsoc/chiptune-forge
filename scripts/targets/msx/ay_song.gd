class_name AySong
extends NesSong
## A song arranged for the AY-3-8910 of the MSX and ZX Spectrum 128: three
## square channels and a noise generator.
##
## It keeps [NesSong]'s four channels, rows, groove, notes, instruments and
## arpeggios, with these differences:[br]
## - Lead, accompaniment and bass notes are MIDI note numbers, played on
##   channels A, B and C.[br]
## - Drum notes stay NES noise notes (16 to 31, 31 the highest); the player
##   turns them into the chip's noise periods. Drums play on channel B,
##   which leaves the accompaniment for as long as a drum sounds.[br]
## - Volumes and volume envelopes are the chip's levels, 0 (silent) to 15,
##   and they add up as attenuations do.[br]
## - Pitch envelopes are in tone period steps.[br]
## [AyArranger] makes one, [AyPlayer] plays it, and [AyWriter] writes it.

const AY_CHANNEL_NAMES: PackedStringArray = ["Lead (A)", "Accompaniment (B)", "Bass (C)", "Drums (B)"]
const LEAD := 0
const ACCOMP := 1
const BASS := 2
const DRUMS := 3
## The player runs at 50 frames a second on both machines (a 60 Hz MSX
## skips every sixth interrupt).
const FRAME_HZ := 50.0
const LOWEST_NOTE := 24
const HIGHEST_NOTE := 108


func _init() -> void:
	frame_hz = FRAME_HZ


## The tone period for a MIDI note on a chip running at [param clock].
static func tone_period(midi: int, clock := AyPsg.CLOCK_MSX) -> int:
	var hz := 440.0 * pow(2.0, (midi - 69) / 12.0)
	return clampi(roundi(clock / (16.0 * hz)), 1, 4095)


## The chip's noise period (1 to 31) for an NES noise period index (0 the
## highest, 15 the lowest), at about the same rate.
static func noise_period(index: int) -> int:
	return clampi(roundi(NesApu.NOISE_PERIODS[clampi(index, 0, 15)] / 16.0), 1, 31)


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


## A linear volume (0 to 15, as on the NES) as the chip level of nearest
## loudness. Anything audible stays at least 1.
static func level_of(volume: float) -> int:
	if volume <= 0.0:
		return 0
	var want := volume / 15.0
	var best := 1
	for level in range(1, 16):
		if absf(AyPsg.LEVELS[level] - want) < absf(AyPsg.LEVELS[best] - want):
			best = level
	return best


## A note's volume and its envelope combined: attenuations add, so levels
## add less 15.
static func mix_level(note_level: int, envelope: int) -> int:
	if note_level <= 0 or envelope <= 0:
		return 0
	return maxi(note_level + envelope - 15, 0)
