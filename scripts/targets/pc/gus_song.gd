class_name GusSong
extends SnesSong
## A song arranged for the Gravis Ultrasound, as an Impulse Tracker module:
## the GUS's GF1 chip plays up to 32 sample voices from its own memory, with
## 16-bit samples, linear interpolation and 16 pan positions, and Impulse
## Tracker (and the DOS players games used, such as MIDAS) drive it
## directly.
##
## It is the SNES arrangement ([SnesSong]) on 16-bit samples at Impulse
## Tracker's own tick rate, with no echo (the GUS has none).

## The GF1's output rate with 14 voices active, the most that still give
## 44.1 kHz.
const MIX_HZ := 44100
## Its memory, in bytes: 256 KB on the first boards, 1 MB fully expanded.
const RAM_BYTES := 1048576


func _init() -> void:
	super()
	standard_ticks = true
	frame_hz = tick_hz(tempo, true)
