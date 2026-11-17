class_name PcSfx
extends RefCounted
## A sound effect for a PC sound card, the way DOS games played them.
##
## The Sound Blasters play effects as samples on their DAC, over the FM
## music: 8-bit at 11 kHz on the Sound Blaster, 8-bit at 22 kHz on the Pro
## and 16-bit at 22 kHz on the 16. They export as Creative Voice files
## (.voc), which DOS sound libraries load directly, or WAV on the 16.
##
## The Gravis Ultrasound plays them as 16-bit samples on its spare voices.
## The MIDI modules play music only: DOS games played their sounds on a
## Sound Blaster beside them, so those cards get the Pro's 22 kHz samples.
##
## The Tandy plays them on its
## SN76496 as the Master System does, on Square 3 or the noise channel.
##
## The AdLib has no DAC, so its effects are FM: one OPL channel, keyed once,
## whose pitch and level follow the sound frame by frame at 70 Hz. Noisy
## sounds use the OPL's full feedback, which turns a sine into hiss. They
## export as DRO and IMF files, like the music.

## The channel AdLib sound effects use: the harmony's, which the music
## gets back when the sound ends (with the rhythm mode on, an OPL2 has no
## channel to spare).
const OPL_CHANNEL := 1

var name := "sfx"
var card := "sb"
## Sample cards: the sound at [member rate], rounded to the card's bits.
var samples := PackedFloat32Array()
var rate := 11025
var bits := 8
## AdLib: the patch, the starting MIDI note, and per 70 Hz frame the
## semitones from it and the level (0 to 15).
var patch: Dictionary = {}
var note := 69
var pitch := PackedInt32Array()
var volume := PackedInt32Array()
var noisy := false
## Tandy: the sound on the SN76496.
var psg: SmsSfx


static func from_sfx(sfx: ChipSfx, card: String, sound_name := "") -> PcSfx:
	var out := PcSfx.new()
	out.card = card
	out.name = sound_name if sound_name != "" else sfx.get_sound_name()
	if card == "tandy":
		out.psg = SmsSfx.from_sfx(sfx, out.name)
		out.psg.noise_taps = 0x0006
		out.psg.noise_width = 16
		out.noisy = out.psg.channel == SmsSong.NOISE
		return out
	if card == "adlib":
		var nes := NesSfx.from_sfx(sfx, out.name)
		out.noisy = nes.channel == NesSong.NOISE
		# NES frames are 1/60 s: resample to the driver's 70 Hz.
		var frames := int(ceilf(nes.frame_count() * OplSong.FRAME_HZ / 60.0))
		for f in frames:
			var src := mini(int(f * 60.0 / OplSong.FRAME_HZ), nes.frame_count() - 1)
			out.volume.append(nes.volume[src])
			out.pitch.append(nes.pitch[src] if src < nes.pitch.size() else 0)
		if out.noisy:
			out.note = 72 + (15 - clampi(nes.note - 16, 0, 15)) * 2
			out.patch = {"name": "Noise", "fb": 7, "cnt": 1, "mod": OplPatches.op(15, 0, 15, 0, 0, 15), "car": OplPatches.op(1, 63, 15, 0, 0, 15)}
		else:
			out.note = NesSong.midi_of(NesSong.PULSE2, nes.note)
			out.patch = {"name": "Square", "fb": 5, "cnt": 0, "mod": OplPatches.op(2, 28, 15, 0, 0, 15), "car": OplPatches.op(1, 0, 15, 0, 0, 15)}
		return out
	out.rate = 11025 if card == "sb" else 22050
	out.bits = 16 if card in ["sb16", "gus"] else 8
	var raw := sfx.render(out.rate)
	var steps := 32767.0 if out.bits == 16 else 127.0
	out.samples.resize(raw.size())
	for i in raw.size():
		out.samples[i] = roundf(clampf(raw[i] * 0.9, -1.0, 1.0) * steps) / steps
	return out


func is_fm() -> bool:
	return card == "adlib"


## True when the sound is a sample for a Sound Blaster's DAC.
func is_sample() -> bool:
	return card in ["sb", "sbpro", "sb16", "mt32", "gm", "gus"]


func seconds() -> float:
	if is_fm():
		return volume.size() / OplSong.FRAME_HZ
	if card == "tandy":
		return psg.frame_count() / SmsSong.FRAME_HZ
	return samples.size() / float(rate)


## The register writes of each 70 Hz frame, as [bank, register, value].
func opl_frames() -> Array:
	var frames: Array = []
	var c := OPL_CHANNEL
	var keyed := false
	var sent_hi := -1
	for f in volume.size():
		var writes: Array = []
		if f == 0:
			writes.append(PackedInt32Array([0, 0x01, 0x20]))
			for w in OplSong.patch_registers(c, patch, OplSong.level_atten(volume[0])):
				writes.append(PackedInt32Array([0, w[0], w[1]]))
		elif volume[f] != volume[f - 1]:
			var car: int = Opl.OP_OFFSET[c] + 3
			writes.append(PackedInt32Array([0, 0x40 + car, OplPatches.op_bytes(patch["car"], OplSong.level_atten(volume[f]))[1]]))
			if int(patch["cnt"]) == 1:
				writes.append(PackedInt32Array([0, 0x40 + car - 3, OplPatches.op_bytes(patch["mod"], OplSong.level_atten(volume[f]))[1]]))
		var bf := OplSong.fnum_of(OplSong.midi_hz(clampi(note + pitch[f], 12, 120)))
		var hi := (bf[0] << 2) | (bf[1] >> 8)
		if f == 0 or pitch[f] != pitch[f - 1]:
			writes.append(PackedInt32Array([0, 0xA0 + c, bf[1] & 0xFF]))
		if not keyed or hi != sent_hi:
			writes.append(PackedInt32Array([0, 0xB0 + c, 0x20 | hi]))
			keyed = true
			sent_hi = hi
		frames.append(writes)
	frames.append([PackedInt32Array([0, 0xB0 + c, sent_hi & 0x1F])])
	return frames


## The sound at [param mix_rate], as the card plays it.
func render(mix_rate := 44100) -> PackedFloat32Array:
	if card == "tandy":
		return psg.render(mix_rate)
	if is_fm():
		var chip := Opl.new(float(mix_rate))
		var left := PackedFloat32Array()
		var right := PackedFloat32Array()
		var per_frame := mix_rate / OplSong.FRAME_HZ
		var frames := opl_frames()
		var total := int(ceilf((frames.size() + 20) * per_frame))
		left.resize(total)
		right.resize(total)
		var at := 0
		for f in frames.size() + 20:
			if f < frames.size():
				for w in frames[f]:
					chip.write(0, w[1], w[2])
			var end := mini(int((f + 1) * per_frame), total)
			chip.render(left, right, at, end - at)
			at = end
		for i in total:
			left[i] *= 3.0
		return left
	var out := PackedFloat32Array()
	var count := int(ceilf(samples.size() * float(mix_rate) / rate))
	out.resize(count)
	var step := float(rate) / mix_rate
	for i in count:
		out[i] = samples[mini(int(i * step), samples.size() - 1)]
	return out


## A Creative Voice File (version 1.10): one 8-bit unsigned sound block.
func voc_bytes() -> PackedByteArray:
	var out := PackedByteArray("Creative Voice File".to_ascii_buffer())
	out.append(0x1A)
	out.append_array(PackedByteArray([0x1A, 0x00, 0x0A, 0x01, 0x29, 0x11]))
	var pcm := _pcm8()
	var size := pcm.size() + 2
	out.append_array(PackedByteArray([1, size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF]))
	out.append(256 - roundi(1000000.0 / rate))
	out.append(0)
	out.append_array(pcm)
	out.append(0)
	return out


func _pcm8() -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size())
	for i in samples.size():
		pcm[i] = clampi(roundi(samples[i] * 127.0) + 128, 0, 255)
	return pcm


## A mono WAV at the card's rate and bits.
func wav_bytes() -> PackedByteArray:
	var pcm := PackedByteArray()
	if bits == 16:
		pcm.resize(samples.size() * 2)
		for i in samples.size():
			pcm.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	else:
		pcm = _pcm8()
	var bytes_per := bits / 8
	var out := PackedByteArray("RIFF".to_ascii_buffer())
	var head := PackedByteArray()
	head.resize(40)
	head.encode_u32(0, 36 + pcm.size())
	out.append_array(head.slice(0, 4))
	out.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 1)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * bytes_per)
	fmt.encode_u16(16, bytes_per)
	fmt.encode_u16(18, bits)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	var size := PackedByteArray()
	size.resize(4)
	size.encode_u32(0, pcm.size())
	out.append_array(size)
	out.append_array(pcm)
	return out


## The AdLib sound's register writes as a recording [OplWriter] can write.
func recorded() -> Dictionary:
	return {"frames": opl_frames(), "loop_frame": -1, "tail": []}
