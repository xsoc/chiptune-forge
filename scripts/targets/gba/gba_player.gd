class_name GbaPlayer
extends SnesPlayer
## Plays a [GbaSong]'s tracker rows one tick at a time, as Maxmod plays an
## Impulse Tracker module: the same row and effect logic as [SnesPlayer],
## on 8-bit samples straight from the module, with no echo.


func _reset_chip() -> void:
	apu.reset()
	apu.write(SnesDsp.MVOLL, 80)
	apu.write(SnesDsp.MVOLR, 80)
	for i in song.samples.size():
		var sample := SnesSamples.get_sample(song.samples[i])
		var looped := int(sample["loop_length"]) > 0
		apu.set_source(i, {"pcm": sample["pcm"], "loop": int(sample["loop_start"]) if looped else -1})
	apu.write(SnesDsp.FLG, SnesDsp.FLG_ECEN)
	apu.write(SnesDsp.EVOLL, 0)
	apu.write(SnesDsp.EVOLR, 0)
