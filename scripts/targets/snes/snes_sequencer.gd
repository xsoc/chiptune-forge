class_name SnesSequencer
extends NesSequencer
## Plays a [SnesSong] the way a SNES would: [SnesPlayer] runs SNESMod's
## logic once per tick and [SnesDsp] turns its register writes into sound.
## Everything else (timing, loops, mutes, fades, meters) works as in
## [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = SnesDsp.new(float(rate))
	driver = SnesPlayer.new(nes, apu)


func _output_gain() -> float:
	return 2.4
