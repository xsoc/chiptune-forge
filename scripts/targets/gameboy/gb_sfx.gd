class_name GbSfx
extends RefCounted
## A sound effect converted for the Game Boy: one register update per video
## frame on one channel, played by the small cf_sfx player that the Game Boy
## export includes (see [GbCWriter]).
##
## Tonal sounds play on Pulse 2 and noisy ones on the noise channel. Each
## frame stores the volume, duty and pitch the sfxr model has at that moment;
## filters, phaser, bit-crush, echo and second layers are left out.

## The Game Boy's frame rate (VBlank).
const FRAME_HZ := 59.7275
## Frames are counted in a byte.
const MAX_FRAMES := 255
const PULSE := 1
const NOISE := 3
## Frame byte 0 flag: rewrite the volume and retrigger the channel.
const RETRIGGER := 0x04

var name := "sfx"
## [constant PULSE] (channel 2) or [constant NOISE] (channel 4).
var channel := PULSE
## Three bytes per frame: volume << 4 | retrigger | duty, then the period's
## low byte (or NR43 for noise), then the period's high bits.
var frames := PackedByteArray()
var notes: PackedStringArray = []


func frame_count() -> int:
	return frames.size() / 3


## Converts a sound by running the sfxr model and sampling it once per frame.
static func from_sfx(sfx: ChipSfx, sound_name := "") -> GbSfx:
	var out := GbSfx.new()
	out.name = sound_name if sound_name != "" else sfx.get_sound_name()
	var p := ChipSfxSynth.with_defaults(sfx.data.get("params", {}))
	var wave := str(p["wave"])
	out.channel = NOISE if wave == "noise" or wave == "noise_short" else PULSE
	var gain := clampf(float(p["volume"]) * 2.0, 0.35, 1.0)
	var state := ChipSfxSynth._State.new()
	state.setup(p)
	var per_frame := ChipSfxSynth.DEFAULT_RATE / FRAME_HZ
	var acc := 0.0
	var last_volume := -1
	var count := 0
	while state.playing and count < MAX_FRAMES:
		acc += per_frame
		var sum_env := 0.0
		var n := 0
		var period := 8
		var duty := 0.5
		while acc >= 1.0 and state.playing:
			acc -= 1.0
			state.tick()
			sum_env += state.env_vol
			n += 1
			period = state.period
			duty = state.square_duty
		if n == 0:
			break
		var env := clampf(sum_env / n, 0.0, 1.0)
		var volume := clampi(roundi(15.0 * env * gain), 0, 15)
		# sfxr's oscillator runs at 8x 44.1 kHz and wraps every `period` steps.
		var freq := ChipSfxSynth.DEFAULT_RATE * ChipSfxSynth.OVERSAMPLE / float(maxi(period, 1))
		var b0 := volume << 4
		if volume != last_volume:
			b0 |= RETRIGGER
			last_volume = volume
		var b1 := 0
		var b2 := 0
		if out.channel == PULSE:
			b0 |= _duty_code(duty)
			var gb_period := clampi(roundi(2048.0 - 131072.0 / maxf(freq, 1.0)), 0, 2047)
			b1 = gb_period & 0xFF
			b2 = gb_period >> 8
		else:
			# sfxr's noise holds 32 random values per period.
			b1 = nearest_poly(freq * 32.0, wave == "noise_short")
		out.frames.append_array(PackedByteArray([b0, b1, b2]))
		count += 1
	# Trim trailing silence, but keep at least one frame.
	while out.frames.size() > 3 and out.frames[out.frames.size() - 3] >> 4 == 0:
		out.frames.resize(out.frames.size() - 3)
	if count >= MAX_FRAMES and state.playing:
		out.notes.append("cut to %.1f s" % (MAX_FRAMES / FRAME_HZ))
	if float(p["lpf_freq"]) < 1.0 or float(p["hpf_freq"]) > 0.0 or float(p["pha_offset"]) != 0.0:
		out.notes.append("filters left out")
	if wave in ["saw", "sine", "triangle"]:
		out.notes.append("%s wave played as a pulse" % wave)
	if sfx.data.has("layer2"):
		out.notes.append("second layer left out")
	return out


static func _duty_code(duty: float) -> int:
	if duty < 0.19:
		return 0
	if duty < 0.37:
		return 1
	return 2


## The NR43 value whose noise clock is nearest to [param hz].
static func nearest_poly(hz: float, narrow: bool) -> int:
	var best := 0
	var best_error := INF
	for shift in 14:
		for divisor in 8:
			var clock := 262144.0 / (0.5 if divisor == 0 else float(divisor)) / float(1 << shift)
			var error := absf(log(clock / maxf(hz, 1.0)))
			if error < best_error:
				best_error = error
				best = (shift << 4) | divisor
	return best | (0x08 if narrow else 0)


## Plays the frames through an emulated sound chip, as the cf_sfx player
## would on the console. Returns mono samples.
func render(mix_rate := 44100) -> PackedFloat32Array:
	var apu := GbApu.new(float(mix_rate))
	apu.write(GbApu.NR52, 0x80)
	apu.write(GbApu.NR51, 0xFF)
	apu.write(GbApu.NR50, 0x77)
	var count := frame_count()
	var per_frame := mix_rate / FRAME_HZ
	var total := int((count + 6) * per_frame)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(total)
	right.resize(total)
	var pos := 0
	var acc := 0.0
	for f in count + 6:
		if f < count:
			apply_frame(apu, f)
		elif f == count:
			stop(apu)
		acc += per_frame
		var n := mini(int(acc), total - pos)
		acc -= n
		if n > 0:
			apu.render(left, right, pos, n)
			pos += n
	var out := PackedFloat32Array()
	out.resize(pos)
	for i in pos:
		out[i] = clampf(left[i] * 1.6, -1.0, 1.0)
	return out


## The register writes cf_sfx_update makes for frame [param f].
func apply_frame(apu: GbApu, f: int) -> void:
	var a := frames[f * 3]
	var b := frames[f * 3 + 1]
	var c := frames[f * 3 + 2]
	if channel == PULSE:
		apu.write(GbApu.NR21, (a & 3) << 6)
		if a & RETRIGGER:
			apu.write(GbApu.NR22, a & 0xF0)
			apu.write(GbApu.NR23, b)
			apu.write(GbApu.NR24, 0x80 | c)
		else:
			apu.write(GbApu.NR23, b)
			apu.write(GbApu.NR24, c)
	else:
		if a & RETRIGGER:
			apu.write(GbApu.NR42, a & 0xF0)
			apu.write(GbApu.NR43, b)
			apu.write(GbApu.NR44, 0x80)
		else:
			apu.write(GbApu.NR43, b)


## What cf_sfx_stop writes: silence the channel.
func stop(apu: GbApu) -> void:
	apu.write(GbApu.NR22 if channel == PULSE else GbApu.NR42, 0)
