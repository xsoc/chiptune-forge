class_name SmsSequencer
extends NesSequencer
## Plays an [SmsSong] the way a Master System would: [SmsPlayer] writes the
## same bytes PSGlib would once per video frame, and [SmsPsg] turns them into
## sound. Everything else (timing, loops, mutes, fades, meters) works as in
## [NesSequencer].


func _make_chip(rate: int) -> void:
	apu = SmsPsg.new(float(rate))
	driver = SmsPlayer.new(nes, apu)


func _output_gain() -> float:
	return 0.7
