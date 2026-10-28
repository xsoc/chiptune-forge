extends "res://tests/test_case.gd"


func test_wav_header_and_loop_chunk() -> void:
	var frames := PackedVector2Array()
	frames.resize(1000)
	var bytes := ChipAudio.encode_wav_stereo(frames, 44100, 100, 900)
	check_eq(bytes.slice(0, 4).get_string_from_ascii(), "RIFF")
	check_eq(bytes.slice(8, 12).get_string_from_ascii(), "WAVE")
	check_eq(bytes.decode_u32(4), bytes.size() - 8, "RIFF size")
	check_eq(bytes.decode_u16(22), 2, "channels")
	check_eq(bytes.decode_u32(24), 44100, "rate")
	check_eq(bytes.decode_u32(40), 4000, "data size")
	var smpl := 44 + 4000
	check_eq(bytes.slice(smpl, smpl + 4).get_string_from_ascii(), "smpl")
	check_eq(bytes.decode_u32(smpl + 8 + 44), 100, "loop start")
	check_eq(bytes.decode_u32(smpl + 8 + 48), 899, "loop end")


func test_mono_wav_has_no_loop() -> void:
	var samples := PackedFloat32Array([0.0, 0.5, -0.5, 1.0])
	var bytes := ChipAudio.encode_wav_mono(samples, 22050)
	check_eq(bytes.size(), 44 + 8)
	check_eq(bytes.decode_s16(44 + 6), 32767, "full scale")


func test_midi_file() -> void:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "platformer"
	s.seed_text = "midi"
	var bytes := MidiWriter.encode(SongGenerator.generate(s))
	check_eq(bytes.slice(0, 4).get_string_from_ascii(), "MThd")
	var tracks := (bytes[10] << 8) | bytes[11]
	check(tracks >= 2, "has a conductor and note tracks")
	var count := 0
	var offset := 14
	while offset < bytes.size():
		check_eq(bytes.slice(offset, offset + 4).get_string_from_ascii(), "MTrk", "track %d" % count)
		var length := (bytes[offset + 4] << 24) | (bytes[offset + 5] << 16) | (bytes[offset + 6] << 8) | bytes[offset + 7]
		offset += 8 + length
		count += 1
	check_eq(offset, bytes.size(), "track lengths add up")
	check_eq(count, tracks, "track count")


func test_sequencer_renders_song() -> void:
	var s := SongSettings.new()
	s.vibes.assign(["calm"])
	s.style = "shmup"
	s.seed_text = "render"
	s.length_seconds = 30
	var song := SongGenerator.generate(s)
	var sequencer := ChipSongSequencer.new(song, 22050)
	sequencer.looping = false
	var frames := sequencer.render_all(1)
	check_near(frames.size() / 22050.0, song.get_length_seconds(), 3.0, "rendered length")
	var peak := 0.0
	for frame in frames:
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	check(peak > 0.05 and peak <= 1.0, "peak %f" % peak)


func test_song_export_zip() -> void:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = "platformer"
	s.seed_text = "zip"
	s.length_seconds = 30
	var job := ExportJob.for_song(SongGenerator.generate(s), {"prefix": "test song", "midi": true, "stems": false})
	var guard := 0
	while not job.done and guard < 10000:
		job.step(50000)
		guard += 1
	check(job.done, "export finishes")
	var names: Array = job.files.keys()
	var has := func(suffix: String) -> bool:
		return names.any(func(n: String) -> bool: return n.ends_with(suffix))
	check(has.call(".chipsong"), "has the song: %s" % str(names))
	check(has.call(".wav"), "has a WAV")
	check(has.call(".mid"), "has MIDI")
	check(has.call("addons/chipforge/plugin.cfg"), "bundles the plugin")
	check(has.call("addons/chipforge/runtime/chip_music_player.gd"), "bundles the player")
	var zip := job.build_zip()
	check(zip.size() > 1000 and zip.slice(0, 2).get_string_from_ascii() == "PK", "builds a zip")


func test_kit_export() -> void:
	var catalog := Catalog.get_default()
	var sounds := {
		"jump": SfxGenerator.make_sfx(catalog.get_sfx_preset("jump"), 1),
		"coin": SfxGenerator.make_sfx(catalog.get_sfx_preset("coin"), 2),
	}
	var job := ExportJob.for_sfx(sounds, "Test kit", {})
	while not job.done:
		job.step(50000)
	var names: Array = job.files.keys()
	check(names.any(func(n: String) -> bool: return n.ends_with(".chipkit")), "has the kit: %s" % str(names))
	check(names.filter(func(n: String) -> bool: return n.ends_with(".wav")).size() == 2, "one WAV per sound")
