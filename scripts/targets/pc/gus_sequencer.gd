class_name GusSequencer
extends NesSequencer
## Plays a [GusSong] the way a Gravis Ultrasound would: [GbaPlayer] runs the
## module's logic once per tick, as Impulse Tracker does, and [GusMixer]
## plays the voices as the GF1 chip does.


func _make_chip(rate: int) -> void:
	apu = GusMixer.new(float(rate))
	driver = GbaPlayer.new(nes, apu)


func _output_gain() -> float:
	return 0.9
