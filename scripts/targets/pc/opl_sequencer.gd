class_name OplSequencer
extends NesSequencer
## Plays an [OplSong] the way a PC sound card would: [OplPlayer] writes the
## OPL's registers 70 times a second and [OplSound] turns them into sound.
## Everything else (timing, loops, mutes, fades, meters) works as in
## [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = OplSound.new(nes, float(rate))
	driver = OplPlayer.new(nes, apu)


func _output_gain() -> float:
	return 1.2
