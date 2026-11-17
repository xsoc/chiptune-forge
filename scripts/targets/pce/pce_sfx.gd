class_name PceSfx
extends RefCounted
## A sound effect converted for the PC Engine, played by our C player on
## channel 5 over the music, which gets the channel back when the sound
## ends.
##
## It starts from the NES conversion ([NesSfx]), so pitch moves in semitone
## steps once per frame. Tonal sounds play a pulse or square waveform (from
## the sound's duty), noisy ones the channel's noise, with the NES noise
## pitches moved to the chip's noise frequencies.

## The PSG channel sound effects play on (channel 5).
const VOICE := 4

var name := "sfx"
var noise := false
## The waveform name for tonal sounds.
var wave := "square"
## The MIDI note the sound starts on, or the noise frequency (1 to 31).
var note := 69
## Level per frame, 0 (silent) to 15.
var volume := PackedInt32Array()
## Semitones from [member note] per frame, or noise frequency steps.
var pitch := PackedInt32Array()
var notes: PackedStringArray = []


func frame_count() -> int:
	return volume.size()


## The PC Engine noise frequency (1 to 31, 31 the highest) for an NES noise
## period index (0 the highest, 15 the lowest).
static func noise_of_index(index: int) -> int:
	return clampi(31 - clampi(index, 0, 15) * 2, 1, 31)


static func from_sfx(sfx: ChipSfx, sound_name := "") -> PceSfx:
	var nes := NesSfx.from_sfx(sfx, sound_name)
	var out := PceSfx.new()
	out.name = nes.name
	for v in nes.volume:
		out.volume.append(SmsSong.level_of(v))
	if nes.channel == NesSong.NOISE:
		out.noise = true
		var freqs := PackedInt32Array()
		for p in nes.pitch:
			freqs.append(noise_of_index(15 - clampi(nes.note + p - 16, 0, 15)))
		out.note = freqs[0]
		for f in freqs:
			out.pitch.append(f - out.note)
		out.notes.append_array(nes.notes)
	else:
		var duty := nes.duty[0] if not nes.duty.is_empty() else 2
		out.wave = ["pulse12", "pulse25", "square", "pulse25"][clampi(duty, 0, 3)]
		out.note = PceSong.fit(NesSong.midi_of(NesSong.PULSE2, nes.note))["note"]
		out.pitch = nes.pitch.duplicate()
		for line in nes.notes:
			out.notes.append(line.replace(" as a pulse", " as a %s wave" % out.wave.replace("12", " 12%").replace("25", " 25%")))
	return out


## The instrument holding the sound's envelopes, in [PceSong] form (its
## wave index is for a song whose waves are just this sound's).
func instrument() -> Dictionary:
	return {"name": name, "wave": 0, "noise": noise, "volume": Array(volume), "arp": Array(pitch)}


## The sound as a one-note [PceSong] on channel 5, at one frame per row.
func to_song() -> PceSong:
	var song := PceSong.new()
	song.title = name
	song.groove = PackedInt32Array([1])
	song.steps_per_beat = 4
	song.steps_per_bar = 16
	song.row_count = frame_count() + 1
	song.looping = false
	song.section_rows = [{"name": name, "row": 0, "length": song.row_count}]
	song.wave_index(wave)
	song.instruments = [instrument()]
	song.notes[VOICE] = [{"row": 0, "length": frame_count(), "note": note, "instrument": 0, "volume": 15, "arp": -1}]
	return song


## Plays the sound through an emulated PSG, as our player would. Returns
## mono samples.
func render(mix_rate := 44100) -> PackedFloat32Array:
	var psg := PcePsg.new(float(mix_rate))
	var player := PcePlayer.new(to_song(), psg)
	player.channel_mask = 1 << VOICE
	var frames := frame_count() + 6
	var per_frame := mix_rate / PceSong.FRAME_HZ
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
		out[i] = clampf(out[i] * 2.0, -1.0, 1.0)
	return out
