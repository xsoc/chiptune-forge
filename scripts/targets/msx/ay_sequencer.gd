class_name AySequencer
extends NesSequencer
## Plays an [AySong] the way an MSX or ZX Spectrum 128 would: [AyPlayer]
## sets the same registers our Z80 player does once per frame, and [AyPsg]
## turns them into sound. Everything else (timing, loops, mutes, fades,
## meters) works as in [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = AyPsg.new(float(rate))
	driver = AyPlayer.new(nes, apu)


func _output_gain() -> float:
	return 1.4
