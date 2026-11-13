class_name NesSfx
extends RefCounted
## A sound effect converted for the NES: one instrument whose envelopes hold
## the sound frame by frame (volume, pitch in semitones from the first note,
## and duty or noise mode), played as a one-note FamiStudio song. FamiStudio
## exports such songs as sound effects for its engine, which plays them over
## the music and gives the channel back when they end.
##
## Tonal sounds play on Pulse 2 and noisy ones on the noise channel. Pitch
## moves in semitone steps, once per frame; filters, phaser, bit-crush, echo
## and second layers are left out.

## Envelopes are at most 255 frames long.
const MAX_FRAMES := 255

var name := "sfx"
## [constant NesSong.PULSE2] or [constant NesSong.NOISE].
var channel := NesSong.PULSE2
## The note the sound starts on (a FamiStudio note value).
var note := 49
var volume := PackedInt32Array()
## Semitones from [member note], per frame.
var pitch := PackedInt32Array()
## Duty (0 to 3) on Pulse 2, mode (0 or 1) on the noise channel.
var duty := PackedInt32Array()
var notes: PackedStringArray = []


func frame_count() -> int:
	return volume.size()


## Converts a sound by running the sfxr model and sampling it once per frame.
static func from_sfx(sfx: ChipSfx, sound_name := "") -> NesSfx:
	var out := NesSfx.new()
	out.name = sound_name if sound_name != "" else sfx.get_sound_name()
	var p := ChipSfxSynth.with_defaults(sfx.data.get("params", {}))
	var wave := str(p["wave"])
	var noisy := wave == "noise" or wave == "noise_short"
	out.channel = NesSong.NOISE if noisy else NesSong.PULSE2
	var gain := clampf(float(p["volume"]) * 2.0, 0.35, 1.0)
	var state := ChipSfxSynth._State.new()
	state.setup(p)
	var per_frame := ChipSfxSynth.DEFAULT_RATE / NesApu.FRAME_HZ
	var acc := 0.0
	var count := 0
	var targets: Array[int] = []
	while state.playing and count < MAX_FRAMES:
		acc += per_frame
		var sum_env := 0.0
		var n := 0
		var period := 8
		var square_duty := 0.5
		while acc >= 1.0 and state.playing:
			acc -= 1.0
			state.tick()
			sum_env += state.env_vol
			n += 1
			period = state.period
			square_duty = state.square_duty
		if n == 0:
			break
		var env := clampf(sum_env / n, 0.0, 1.0)
		out.volume.append(clampi(roundi(15.0 * env * gain), 0, 15))
		# sfxr's oscillator runs at 8x 44.1 kHz and wraps every `period` steps.
		var freq := ChipSfxSynth.DEFAULT_RATE * ChipSfxSynth.OVERSAMPLE / float(maxi(period, 1))
		if noisy:
			# sfxr's noise holds 32 random values per period.
			targets.append(NesArranger.noise_note(nearest_noise(freq * 32.0)))
			out.duty.append(1 if wave == "noise_short" else 0)
		else:
			var value := roundi(1.0 + 12.0 * log(maxf(freq, 1.0) / 32.7032) / log(2.0))
			targets.append(clampi(value, NesSong.LOWEST_TONAL_NOTE, NesSong.LAST_NOTE))
			out.duty.append(GbSfx._duty_code(square_duty))
		count += 1
	# Trim trailing silence, then end on silence: an envelope holds its last
	# value, so the last frame must be 0.
	while out.volume.size() > 1 and out.volume[out.volume.size() - 1] == 0 and out.volume[out.volume.size() - 2] == 0:
		out.volume.resize(out.volume.size() - 1)
	if out.volume.is_empty() or out.volume[out.volume.size() - 1] != 0:
		if out.volume.size() >= MAX_FRAMES:
			out.volume[out.volume.size() - 1] = 0
		else:
			out.volume.append(0)
	targets.resize(out.volume.size())
	out.duty.resize(out.volume.size())
	for i in targets.size():
		if targets[i] == 0:
			targets[i] = targets[i - 1] if i > 0 else 49
	out.note = targets[0]
	for t in targets:
		out.pitch.append(clampi(t - out.note, -64, 63))
	if count >= MAX_FRAMES and state.playing:
		out.notes.append("cut to %.1f s" % (MAX_FRAMES / NesApu.FRAME_HZ))
	if float(p["lpf_freq"]) < 1.0 or float(p["hpf_freq"]) > 0.0 or float(p["pha_offset"]) != 0.0:
		out.notes.append("filters left out")
	if wave in ["saw", "sine", "triangle"]:
		out.notes.append("%s wave played as a pulse" % wave)
	if sfx.data.has("layer2"):
		out.notes.append("second layer left out")
	return out


## The noise period index (0 to 15) whose step rate is nearest to [param hz].
static func nearest_noise(hz: float) -> int:
	var best := 0
	var best_error := INF
	for i in NesApu.NOISE_PERIODS.size():
		var clock: float = NesApu.CPU_HZ / float(NesApu.NOISE_PERIODS[i])
		var error := absf(log(clock / maxf(hz, 1.0)))
		if error < best_error:
			best_error = error
			best = i
	return best


## The instrument holding the sound's envelopes, in [NesSong] form.
func instrument() -> Dictionary:
	return {"name": name, "volume": Array(volume), "arp": Array(pitch), "duty": Array(duty)}


## The sound as a one-note [NesSong] at one frame per row.
func to_song() -> NesSong:
	var song := NesSong.new()
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


## Plays the sound through an emulated 2A03, as FamiStudio's engine would on
## the console. Returns mono samples.
func render(mix_rate := 44100) -> PackedFloat32Array:
	var apu := NesApu.new(float(mix_rate))
	var player := NesPlayer.new(to_song(), apu)
	var frames := frame_count() + 6
	var per_frame := mix_rate / NesApu.FRAME_HZ
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
			apu.render(out, pos, n)
			pos += n
	out.resize(pos)
	for i in pos:
		out[i] = clampf(out[i] * 2.4, -1.0, 1.0)
	return out
