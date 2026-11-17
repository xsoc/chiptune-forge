class_name PceSequencer
extends NesSequencer
## Plays a [PceSong] the way a PC Engine would: [PcePlayer] writes the PSG's
## registers once per video frame, as our C player does, and [PcePsg] turns
## them into sound. Everything else (timing, loops, mutes, fades, meters)
## works as in [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = PcePsg.new(float(rate))
	driver = PcePlayer.new(nes, apu)


func _output_gain() -> float:
	return 1.6
