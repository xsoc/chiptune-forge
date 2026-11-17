class_name AyPlayer
extends NesPlayer
## Plays an [AySong] one frame at a time, setting the AY-3-8910's registers.
##
## Notes, durations, arpeggios and envelopes work as in [NesPlayer]. Each
## frame it works out registers 0 to 10 (tone periods, noise period, mixer
## and volumes) and writes them all, which is what our Z80 player does with
## the exported data: [AyWriter] records these register values frame by
## frame.
##
## Channel A plays the lead and C the bass. Channel B plays the drums (noise
## only) while a drum sounds, and the accompaniment the rest of the time.

## The registers the player sets each frame.
const PLAYED_REGISTERS := 11

## Parts this player may play, as a bit mask over the song's four channels.
## A sound effect plays only its own, and only its registers change.
var channel_mask := 0x0F
## The chip clock the tone periods are worked out for.
var clock := AyPsg.CLOCK_MSX
## The register values set on the last frame.
var regs := PackedInt32Array()


func _reset_chip() -> void:
	apu.reset()
	regs = PackedInt32Array()
	regs.resize(PLAYED_REGISTERS)
	regs[AyPsg.MIXER] = 0xBF


func _output(channel: int) -> void:
	# All four parts are worked out together once the last one has moved.
	if channel == _count - 1:
		_update()


func _update() -> void:
	var mixer := regs[AyPsg.MIXER]
	if channel_mask & (1 << AySong.LEAD):
		mixer = _tone(AySong.LEAD, 0, mixer)
	if channel_mask & (1 << AySong.BASS):
		mixer = _tone(AySong.BASS, 2, mixer)
	if channel_mask & ((1 << AySong.ACCOMP) | (1 << AySong.DRUMS)):
		var drums := _ch[AySong.DRUMS]
		var level := AySong.mix_level(drums.volume, drums.value("volume", 15)) if drums.note > 0 else 0
		if level > 0 and (channel_mask & (1 << AySong.DRUMS)):
			var index := ((drums.note + drums.arp_value()) & 0x0F) ^ 0x0F
			regs[AyPsg.NOISE] = AySong.noise_period(index)
			regs[9] = level
			# Noise on, tone off.
			mixer = (mixer | 0x02) & ~0x10
		elif channel_mask & (1 << AySong.ACCOMP):
			mixer = _tone(AySong.ACCOMP, 1, mixer)
		else:
			regs[9] = 0
			mixer |= 0x12
	regs[AyPsg.MIXER] = mixer
	for r in PLAYED_REGISTERS:
		apu.write(r, regs[r])


## Sets channel [param voice] for the part on [param channel]. Returns the
## new mixer value.
func _tone(channel: int, voice: int, mixer: int) -> int:
	var ch := _ch[channel]
	var level := AySong.mix_level(ch.volume, ch.value("volume", 15)) if ch.note > 0 else 0
	if ch.note > 0:
		var midi := clampi(ch.note + ch.arp_value(), 0, 127)
		var period := clampi(AySong.tone_period(midi, clock) + ch.value("pitch", 0), 1, 4095)
		regs[voice * 2] = period & 0xFF
		regs[voice * 2 + 1] = period >> 8
	regs[8 + voice] = level
	# Tone on, noise off.
	return (mixer & ~(1 << voice)) | (8 << voice)


func get_channel_volume(channel: int) -> int:
	var ch := _ch[channel]
	if ch.note <= 0:
		return 0
	return AySong.mix_level(ch.volume, ch.value("volume", 15))
