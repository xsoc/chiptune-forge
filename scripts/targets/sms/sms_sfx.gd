class_name SmsSfx
extends RefCounted
## A sound effect converted for the SN76489, played the way PSGlib plays
## sound effects: frame by frame on one channel, over the music, which gets
## the channel back when the sound ends.
##
## Tonal sounds play on Square 3 (PSGlib's SFX_CHANNEL2) and noisy ones on
## the noise channel (SFX_CHANNEL3). It starts from the NES conversion
## ([NesSfx]), so pitch moves in semitone steps once per frame, then moves
## volumes to the chip's 2 dB steps and noise to its three rates.

var name := "sfx"
## [constant SmsSong.SQUARE3] or [constant SmsSong.NOISE].
var channel := SmsSong.SQUARE3
## The MIDI note the sound starts on, or the noise rate (0 to 2).
var note := 69
## Level per frame, 0 (silent) to 15.
var volume := PackedInt32Array()
## Semitones from [member note] per frame, or noise rate steps.
var pitch := PackedInt32Array()
## Noise only: 1 for white noise, 0 for periodic.
var white := 1
var notes: PackedStringArray = []


func frame_count() -> int:
	return volume.size()


static func from_sfx(sfx: ChipSfx, sound_name := "") -> SmsSfx:
	var nes := NesSfx.from_sfx(sfx, sound_name)
	var out := SmsSfx.new()
	out.name = nes.name
	for v in nes.volume:
		out.volume.append(SmsSong.level_of(v))
	if nes.channel == NesSong.NOISE:
		out.channel = SmsSong.NOISE
		var rates := PackedInt32Array()
		for p in nes.pitch:
			var index := 15 - clampi(nes.note + p - 16, 0, 15)
			rates.append(SmsArranger.RATE_FOR_INDEX[index])
		out.note = rates[0]
		for r in rates:
			out.pitch.append(r - out.note)
		out.notes.append_array(nes.notes)
	else:
		out.channel = SmsSong.SQUARE3
		out.note = NesSong.midi_of(NesSong.PULSE2, nes.note)
		out.pitch = nes.pitch.duplicate()
		var lowest := out.note
		for p in out.pitch:
			lowest = mini(lowest, out.note + p)
		for line in nes.notes:
			out.notes.append(line.replace(" as a pulse", " as a square"))
		if lowest < SmsSong.LOWEST_NOTE:
			out.notes.append("held at A2 below the chip's lowest note")
	return out


## The instrument holding the sound's envelopes, in [SmsSong] form.
func instrument() -> Dictionary:
	var inst := {"name": name, "volume": Array(volume), "arp": Array(pitch)}
	if channel == SmsSong.NOISE:
		inst["duty"] = [white]
	return inst


## The sound as a one-note [SmsSong] at one frame per row.
func to_song() -> SmsSong:
	var song := SmsSong.new()
	song.title = name
	song.groove = PackedInt32Array([1])
	song.steps_per_beat = 4
	song.steps_per_bar = 16
	song.row_count = frame_count() + 1
	song.looping = false
	song.section_rows = [{"name": name, "row": 0, "length": song.row_count}]
	song.instruments = [instrument()]
	song.notes[channel] = [{"row": 0, "length": frame_count(), "note": note, "instrument": 0, "volume": 15, "arp": -1}]
	return song


## PSGlib's channel flag for PSGSFXPlay.
func psglib_channel() -> String:
	return "SFX_CHANNEL3" if channel == SmsSong.NOISE else "SFX_CHANNEL2"


## Plays the sound through an emulated SN76489, as PSGlib would. Returns
## mono samples.
func render(mix_rate := 44100) -> PackedFloat32Array:
	var psg := SmsPsg.new(float(mix_rate))
	var player := SmsPlayer.new(to_song(), psg)
	player.channel_mask = 1 << channel
	var frames := frame_count() + 6
	var per_frame := mix_rate / SmsSong.FRAME_HZ
	var total := int(frames * per_frame)
	var out := PackedFloat32Array()
	out.resize(total)
	var pos := 0
	var acc := 0.0
	for f in frames:
		player.tick()
		acc += per_frame
		var n := mini(int(acc), total - pos)
		acc -= n
		if n > 0:
			psg.render(out, pos, n)
			pos += n
	out.resize(pos)
	for i in pos:
		out[i] = clampf(out[i] * 0.6, -1.0, 1.0)
	return out
