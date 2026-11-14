class_name MdSequencer
extends NesSequencer
## Plays an [MdSong] the way a Mega Drive would: [MdPlayer] writes the
## YM2612 and SN76489 registers once per video frame, and [MdSound] turns
## them into sound. Everything else (timing, loops, mutes, fades, meters)
## works as in [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = MdSound.new(float(rate))
	driver = MdPlayer.new(nes, apu)


func _output_gain() -> float:
	return 1.5
