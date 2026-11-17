class_name SidSfx
extends RefCounted
## A sound effect converted for the SID, played by our 6502 player on voice
## 2 over the music, which gets the voice back when the sound ends.
##
## It starts from the NES conversion ([NesSfx]), so pitch moves in semitone
## steps once per frame. Tonal sounds play a pulse with the NES duty cycle,
## noisy ones the SID's noise. The SID has no per-frame volume, so the
## sound's volume curve becomes the closest hardware ADSR envelope.

var name := "sfx"
var noise := false
## The MIDI note the sound starts on, or the NES noise note (16 to 31).
var note := 69
## The NES volume per frame (0 to 15), which sets its length and envelope.
var volume := PackedInt32Array()
## Semitones from [member note] per frame, or noise steps.
var pitch := PackedInt32Array()
var duty := PackedInt32Array()
var notes: PackedStringArray = []


func frame_count() -> int:
	return volume.size()


static func from_sfx(sfx: ChipSfx, sound_name := "") -> SidSfx:
	var nes := NesSfx.from_sfx(sfx, sound_name)
	var out := SidSfx.new()
	out.name = nes.name
	for v in nes.volume:
		out.volume.append(int(v))
	out.pitch = nes.pitch.duplicate()
	out.duty = nes.duty.duplicate()
	if nes.channel == NesSong.NOISE:
		out.noise = true
		out.note = nes.note
		out.notes.append_array(nes.notes)
	else:
		out.note = SidSong.fit(NesSong.midi_of(NesSong.PULSE2, nes.note))["note"]
		out.notes.append_array(nes.notes)
	return out


func channel() -> int:
	return SidSong.DRUMS if noise else SidSong.ACCOMP


func instrument() -> Dictionary:
	var adsr := SidSong.adsr_of(Array(volume), -1, SidSong.FRAME_HZ)
	var inst := {"name": name, "volume": Array(volume), "arp": Array(pitch), "ad": adsr[0], "sr": adsr[1]}
	inst["wave"] = "noise" if noise else "pulse"
	if not noise:
		inst["duty"] = Array(duty)
	return inst


## The sound as a one-note [SidSong] at one frame per row.
func to_song() -> SidSong:
	var song := SidSong.new()
	song.title = name
	song.groove = PackedInt32Array([1])
	song.steps_per_beat = 4
	song.steps_per_bar = 16
	song.row_count = frame_count() + 1
	song.looping = false
	song.section_rows = [{"name": name, "row": 0, "length": song.row_count}]
	song.instruments = [instrument()]
	song.notes[channel()] = [{"row": 0, "length": frame_count(), "note": note, "instrument": 0, "volume": 15, "arp": -1}]
	return song


## A player for the sound that sets only voice 2's registers.
func make_player(chip: Variant) -> SidPlayer:
	var player := SidPlayer.new(to_song(), chip)
	player.channel_mask = 1 << channel()
	player.hard_restart = false
	player.pitched_drums = false
	player.start(0)
	return player


## Plays the sound through an emulated SID, as our player would. Returns
## mono samples.
func render(mix_rate := 44100) -> PackedFloat32Array:
	var chip := SidChip.new(float(mix_rate))
	var player := make_player(chip)
	var frames := frame_count() + 15
	var per_frame := mix_rate / SidSong.FRAME_HZ
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
			chip.render(out, pos, n)
			pos += n
	out.resize(pos)
	for i in pos:
		out[i] = clampf(out[i] * 1.5, -1.0, 1.0)
	return out
