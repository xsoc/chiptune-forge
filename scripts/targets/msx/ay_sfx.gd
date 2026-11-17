class_name AySfx
extends RefCounted
## A sound effect converted for the AY-3-8910, played by our Z80 player on
## channel B over the music, which gets the channel back when the sound
## ends.
##
## It starts from the NES conversion ([NesSfx]), so pitch moves in semitone
## steps once per frame. Tonal sounds play a square, noisy ones the noise
## generator, with the NES noise pitches moved to the chip's noise periods.

var name := "sfx"
var noise := false
## The MIDI note the sound starts on, or the NES noise note (16 to 31).
var note := 69
## Level per frame, 0 (silent) to 15.
var volume := PackedInt32Array()
## Semitones from [member note] per frame, or noise steps.
var pitch := PackedInt32Array()
var notes: PackedStringArray = []


func frame_count() -> int:
	return volume.size()


static func from_sfx(sfx: ChipSfx, sound_name := "") -> AySfx:
	var nes := NesSfx.from_sfx(sfx, sound_name)
	var out := AySfx.new()
	out.name = nes.name
	for v in nes.volume:
		out.volume.append(AySong.level_of(v))
	out.pitch = nes.pitch.duplicate()
	if nes.channel == NesSong.NOISE:
		out.noise = true
		out.note = nes.note
		out.notes.append_array(nes.notes)
	else:
		out.note = AySong.fit(NesSong.midi_of(NesSong.PULSE2, nes.note))["note"]
		for line in nes.notes:
			out.notes.append(line.replace(" as a pulse", " as a square"))
	return out


## The song channel the sound plays as.
func channel() -> int:
	return AySong.DRUMS if noise else AySong.ACCOMP


## The sound as a one-note [AySong] at one frame per row.
func to_song() -> AySong:
	var song := AySong.new()
	song.title = name
	song.groove = PackedInt32Array([1])
	song.steps_per_beat = 4
	song.steps_per_bar = 16
	song.row_count = frame_count() + 1
	song.looping = false
	song.section_rows = [{"name": name, "row": 0, "length": song.row_count}]
	song.instruments = [{"name": name, "volume": Array(volume), "arp": Array(pitch)}]
	song.notes[channel()] = [{"row": 0, "length": frame_count(), "note": note, "instrument": 0, "volume": 15, "arp": -1}]
	return song


## A player for the sound that sets only channel B's registers (and the
## noise period for noisy sounds).
func make_player(chip: Variant) -> AyPlayer:
	var player := AyPlayer.new(to_song(), chip)
	player.channel_mask = 1 << channel()
	return player


## Plays the sound through an emulated chip, as our player would. Returns
## mono samples.
func render(mix_rate := 44100) -> PackedFloat32Array:
	var psg := AyPsg.new(float(mix_rate))
	var player := make_player(psg)
	var frames := frame_count() + 6
	var per_frame := mix_rate / AySong.FRAME_HZ
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
		out[i] = clampf(out[i] * 1.5, -1.0, 1.0)
	return out
