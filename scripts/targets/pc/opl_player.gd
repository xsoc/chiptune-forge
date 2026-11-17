class_name OplPlayer
extends NesPlayer
## Plays an [OplSong] at 70 Hz, writing the OPL's registers the way a DOS
## music driver does.
##
## Notes, durations, arpeggios and envelopes work as in [NesPlayer]. On a
## melodic channel a new note loads the instrument's patch if the channel
## holds another one, sets the pitch, and keys the channel off and on again
## (so the envelope restarts); a note that ends keys it off, so the patch's
## own release plays. The note's level lowers the carrier's total level.
## Drums key their bits in register $BD, clearing and setting a bit to
## strike again. Each frame only writes registers that changed, so
## recording the writes gives compact IMF, DRO and VGM files.

const BD_REG := 0xBD
## Pitches of the rhythm channels: the bass drum's, the hi-hat and snare's,
## and (until a tom note sets it) the tom and cymbal's.
const BD_NOTE := 36
const HH_SD_NOTE := 79
const TOM_NOTE := 55

var opl: OplSong
var _patch := PackedInt32Array()
var _sent_freq := PackedInt32Array()
var _sent_level := PackedInt32Array()
var _keyed := PackedByteArray()
var _key_now := PackedByteArray()
# Per bank: drum key bits now, bits to strike again this frame, and the
# value last written to $BD.
var _drum_on := PackedInt32Array([0, 0])
var _strike := PackedInt32Array([0, 0])
var _sent_bd := PackedInt32Array([-1, -1])
var _tom_freq := PackedInt32Array([-1, -1])
var _drums_dirty := false


func _init(song: OplSong, sound: Variant) -> void:
	opl = song
	var n := song.layout.size()
	_patch.resize(n)
	_sent_freq.resize(n)
	_sent_level.resize(n)
	_keyed.resize(n)
	_key_now.resize(n)
	super(song, sound)


func _reset_chip() -> void:
	apu.reset()
	invalidate()
	var banks := 2 if opl.chip != "opl2" else 1
	if opl.chip == "opl3":
		apu.write(1, 0x05, 0x01)
	for bank in banks:
		if opl.chip == "opl3" and bank == 1:
			continue
		# Waveform select on; note select 0.
		apu.write(bank, 0x01, 0x20)
		apu.write(bank, 0x08, 0x00)
	_reload_drums()


func _reload_drums() -> void:
	for bank in 2:
		if opl.rhythm_on(bank):
			_load_drums(bank)
	_drums_dirty = false


## Forgets what the chips hold, so the next frame writes every register
## again (patches included). Used at the loop point.
func invalidate() -> void:
	_patch.fill(-1)
	_sent_freq.fill(-1)
	_sent_level.fill(-1)
	_keyed.fill(0)
	_key_now.fill(0)
	_drum_on = PackedInt32Array([0, 0])
	_strike = PackedInt32Array([0, 0])
	_sent_bd = PackedInt32Array([-1, -1])
	_tom_freq = PackedInt32Array([-1, -1])
	_drums_dirty = true


## Loads the rhythm mode's patches and pitches into channels 7 to 9.
func _load_drums(bank: int) -> void:
	var pan := _pan_bits("LR")
	for w in OplSong.patch_registers(6, OplPatches.bass_drum(), 0, pan):
		apu.write(bank, w[0], w[1])
	var singles := [[OplPatches.hi_hat(), 0x11], [OplPatches.snare(), 0x14], [OplPatches.tom(), 0x12], [OplPatches.cymbal(), 0x15]]
	for entry in singles:
		var b := OplPatches.op_bytes(entry[0])
		var off: int = entry[1]
		apu.write(bank, 0x20 + off, b[0])
		apu.write(bank, 0x40 + off, b[1])
		apu.write(bank, 0x60 + off, b[2])
		apu.write(bank, 0x80 + off, b[3])
		apu.write(bank, 0xE0 + off, b[4])
	apu.write(bank, 0xC7, pan)
	apu.write(bank, 0xC8, pan)
	for pair in [[6, BD_NOTE], [7, HH_SD_NOTE], [8, TOM_NOTE]]:
		var bf := OplSong.fnum_of(OplSong.midi_hz(pair[1]))
		apu.write(bank, 0xA0 + pair[0], bf[1] & 0xFF)
		apu.write(bank, 0xB0 + pair[0], (bf[0] << 2) | (bf[1] >> 8))
	_write_bd(bank, 0)


func _pan_bits(pan: String) -> int:
	if opl.chip != "opl3":
		return 0
	match pan:
		"L":
			return 0x10
		"R":
			return 0x20
	return 0x30


func _write_bd(bank: int, keys: int) -> void:
	var value := 0x20 | keys
	if value != _sent_bd[bank]:
		apu.write(bank, BD_REG, value)
		_sent_bd[bank] = value


func tick() -> void:
	_strike = PackedInt32Array([0, 0])
	if _drums_dirty:
		_reload_drums()
	super()
	# Drums struck again this frame: their bits go off, then on.
	for bank in 2:
		if _strike[bank]:
			_write_bd(bank, _drum_on[bank] & ~_strike[bank])
		if _sent_bd[bank] >= 0 or _strike[bank]:
			_write_bd(bank, _drum_on[bank])


func _attack(channel: int, n: Dictionary) -> void:
	super(channel, n)
	var v: Dictionary = opl.layout[channel]
	var drum := str(v["drum"])
	if drum == "":
		_key_now[channel] = 1
	else:
		var bank := int(v["bank"])
		var bit: int = OplSong.DRUM_BIT[drum]
		if _drum_on[bank] & bit:
			_strike[bank] |= bit
		_drum_on[bank] |= bit


func _output(channel: int) -> void:
	var v: Dictionary = opl.layout[channel]
	if str(v["drum"]) != "":
		_output_drum(channel, v)
	else:
		_output_melodic(channel, v)


func _output_melodic(channel: int, v: Dictionary) -> void:
	var ch = _ch[channel]
	var bank := int(v["bank"])
	var c := int(v["ch"])
	if ch.note <= 0:
		if _keyed[channel]:
			apu.write(bank, 0xB0 + c, (_sent_freq[channel] >> 8) & 0x1F)
			_keyed[channel] = 0
		_key_now[channel] = 0
		return
	var inst: Dictionary = ch.instrument
	var patch: Dictionary = inst.get("opl", {})
	if patch.is_empty():
		return
	var level := SmsSong.mix_level(ch.volume, ch.value("volume", 15))
	var atten := OplSong.level_atten(level)
	var index: int = opl.instruments.find(inst)
	if _patch[channel] != index:
		if _keyed[channel]:
			apu.write(bank, 0xB0 + c, (_sent_freq[channel] >> 8) & 0x1F)
			_keyed[channel] = 0
		for w in OplSong.patch_registers(c, patch, atten, _pan_bits(str(v["pan"]))):
			apu.write(bank, w[0], w[1])
		_patch[channel] = index
		_sent_level[channel] = atten
	elif atten != _sent_level[channel]:
		var car: int = Opl.OP_OFFSET[c] + 3
		apu.write(bank, 0x40 + car, OplPatches.op_bytes(patch["car"], atten)[1])
		if int(patch.get("cnt", 0)) == 1:
			apu.write(bank, 0x40 + car - 3, OplPatches.op_bytes(patch["mod"], atten)[1])
		_sent_level[channel] = atten
	var midi := clampf(ch.note + ch.arp_value(), 0.0, 127.0) + (ch.value("pitch", 0) + int(v["detune"])) / 100.0
	var bf := OplSong.fnum_of(OplSong.midi_hz(midi))
	var freq := (bf[0] << 10) | bf[1]
	var hi := (bf[0] << 2) | (bf[1] >> 8)
	if _key_now[channel]:
		if _keyed[channel]:
			apu.write(bank, 0xB0 + c, (_sent_freq[channel] >> 8) & 0x1F)
		if freq != _sent_freq[channel]:
			apu.write(bank, 0xA0 + c, bf[1] & 0xFF)
		apu.write(bank, 0xB0 + c, 0x20 | hi)
		_keyed[channel] = 1
		_key_now[channel] = 0
		_sent_freq[channel] = (hi << 8) | (bf[1] & 0xFF)
	elif ((hi << 8) | (bf[1] & 0xFF)) != _sent_freq[channel]:
		apu.write(bank, 0xA0 + c, bf[1] & 0xFF)
		if hi != (_sent_freq[channel] >> 8):
			apu.write(bank, 0xB0 + c, 0x20 | hi)
		_sent_freq[channel] = (hi << 8) | (bf[1] & 0xFF)


func _output_drum(channel: int, v: Dictionary) -> void:
	var ch = _ch[channel]
	var bank := int(v["bank"])
	var drum := str(v["drum"])
	var bit: int = OplSong.DRUM_BIT[drum]
	if ch.note <= 0:
		_drum_on[bank] &= ~bit
		return
	var atten := OplSong.level_atten(ch.volume)
	if atten != _sent_level[channel]:
		match drum:
			"bd":
				apu.write(bank, 0x53, OplPatches.op_bytes(OplPatches.bass_drum()["car"], atten)[1])
			"hh":
				apu.write(bank, 0x51, OplPatches.op_bytes(OplPatches.hi_hat(), atten)[1])
			"sd":
				apu.write(bank, 0x54, OplPatches.op_bytes(OplPatches.snare(), atten)[1])
			"tom":
				apu.write(bank, 0x52, OplPatches.op_bytes(OplPatches.tom(), atten)[1])
			"cym":
				apu.write(bank, 0x55, OplPatches.op_bytes(OplPatches.cymbal(), atten)[1])
		_sent_level[channel] = atten
	if drum == "tom":
		var bf := OplSong.fnum_of(OplSong.midi_hz(ch.note))
		var freq := (bf[0] << 10) | bf[1]
		if freq != _tom_freq[bank]:
			apu.write(bank, 0xA8, bf[1] & 0xFF)
			apu.write(bank, 0xB8, (bf[0] << 2) | (bf[1] >> 8))
			_tom_freq[bank] = freq


func get_channel_volume(channel: int) -> int:
	var ch = _ch[channel]
	if ch.note <= 0:
		return 0
	return SmsSong.mix_level(ch.volume, ch.value("volume", 15))
