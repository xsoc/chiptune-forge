class_name SpeakerSequencer
extends NesSequencer
## Plays a [SpeakerSong] the way a DOS PC would: [SpeakerPlayer] picks the
## speaker's pitch 140 times a second and [SpeakerSound] turns it into
## sound. Everything else works as in [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = SpeakerSound.new(float(rate))
	driver = SpeakerPlayer.new(nes, apu)


func _output_gain() -> float:
	return 0.8
