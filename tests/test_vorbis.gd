extends "res://tests/test_case.gd"
## The OGG Vorbis encoder. CI also decodes real exports with libvorbis and
## FFmpeg (tools/check_ogg.py).


func _tone(seconds: float, rate := 44100) -> PackedVector2Array:
	var frames := PackedVector2Array()
	frames.resize(int(seconds * rate))
	for i in frames.size():
		var t := i / float(rate)
		frames[i] = Vector2(0.4 * sin(TAU * 440.0 * t), 0.3 if fmod(t * 220.0, 1.0) < 0.5 else -0.3)
	return frames


func _has(bytes: PackedByteArray, text: String) -> bool:
	return bytes.hex_encode().contains(text.to_ascii_buffer().hex_encode())


func test_mdct_matches_the_definition() -> void:
	ChipVorbis._ensure_tables()
	var x := PackedFloat64Array()
	x.resize(ChipVorbis.BLOCK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in x.size():
		x[i] = rng.randf_range(-1.0, 1.0)
	var fast := ChipVorbis._mdct(x)
	var n := float(ChipVorbis.BLOCK)
	for k in [0, 1, 7, 100, 511, 512, 1000, 1023]:
		var sum := 0.0
		for i in ChipVorbis.BLOCK:
			sum += x[i] * cos(TAU / n * (i + 0.5 + n / 4.0) * (k + 0.5))
		check_near(fast[k], sum * 2.0 / ChipVorbis.HALF, 1e-9, "coefficient %d" % k)


func test_codes_are_complete_prefix_codes() -> void:
	var weights := PackedFloat64Array()
	for i in 625:
		weights.append(exp(-0.03 * i))
	var lengths := ChipVorbis.huffman_lengths(weights, 1e-6)
	var kraft := 0.0
	for length_bits in lengths:
		check(length_bits >= 1 and length_bits <= 32)
		kraft += pow(2.0, -length_bits)
	check_near(kraft, 1.0, 1e-9, "a complete tree, as decoders require")
	var codes := ChipVorbis.codewords(PackedInt32Array([2, 2, 2, 3, 3]))
	# Vorbis assigns 00, 01, 10, 110, 111 (stored bit-reversed).
	check_eq(Array(codes), [0b00, 0b10, 0b01, 0b011, 0b111])


func test_ogg_pages() -> void:
	ChipVorbis._ensure_tables()
	check_eq(ChipVorbis._crc("OggS".to_ascii_buffer()), 0x5fb0a94f, "CRC-32 with polynomial 0x04C11DB7, no reflection")
	var bytes := ChipVorbis.from_frames(_tone(0.5), 44100, 1000, 20000).run()
	check_eq(bytes.slice(0, 4).get_string_from_ascii(), "OggS")
	check_eq(bytes[5], 2, "the first page begins the stream")
	var pages := 0
	var at := 0
	var last_granule := 0
	var last_flags := 0
	while at < bytes.size():
		check_eq(bytes.slice(at, at + 4).get_string_from_ascii(), "OggS")
		var segments := bytes[at + 26]
		var size := 27 + segments
		for i in segments:
			size += bytes[at + 27 + i]
		var page := bytes.slice(at, at + size)
		var crc := page.decode_u32(22)
		page.encode_u32(22, 0)
		check_eq(ChipVorbis._crc(page), crc, "page %d CRC" % pages)
		last_granule = bytes.decode_s64(at + 6)
		last_flags = bytes[at + 5]
		at += size
		pages += 1
	check_eq(last_granule, 22050, "the last page's granule is the true length")
	check_eq(last_flags & 4, 4, "and it ends the stream")
	check(_has(bytes, "LOOPSTART=1000") and _has(bytes, "LOOPLENGTH=19000"), "loop tags")


func test_godot_plays_it() -> void:
	var bytes := ChipVorbis.from_frames(_tone(1.0), 44100).run()
	var stream := AudioStreamOggVorbis.load_from_buffer(bytes)
	check(stream != null, "Godot loads the file")
	if stream:
		check_near(stream.get_length(), 1.0, 0.01)
	check(bytes.size() < 44100 * 4 / 4, "well under a quarter of the WAV")


func test_from_wav_mono_and_48k() -> void:
	var pcm := PackedByteArray()
	pcm.resize(4800 * 2)
	for i in 4800:
		pcm.encode_s16(i * 2, int(12000.0 * sin(TAU * 600.0 * i / 48000.0)))
	var wav := ChipAudio.wav_header(pcm.size(), 1, 48000)
	wav.append_array(pcm)
	var info := ChipVorbis.parse_wav(wav)
	check_eq([info.channels, info.rate, info.frames], [1, 48000, 4800])
	var encoder := ChipVorbis.from_wav(wav)
	var steps := 0
	while not encoder.step(1):
		steps += 1
	check(steps > 1, "works a little at a time")
	var stream := AudioStreamOggVorbis.load_from_buffer(encoder.bytes)
	check(stream != null)
	if stream:
		check_near(stream.get_length(), 0.1, 0.01)
	check(ChipVorbis.from_wav("nope".to_ascii_buffer()) == null)


func test_export_adds_ogg() -> void:
	var song := SongGenerator.generate(SongSettings.new())
	var job := ExportJob.for_target_song("modern", song, {"prefix": "t", "godot": false, "wav": false, "ogg": true, "loops": 1})
	job.run()
	check(job.files.has("audio/t.ogg"), "an OGG")
	check(not job.files.has("audio/t.wav"), "and no WAV when WAV is off")
	check(_has(job.files["audio/t.ogg"], "LOOPSTART="), "with the loop")
	check(_has(job.files["audio/t.ogg"], "COMMENT=Made with Chiptune Forge"), "and the credit")
	var readme: String = job.files["README.txt"].get_string_from_utf8()
	check(readme.contains("OGG Vorbis") and not readme.contains("smpl"), readme)


func test_prerendered_song() -> void:
	var settings := SongSettings.new()
	settings.length_seconds = 15.0
	var song := SongGenerator.generate(settings)
	var stream := song.render_ogg(22050)
	check(stream != null)
	if stream:
		check_eq(stream.loop, bool(song.data.get("timing", {}).get("loop", true)))
		check(stream.get_length() > 1.0)
