class_name ChipAudio
extends RefCounted
## Helpers to turn rendered samples into Godot streams and WAV files.

const SMPL_SIZE := 60


## Converts mono samples (-1 to 1) to a 16-bit [AudioStreamWAV].
static func mono_to_stream(samples: PackedFloat32Array, mix_rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = _to_pcm16_mono(samples)
	return stream


## Converts stereo frames to a 16-bit [AudioStreamWAV], optionally looping
## between two frame positions.
static func stereo_to_stream(frames: PackedVector2Array, mix_rate: int, loop_begin := -1, loop_end := -1) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = true
	stream.data = _to_pcm16_stereo(frames)
	if loop_begin >= 0 and loop_end > loop_begin:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = loop_begin
		stream.loop_end = loop_end
	return stream


## Encodes stereo frames as a 16-bit PCM WAV file. When a loop is given it is
## written to a [code]smpl[/code] chunk, which most engines and samplers read.
static func encode_wav_stereo(frames: PackedVector2Array, mix_rate: int, loop_begin := -1, loop_end := -1) -> PackedByteArray:
	return _wav_bytes(_to_pcm16_stereo(frames), 2, mix_rate, loop_begin, loop_end)


static func encode_wav_mono(samples: PackedFloat32Array, mix_rate: int) -> PackedByteArray:
	return _wav_bytes(_to_pcm16_mono(samples), 1, mix_rate, -1, -1)


static func _to_pcm16_mono(samples: PackedFloat32Array) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return pcm


static func _to_pcm16_stereo(frames: PackedVector2Array) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(frames.size() * 4)
	write_pcm16_stereo(frames, pcm, 0)
	return pcm


## Writes stereo frames as 16-bit PCM into [param out] from byte
## [param offset]. [param out] must already be big enough. Lets long renders
## fill one buffer a block at a time instead of keeping every float frame.
static func write_pcm16_stereo(frames: PackedVector2Array, out: PackedByteArray, offset: int) -> void:
	for i in frames.size():
		var frame := frames[i]
		out.encode_s16(offset + i * 4, int(clampf(frame.x, -1.0, 1.0) * 32767.0))
		out.encode_s16(offset + i * 4 + 2, int(clampf(frame.y, -1.0, 1.0) * 32767.0))


## The RIFF, fmt and data chunk headers of a 16-bit WAV file whose sample
## data is [param pcm_size] bytes. The data follows straight after, then
## [method wav_loop_chunk] when there is a loop.
static func wav_header(pcm_size: int, channels: int, mix_rate: int, loop_begin := -1, loop_end := -1) -> PackedByteArray:
	var has_loop := loop_begin >= 0 and loop_end > loop_begin
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_u32(4 + 24 + 8 + pcm_size + (8 + SMPL_SIZE if has_loop else 0)))
	out.append_array("WAVE".to_ascii_buffer())
	out.append_array("fmt ".to_ascii_buffer())
	out.append_array(_u32(16))
	out.append_array(_u16(1))
	out.append_array(_u16(channels))
	out.append_array(_u32(mix_rate))
	out.append_array(_u32(mix_rate * channels * 2))
	out.append_array(_u16(channels * 2))
	out.append_array(_u16(16))
	out.append_array("data".to_ascii_buffer())
	out.append_array(_u32(pcm_size))
	return out


## The [code]smpl[/code] chunk holding a forward loop, which most engines and
## samplers read. Empty when there is no loop.
static func wav_loop_chunk(mix_rate: int, loop_begin: int, loop_end: int) -> PackedByteArray:
	var out := PackedByteArray()
	if loop_begin < 0 or loop_end <= loop_begin:
		return out
	out.append_array("smpl".to_ascii_buffer())
	out.append_array(_u32(SMPL_SIZE))
	out.append_array(_u32(0)) # manufacturer
	out.append_array(_u32(0)) # product
	out.append_array(_u32(int(1000000000.0 / mix_rate))) # sample period, ns
	out.append_array(_u32(60)) # MIDI unity note
	out.append_array(_u32(0)) # pitch fraction
	out.append_array(_u32(0)) # SMPTE format
	out.append_array(_u32(0)) # SMPTE offset
	out.append_array(_u32(1)) # loop count
	out.append_array(_u32(0)) # sampler data
	out.append_array(_u32(0)) # cue id
	out.append_array(_u32(0)) # forward loop
	out.append_array(_u32(loop_begin))
	out.append_array(_u32(loop_end - 1)) # inclusive end
	out.append_array(_u32(0)) # fraction
	out.append_array(_u32(0)) # play count, 0 = forever
	return out


static func _wav_bytes(pcm: PackedByteArray, channels: int, mix_rate: int, loop_begin: int, loop_end: int) -> PackedByteArray:
	var out := wav_header(pcm.size(), channels, mix_rate, loop_begin, loop_end)
	out.append_array(pcm)
	out.append_array(wav_loop_chunk(mix_rate, loop_begin, loop_end))
	return out


static func _u32(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, value)
	return bytes


static func _u16(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(2)
	bytes.encode_u16(0, value)
	return bytes
