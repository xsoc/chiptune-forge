class_name SpeakerSong
extends NesSong
## A song arranged for the PC speaker: one square wave, on or off, at the
## pitch the timer chip (the 8253 PIT) divides from 1.19 MHz.
##
## Three parts take turns on it: the lead, the bass and the drums. The
## driver runs at 70 Hz and plays two tones a frame, each 1/140 s: while the
## lead and bass both sound it alternates between them (the fast arpeggio
## DOS games used for chords on one voice), and a drum hit takes over both
## for as long as it lasts. [SpeakerArranger] makes one from a [ChipSong].

const CHANNEL_NAMES_SPEAKER: PackedStringArray = ["Lead", "Bass", "Drums"]
const LEAD := 0
const BASS := 1
const DRUMS := 2
## Driver frames per second, and tones per frame.
const FRAME_HZ := 70.0
const SLOTS := 2
## The PIT's input clock.
const PIT_HZ := 1193182.0
const LOWEST := 36
const HIGHEST := 96

var card := "speaker"


func _init() -> void:
	frame_hz = FRAME_HZ
	notes = [[], [], []]


func channel_names() -> PackedStringArray:
	return CHANNEL_NAMES_SPEAKER


## The PIT divisor for a frequency (0 is silence).
static func divisor_of(hz: float) -> int:
	if hz <= 0.0:
		return 0
	return clampi(roundi(PIT_HZ / hz), 2, 65535)


static func midi_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)
