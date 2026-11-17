class_name GbaSequencer
extends NesSequencer
## Plays a [GbaSong] the way a Game Boy Advance would: [GbaPlayer] runs the
## module's logic once per tick and [GbaMixer] mixes it as Maxmod does.
## Everything else (timing, loops, mutes, fades, meters) works as in
## [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = GbaMixer.new(float(rate))
	driver = GbaPlayer.new(nes, apu)


func _output_gain() -> float:
	return 2.4
