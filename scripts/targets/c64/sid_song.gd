class_name SidSong
extends NesSong
## A song arranged for the Commodore 64's SID: three voices, each with its
## own waveform and ADSR envelope.
##
## It keeps [NesSong]'s four channels, rows, groove, notes and arpeggios,
## with these differences:[br]
## - Lead, accompaniment and bass notes are MIDI note numbers, played on
##   voices 1, 2 and 3.[br]
## - Drum notes stay NES noise notes (16 to 31, 31 the highest); the player
##   turns them into noise frequencies. Drums play on voice 2, which leaves
##   the accompaniment for as long as a drum sounds.[br]
## - An instrument has a waveform ("pulse", "saw", "triangle" or "noise"),
##   the SID's attack/decay and sustain/release bytes ("ad", "sr"), a pulse
##   width ("pw", 0 to 4095) or a duty envelope (NES duty codes), and pitch
##   and arpeggio envelopes as on the NES. Its NES volume envelope stays,
##   for how long a drum holds voice 2.[br]
## - A note's volume (0 to 15) scales its instrument's sustain level.[br]
## [SidArranger] makes one, [SidPlayer] plays it, and [SidWriter] writes it.

const SID_CHANNEL_NAMES: PackedStringArray = ["Lead (voice 1)", "Accompaniment (voice 2)", "Bass (voice 3)", "Drums (voice 2)"]
const LEAD := 0
const ACCOMP := 1
const BASS := 2
const DRUMS := 3
## The voice each part plays on.
const VOICE_OF := [0, 1, 2, 1]
## PAL frame rate.
const FRAME_HZ := 50.1245
const LOWEST_NOTE := 24
const HIGHEST_NOTE := 103
## Attack times (ms) for each attack rate, and decay and release times.
const ATTACK_MS := [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000]
const DECAY_MS := [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000]
const DUTY_WIDTHS := [512, 1024, 2048, 3072]


func _init() -> void:
	frame_hz = FRAME_HZ


## The frequency register value for a MIDI note.
static func note_freq(midi: int) -> int:
	return freq_of_hz(440.0 * pow(2.0, (midi - 69) / 12.0))


static func freq_of_hz(hz: float) -> int:
	return clampi(roundi(hz * 16777216.0 / SidChip.CLOCK), 1, 65535)


## The noise frequency register value for an NES noise period index (0 the
## highest, 15 the lowest), at about the same rate.
static func noise_freq(index: int) -> int:
	var rate := NesApu.CPU_HZ / float(NesApu.NOISE_PERIODS[clampi(index, 0, 15)])
	# The SID's noise steps 16 times per oscillator cycle.
	return freq_of_hz(rate / 16.0)


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


static func _nearest(table: Array, ms: float) -> int:
	var best := 0
	for i in table.size():
		if absf(float(table[i]) - ms) < absf(float(table[best]) - ms):
			best = i
	return best


## The SID envelope closest to an NES volume envelope (values 0 to 15 at
## [param fps] frames a second). Returns [ad, sr].
static func adsr_of(volume: Array, loop := -1, fps := 60.0) -> PackedInt32Array:
	if volume.is_empty():
		return PackedInt32Array([0x00, 0xF2])
	var peak := 0
	var peak_at := 0
	for i in volume.size():
		if int(volume[i]) > peak:
			peak = int(volume[i])
			peak_at = i
	if peak <= 0:
		return PackedInt32Array([0x00, 0x00])
	var held := int(volume[loop]) if loop >= 0 and loop < volume.size() else int(volume[volume.size() - 1])
	var sustain := clampi(roundi(held * 15.0 / peak), 0, 15)
	var attack := 0 if peak_at == 0 else _nearest(ATTACK_MS, peak_at * 1000.0 / fps)
	# How long the envelope takes from its peak to (nearly) where it holds.
	var target := held + (peak - held) * 0.1
	var frames := 0
	for i in range(peak_at, volume.size()):
		if float(volume[i]) <= target:
			break
		frames += 1
	var decay := 0
	if sustain < 15:
		var fraction := 1.0 - sustain / 15.0
		decay = _nearest(DECAY_MS.map(func(ms: int) -> float: return ms * fraction), maxf(frames, 1) * 1000.0 / fps)
	var release := decay if sustain == 0 else 2
	return PackedInt32Array([(attack << 4) | decay, (sustain << 4) | release])
