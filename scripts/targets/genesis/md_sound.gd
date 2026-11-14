class_name MdSound
extends RefCounted
## The Mega Drive's two sound chips together, as a driver sees them: the
## YM2612 ([Ym2612]) on ports $4000 to $4003 and the SN76489 ([SmsPsg]) on
## port $C00011. [MdPlayer] writes both once per frame; [method render]
## mixes them.

## The PSG's level against the FM in the mix: on the console it is clearly
## quieter than an FM channel at full volume.
const PSG_MIX := 0.6

var fm: Ym2612
var psg: SmsPsg
## Per-channel gain for previews, in [MdSong] channel order (FM 1 to 6,
## then the PSG's four).
var channel_gain := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]):
	set(value):
		channel_gain = value
		_apply_gains()

var _psg_buffer := PackedFloat32Array()


func _init(rate := 44100.0) -> void:
	fm = Ym2612.new(rate)
	psg = SmsPsg.new(rate)


func reset() -> void:
	fm.reset()
	psg.reset()


func fm_write(port: int, reg: int, value: int) -> void:
	fm.write(port, reg, value)


func psg_write(value: int) -> void:
	psg.write(value)


## Sets one channel's preview gain. The gain array is copied on read in
## GDScript, so callers use this rather than writing into it.
func set_gain(channel: int, gain: float) -> void:
	channel_gain[channel] = gain
	_apply_gains()


func _apply_gains() -> void:
	for c in 6:
		fm.channel_gain[c] = channel_gain[c]
	for c in 4:
		psg.channel_gain[c] = channel_gain[6 + c]


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	if _psg_buffer.size() < count:
		_psg_buffer.resize(count)
	psg.render(_psg_buffer, 0, count)
	for i in count:
		out[offset + i] = _psg_buffer[i] * PSG_MIX
	fm.render(out, offset, count)
