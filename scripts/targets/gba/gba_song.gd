class_name GbaSong
extends SnesSong
## A song arranged for the Game Boy Advance, as an Impulse Tracker module for
## Maxmod, devkitPro's sound library, which mixes sampled channels into the
## GBA's two Direct Sound PCM channels.
##
## It is the SNES arrangement ([SnesSong]: eight channels, channel 8 left
## free for sound effects) with these differences: ticks run at Impulse
## Tracker's own rate (tempo x 0.4 a second), there is no echo, and samples
## are 8-bit, as Maxmod mixes them.

## The rate Maxmod mixes at with mmInitDefault.
const MIX_HZ := 16384


func _init() -> void:
	super()
	standard_ticks = true
	frame_hz = tick_hz(tempo, true)
