class_name PceDriver
extends RefCounted
## A line-by-line GDScript copy of our C player (assets/pce/pce_player.c),
## running on the data [PceWriter] makes. Tests run it next to [PcePlayer]
## to check that the exported data plays exactly what the preview plays.

const SFX_CHANNEL := 6
const SFX_VOICE := 4

var psg: PcePsg
var song := PackedByteArray()
var sfx := PackedByteArray()
var playing := false

var _c := 0
var _pos := PackedInt32Array()
var _wait := PackedInt32Array()
var _ended := PackedInt32Array()
var _note := PackedInt32Array()
var _inst := PackedInt32Array()
var _vol := PackedInt32Array()
var _arp := PackedInt32Array()
var _env_vol := PackedInt32Array()
var _env_arp := PackedInt32Array()
var _env_pitch := PackedInt32Array()
var _arp_pos := PackedInt32Array()
var _loaded := PackedInt32Array()
var _period := PackedInt32Array()
var _volume := PackedInt32Array()


func _init(chip: PcePsg, song_data: PackedByteArray, sfx_data := PackedByteArray()) -> void:
	psg = chip
	song = song_data
	sfx = sfx_data
	for n in 128:
		_period.append(PceSong.note_period(n))
	for level in 16:
		_volume.append(PceSong.volume_of_level(level))
	for array in [_pos, _wait, _ended, _note, _inst, _vol, _arp, _env_vol, _env_arp, _env_pitch, _arp_pos]:
		array.resize(7)
	_loaded.resize(6)


func _byte(offset: int) -> int:
	if _c == SFX_CHANNEL:
		return sfx[offset]
	return song[offset]


func _word(offset: int) -> int:
	return _byte(offset) | (_byte(offset + 1) << 8)


func _env_value(env: int, at: int, fallback: int) -> int:
	if env == 0:
		return fallback
	var length := _byte(env)
	if length == 0:
		return fallback
	return _byte(env + 2 + mini(at, length - 1))


func _env_next(env: int, at: int) -> int:
	if env == 0:
		return 0
	var length := _byte(env)
	if length == 0:
		return 0
	var loop := _byte(env + 1)
	at += 1
	if at >= length:
		return loop if loop < length else length - 1
	return at


static func _signed(v: int) -> int:
	return v - 256 if v >= 128 else v


func _begin(offset: int) -> void:
	_pos[_c] = offset
	_wait[_c] = 0
	_ended[_c] = 0
	_note[_c] = 0
	_inst[_c] = 255
	_vol[_c] = 15
	_arp[_c] = 255
	_env_vol[_c] = 0
	_env_arp[_c] = 0
	_env_pitch[_c] = 0
	_arp_pos[_c] = 0


func start() -> void:
	psg.write(PcePsg.MAIN_BALANCE, 0xFF)
	for c in 6:
		_c = c
		psg.write(PcePsg.SELECT, c)
		psg.write(PcePsg.CONTROL, 0)
		psg.write(PcePsg.BALANCE, _byte(36 + c))
		_loaded[c] = 255
		_begin(_word(12 + c * 2))
	_ended[SFX_CHANNEL] = 1
	playing = true


func sfx_play(n: int) -> void:
	_c = SFX_CHANNEL
	_begin(_word(12 + n * 2))


func _read() -> void:
	if _ended[_c] or _wait[_c]:
		return
	var pos := _pos[_c]
	while true:
		var b := _byte(pos)
		pos += 1
		if b < 128:
			_note[_c] = b
			_wait[_c] = _byte(pos)
			pos += 1
			_env_vol[_c] = 0
			_env_arp[_c] = 0
			_env_pitch[_c] = 0
			_arp_pos[_c] = 0
			break
		if b < 192:
			_inst[_c] = b & 63
		elif b == 192:
			_vol[_c] = _byte(pos)
			pos += 1
		elif b == 193:
			_arp[_c] = _byte(pos)
			pos += 1
		elif b == 194:
			_note[_c] = 0
			_wait[_c] = _byte(pos)
			pos += 1
			break
		elif b == 195:
			_wait[_c] = _byte(pos)
			pos += 1
			break
		elif b == 254:
			pos = _word(24 + _c * 2)
		else:
			_note[_c] = 0
			_ended[_c] = 1
			break
	_pos[_c] = pos


func _output(voice: int) -> void:
	psg.write(PcePsg.SELECT, voice)
	if _note[_c] == 0:
		psg.write(PcePsg.CONTROL, 0x80)
		return
	var inst_at := _word(8) + _inst[_c] * 8
	var wave := _byte(inst_at)
	var flags := _byte(inst_at + 1)
	var id := wave | 128 if _c == SFX_CHANNEL else wave
	if not (flags & 1) and _loaded[voice] != id:
		psg.write(PcePsg.CONTROL, 0x40)
		psg.write(PcePsg.CONTROL, 0)
		var at := _word(6) + wave * 32
		for i in 32:
			psg.write(PcePsg.WAVE, _byte(at + i))
		_loaded[voice] = id
	var value: int
	if _arp[_c] != 255:
		value = _env_value(_word(_word(10) + _arp[_c] * 2), _arp_pos[_c], 0)
	else:
		value = _env_value(_word(inst_at + 4), _env_arp[_c], 0)
	var note := _note[_c] + _signed(value)
	if flags & 1:
		psg.write(PcePsg.NOISE, 0x80 | clampi(note, 0, 31))
	else:
		if voice >= 4:
			psg.write(PcePsg.NOISE, 0)
		note = clampi(note, 0, 127)
		var period := _period[note]
		value = _signed(_env_value(_word(inst_at + 6), _env_pitch[_c], 0))
		if value != 0:
			var k := mini(note, 126)
			var step := _period[k] - _period[k + 1]
			if value > 0:
				period -= (step * value) >> 4
			else:
				period += (step * -value) >> 4
		period = clampi(period, 1, 4095)
		psg.write(PcePsg.FREQ_LO, period & 0xFF)
		psg.write(PcePsg.FREQ_HI, period >> 8)
	value = _env_value(_word(inst_at + 2), _env_vol[_c], 15)
	var level := 0
	if _vol[_c] != 0 and value != 0 and _vol[_c] + value > 15:
		level = _vol[_c] + value - 15
	psg.write(PcePsg.CONTROL, 0x80 | _volume[level])


func _advance() -> void:
	if _inst[_c] < 64:
		var inst_at := _word(8) + _inst[_c] * 8
		_env_vol[_c] = _env_next(_word(inst_at + 2), _env_vol[_c])
		_env_arp[_c] = _env_next(_word(inst_at + 4), _env_arp[_c])
		_env_pitch[_c] = _env_next(_word(inst_at + 6), _env_pitch[_c])
	if _arp[_c] != 255:
		_arp_pos[_c] = _env_next(_word(_word(10) + _arp[_c] * 2), _arp_pos[_c])
	if _wait[_c]:
		_wait[_c] -= 1


func frame() -> void:
	if not playing:
		return
	var sfx_on := false
	if not sfx.is_empty():
		_c = SFX_CHANNEL
		if not _ended[_c]:
			_read()
			_output(SFX_VOICE)
			_advance()
			sfx_on = not _ended[_c]
	for c in 6:
		_c = c
		_read()
		if c != SFX_VOICE or not sfx_on:
			_output(c)
		_advance()
