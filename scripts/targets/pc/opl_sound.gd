class_name OplSound
extends RefCounted
## The FM chip of a PC sound card as a driver sees it: one OPL2 (AdLib,
## Sound Blaster), two OPL2s with one on each speaker (Sound Blaster Pro),
## or an OPL3 (Sound Blaster 16). [OplPlayer] writes it once per frame and
## [method render] mixes it.
##
## Previews play in mono, as every other target's do: the two speakers are
## averaged.

var chips: Array[Opl] = []
var layout: Array = []
var dual := false
## Per-voice gain for previews, in [member OplSong.layout] order.
var channel_gain := PackedFloat32Array():
	set(value):
		channel_gain = value
		_apply_gains()

var _left := PackedFloat32Array()
var _right := PackedFloat32Array()


func _init(song: OplSong, rate := 44100.0) -> void:
	layout = song.layout
	dual = song.chip == "dual_opl2"
	chips.append(Opl.new(rate, song.chip == "opl3"))
	if dual:
		chips.append(Opl.new(rate))
	channel_gain.resize(layout.size())
	channel_gain.fill(1.0)


func reset() -> void:
	for c in chips:
		c.reset()
	_apply_gains()


## Writes a register: [param bank] is the chip on the Sound Blaster Pro and
## the register bank on the OPL3.
func write(bank: int, reg: int, value: int) -> void:
	if dual:
		chips[bank & 1].write(0, reg, value)
	else:
		chips[0].write(bank, reg, value)


func set_gain(channel: int, gain: float) -> void:
	channel_gain[channel] = gain
	_apply_gains()


func _apply_gains() -> void:
	for chip in chips:
		chip.channel_gain.fill(0.0)
	for i in layout.size():
		var v: Dictionary = layout[i]
		var bank := int(v["bank"])
		var chip: Opl = chips[bank if dual else 0]
		var base := 0 if dual else bank * 9
		if str(v["drum"]) != "":
			for c in [6, 7, 8]:
				chip.channel_gain[base + c] = maxf(chip.channel_gain[base + c], channel_gain[i])
		else:
			var c := base + int(v["ch"])
			chip.channel_gain[c] = maxf(chip.channel_gain[c], channel_gain[i])


func render(out: PackedFloat32Array, offset: int, count: int) -> void:
	if _left.size() < count:
		_left.resize(count)
		_right.resize(count)
	_left.fill(0.0)
	_right.fill(0.0)
	if dual:
		chips[0].render(_left, _left, 0, count)
		chips[1].render(_right, _right, 0, count)
		for i in count:
			out[offset + i] = (_left[i] + _right[i]) * 0.25
	else:
		chips[0].render(_left, _right, 0, count)
		for i in count:
			out[offset + i] = (_left[i] + _right[i]) * 0.5
