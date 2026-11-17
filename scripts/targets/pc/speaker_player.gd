class_name SpeakerPlayer
extends NesPlayer
## Plays a [SpeakerSong] at 70 Hz the way a DOS game drives the PC speaker:
## each frame it works out two PIT divisors, one per 1/140 s, and hands them
## to the speaker ([SpeakerSound], or a recorder for export).
##
## Notes, durations, arpeggios and envelopes work as in [NesPlayer]; a note
## sounds while its volume is at least [constant SpeakerArranger.GATE].
## Drums sound as noise (random divisors) for hats and snares, and as a
## falling tone for kicks and toms.

# Per channel this frame: MIDI pitch (0 for silence), and for drums the
# noise period index and how many frames the hit has played.
var _pitch := PackedFloat32Array([0.0, 0.0, 0.0])
var _drum_index := 0
var _drum_age := 0
var _rng := 0x1234


func _init(song: SpeakerSong, sound: Variant) -> void:
	super(song, sound)


func _reset_chip() -> void:
	apu.reset()
	_rng = 0x1234
	_pitch.fill(0.0)


func tick() -> void:
	_pitch.fill(0.0)
	super()
	var gains: PackedFloat32Array = apu.channel_gain
	var slots := PackedInt32Array([0, 0])
	if _pitch[SpeakerSong.DRUMS] > 0.0 and gains[SpeakerSong.DRUMS] > 0.01:
		for s in SpeakerSong.SLOTS:
			slots[s] = _drum_divisor()
		_drum_age += 1
	else:
		var lead := _pitch[SpeakerSong.LEAD] if gains[SpeakerSong.LEAD] > 0.01 else 0.0
		var bass := _pitch[SpeakerSong.BASS] if gains[SpeakerSong.BASS] > 0.01 else 0.0
		var a := lead if lead > 0.0 else bass
		var b := bass if bass > 0.0 else lead
		slots[0] = SpeakerSong.divisor_of(SpeakerSong.midi_hz(a)) if a > 0.0 else 0
		slots[1] = SpeakerSong.divisor_of(SpeakerSong.midi_hz(b)) if b > 0.0 else 0
	apu.write_frame(slots[0], slots[1])


func _attack(channel: int, n: Dictionary) -> void:
	super(channel, n)
	if channel == SpeakerSong.DRUMS:
		_drum_age = 0


func _output(channel: int) -> void:
	var ch = _ch[channel]
	if ch.note <= 0:
		return
	var level := NesSong.mix_volume(ch.volume, ch.value("volume", 15))
	if level < SpeakerArranger.GATE:
		return
	if channel == SpeakerSong.DRUMS:
		_drum_index = 15 - clampi(ch.note + ch.arp_value() - 16, 0, 15)
		_pitch[channel] = 1.0
	else:
		_pitch[channel] = clampf(ch.note + ch.arp_value(), 12.0, 120.0)


## The next divisor of the current drum: noise for bright drums, a falling
## tone for dark ones.
func _drum_divisor() -> int:
	_rng = (_rng * 1103515245 + 12345) & 0x7FFFFFFF
	var r := float((_rng >> 8) & 0xFFFF) / 65535.0
	if _drum_index >= 9:
		# Kicks and toms: a tone falling from about 200 Hz.
		var start := 220.0 if _drum_index >= 10 else 330.0
		return SpeakerSong.divisor_of(start * pow(0.72, _drum_age + r * 0.5))
	if _drum_index >= 5:
		# Snares: noise from 1 to 5 kHz.
		return SpeakerSong.divisor_of(1000.0 + r * 4000.0)
	# Hats and cymbals: noise from 5 to 15 kHz.
	return SpeakerSong.divisor_of(5000.0 + r * 10000.0)


func get_channel_volume(channel: int) -> int:
	var ch = _ch[channel]
	if ch.note <= 0:
		return 0
	return 15 if NesSong.mix_volume(ch.volume, ch.value("volume", 15)) >= SpeakerArranger.GATE else 0
