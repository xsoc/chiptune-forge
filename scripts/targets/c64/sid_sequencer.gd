class_name SidSequencer
extends NesSequencer
## Plays a [SidSong] the way a Commodore 64 would: [SidPlayer] sets the same
## registers our 6502 player does once per frame, and [SidChip] turns them
## into sound. Everything else (timing, loops, mutes, fades, meters) works
## as in [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = SidChip.new(float(rate))
	driver = SidPlayer.new(nes, apu)


func _output_gain() -> float:
	return 1.6
