class_name MdPlayer
extends NesPlayer
## Plays an [MdSong] one video frame at a time, writing the YM2612's and the
## SN76489's registers, the way a frame-based Mega Drive driver does.
##
## Notes, durations, arpeggios and envelopes work as in [NesPlayer]. On an
## FM channel a new note loads the instrument's patch if the channel holds
## another one, sets the pitch, and keys the operators off and on again;
## a note that ends keys them off, so the patch's own release plays. The
## note's level (with any volume envelope) lowers the carriers' total level.
## The PSG channels work exactly as in [SmsPlayer]. Each frame only writes
## registers that changed, so recording the writes gives a compact VGM file
## ([MdVgmWriter]).

## Channels this player may write, as a bit mask over [MdSong] channels.
var channel_mask := 0x3FF

# FM: per channel, the instrument whose patch is loaded (-1 none), the last
# A4/A0 values and carrier attenuation written, and whether keyed.
var _patch := PackedInt32Array()
var _inst_index := PackedInt32Array([-1, -1, -1, -1, -1, -1])
var _sent_freq := PackedInt32Array()
var _sent_atten := PackedInt32Array()
var _keyed := PackedByteArray()
var _key_now := PackedByteArray()
# PSG, as in SmsPlayer: per tone channel the period, per channel the level.
var _sent_period := PackedInt32Array()
var _sent_level := PackedInt32Array()
var _sent_noise := -1
var _retrigger := false


func _reset_chip() -> void:
	apu.reset()
	invalidate()
	# LFO off, channel 3 in normal mode, timers off, DAC off.
	apu.fm_write(0, 0x22, 0x00)
	apu.fm_write(0, 0x27, 0x00)
	apu.fm_write(0, 0x2B, 0x00)
	for c in 6:
		if channel_mask & (1 << c):
			apu.fm_write(0, 0x28, _key_code(c))


## Forgets what the chips hold, so the next frame writes every register
## again (patches included). Used at the loop point.
func invalidate() -> void:
	_patch = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	_sent_freq = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	_sent_atten = PackedInt32Array([-1, -1, -1, -1, -1, -1])
	_keyed = PackedByteArray([0, 0, 0, 0, 0, 0])
	_key_now = PackedByteArray([0, 0, 0, 0, 0, 0])
	_sent_period = PackedInt32Array([-1, -1, -1])
	_sent_level = PackedInt32Array([-1, -1, -1, -1])
	_sent_noise = -1


## The 0x28 register's channel field: 0 to 2, then 4 to 6.
static func _key_code(channel: int) -> int:
	return channel if channel < 3 else channel + 1


func _attack(channel: int, n: Dictionary) -> void:
	super(channel, n)
	if MdSong.is_fm(channel):
		_inst_index[channel] = int(n["instrument"])
		_key_now[channel] = 1
	elif channel == MdSong.MD_NOISE:
		_retrigger = true


func _output(channel: int) -> void:
	if not (channel_mask & (1 << channel)):
		return
	if MdSong.is_fm(channel):
		_output_fm(channel)
	else:
		_output_psg(channel - MdSong.SQUARE1)


func _output_fm(channel: int) -> void:
	var ch = _ch[channel]
	var port := channel / 3
	var reg := channel % 3
	if ch.note <= 0:
		if _keyed[channel]:
			apu.fm_write(0, 0x28, _key_code(channel))
			_keyed[channel] = 0
		_key_now[channel] = 0
		return
	var inst: Dictionary = ch.instrument
	var patch: Dictionary = inst.get("fm", {})
	if patch.is_empty():
		return
	var level := SmsSong.mix_level(ch.volume, ch.value("volume", 15))
	var atten := MdSong.level_atten(level)
	var index := _inst_index[channel]
	if _patch[channel] != index:
		# Key off before loading, so the old note doesn't take the new sound.
		if _keyed[channel]:
			apu.fm_write(0, 0x28, _key_code(channel))
			_keyed[channel] = 0
		for w in MdSong.patch_registers(channel, patch, atten):
			apu.fm_write(w[0], w[1], w[2])
		_patch[channel] = index
		_sent_atten[channel] = atten
	elif atten != _sent_atten[channel]:
		var carriers: Array = Ym2612.ROUTES[int(patch["alg"])][1]
		for slot in 4:
			var op: int = Ym2612.SLOT_OPERATOR[slot]
			if carriers[op]:
				apu.fm_write(port, 0x40 + reg + slot * 4, MdSong.operator_tl(patch, op, atten))
		_sent_atten[channel] = atten
	var midi := clampf(ch.note + ch.arp_value(), 0.0, 127.0) + ch.value("pitch", 0) / 100.0
	var bf := MdSong.fm_pitch(MdSong.midi_hz(midi))
	var freq := (bf[0] << 11) | bf[1]
	if freq != _sent_freq[channel]:
		# The high byte first: it is latched until the low byte arrives.
		apu.fm_write(port, 0xA4 + reg, freq >> 8)
		apu.fm_write(port, 0xA0 + reg, freq & 0xFF)
		_sent_freq[channel] = freq
	if _key_now[channel]:
		if _keyed[channel]:
			apu.fm_write(0, 0x28, _key_code(channel))
		apu.fm_write(0, 0x28, 0xF0 | _key_code(channel))
		_keyed[channel] = 1
		_key_now[channel] = 0


func _output_psg(psg_channel: int) -> void:
	var ch = _ch[psg_channel + MdSong.SQUARE1]
	var level := SmsSong.mix_level(ch.volume, ch.value("volume", 15)) if ch.note > 0 else 0
	var latch := psg_channel << 5
	if psg_channel < 3:
		if ch.note > 0:
			var midi := clampi(ch.note + ch.arp_value(), 0, 127)
			var period := clampi(SmsSong.tone_period(midi) + ch.value("pitch", 0), 1, 1023)
			var sent := _sent_period[psg_channel]
			if period != sent:
				apu.psg_write(0x80 | latch | (period & 0x0F))
				if sent < 0 or (period >> 4) != (sent >> 4):
					apu.psg_write(period >> 4)
				_sent_period[psg_channel] = period
	elif ch.note > 0:
		var rate := clampi(ch.note + ch.arp_value(), 0, 2)
		var control := ((ch.value("duty", 1) & 1) << 2) | rate
		if control != _sent_noise or _retrigger:
			apu.psg_write(0xE0 | control)
			_sent_noise = control
		_retrigger = false
	if level != _sent_level[psg_channel]:
		apu.psg_write(0x90 | latch | (15 - level))
		_sent_level[psg_channel] = level


func get_channel_volume(channel: int) -> int:
	var ch = _ch[channel]
	if ch.note <= 0:
		return 0
	return SmsSong.mix_level(ch.volume, ch.value("volume", 15))
