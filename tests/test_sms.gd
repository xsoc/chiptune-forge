extends "res://tests/test_case.gd"


func _song(vibe := "happy", style := "platformer", seed_text := "42") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return SongGenerator.generate(s)


func test_chip_registers() -> void:
	var psg := SmsPsg.new(22050.0)
	# Latch tone 0 low bits, then a data byte with the high bits.
	psg.write(0x8E)
	psg.write(0x4F)
	check_eq(psg.tone_period(0), 0xFE, "tone period from latch and data")
	# A latch alone changes only the low bits.
	psg.write(0x81)
	check_eq(psg.tone_period(0), 0xF1, "latch keeps the high bits")
	psg.write(0x90 | 3)
	check_eq(psg.attenuation(0), 3, "volume latch")
	psg.write(0xE5)
	check_eq(psg.noise_control(), 5, "noise control")
	check_eq(SmsSong.tone_period(69), 254, "A4 is period 254")
	check_eq(SmsSong.tone_period(45), 1017, "A2 is the lowest note")
	check_eq(SmsSong.level_of(15), 15)
	check_eq(SmsSong.level_of(0), 0)
	check_eq(SmsSong.level_of(0.01), 1, "audible volumes stay audible")
	check_eq(SmsSong.level_of(7.5), 12, "half amplitude is 6 dB down")
	check_eq(SmsSong.mix_level(14, 15), 14)
	check_eq(SmsSong.mix_level(14, 3), 2)
	check_eq(SmsSong.mix_level(3, 3), 0)


func test_chip_makes_sound() -> void:
	var psg := SmsPsg.new(22050.0)
	psg.write(0x8E)
	psg.write(0x4F)
	psg.write(0x90)
	var out := PackedFloat32Array()
	out.resize(4410)
	psg.render(out, 0, out.size())
	var peak := 0.0
	var crossings := 0
	for i in range(1, out.size()):
		peak = maxf(peak, absf(out[i]))
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
	check(peak > 0.15 and peak <= 0.3, "one channel at full volume (peak %s)" % peak)
	# 440 Hz for 0.2 s: about 176 sign changes.
	check_near(float(crossings), 176.0, 8.0, "plays A4")
	psg.write(0x9F)
	psg.write(0xF0)
	psg.write(0xE4)
	psg.render(out, 0, out.size())
	var noisy := 0.0
	for s in out:
		noisy = maxf(noisy, absf(s))
	check(noisy > 0.1, "white noise plays (peak %s)" % noisy)


func test_arranged_notes_fit_the_chip() -> void:
	var sms := SmsArranger.arrange(_song())
	check(sms.row_count > 0, "has rows")
	check(sms.note_count() > 50, "plays plenty of notes (%d)" % sms.note_count())
	check(absf(sms.frame_hz - SmsSong.FRAME_HZ) < 0.001, "NTSC frame rate")
	check_near(sms.get_bpm(), _song().get_bpm(), _song().get_bpm() * 0.025, "keeps the tempo")
	for c in 4:
		var last := -1
		for n: Dictionary in sms.notes[c]:
			var note := int(n["note"])
			check(int(n["row"]) > last, "one note per row, in order")
			last = int(n["row"])
			check(int(n["volume"]) >= 1 and int(n["volume"]) <= 15, "volume")
			if c == SmsSong.NOISE:
				check(note >= 0 and note <= 2, "noise rate")
			else:
				check(note >= SmsSong.LOWEST_NOTE and note <= SmsSong.HIGHEST_NOTE, "note %d on channel %d" % [note, c])
	for inst: Dictionary in sms.instruments:
		for v in inst.get("volume", []):
			check(int(v) >= 0 and int(v) <= 15, "volume level")
		check(not inst.has("duty") or (inst["duty"] as Array) == [1], "only noise mode in duty")
	check(sms.report[0].begins_with("Square 1"), "report names the SMS channels")
	for line in sms.report:
		check(not line.contains("Pulse") and not line.contains("Triangle"), "no NES names: " + line)
	var source: Dictionary = sms.source.data
	check_eq(source["meta"]["target"], "sms")
	check_eq(source["channels"][2]["name"], "Square 3")


func test_engine_plays_and_loops() -> void:
	var sms := SmsArranger.arrange(_song())
	var seq := SmsSequencer.new(sms, 22050)
	var loops := 0
	var peak := 0.0
	var seconds := sms.frames_before(sms.row_count) / SmsSong.FRAME_HZ + 2.0
	for i in int(seconds * 22050 / 2048):
		var frames := seq.render(2048)
		for f in frames:
			peak = maxf(peak, absf(f.x))
		for e in seq.events:
			if e[0] == ChipSongSequencer.EventType.LOOPED:
				loops += 1
	check(peak > 0.1, "makes sound (peak %s)" % peak)
	check(peak <= 1.0, "no clipping past full scale")
	check_eq(loops, 1, "loops once")


func test_muted_channels_are_silent() -> void:
	var song := _song()
	var sms := SmsArranger.arrange(song)
	var seq := SmsSequencer.new(sms, 22050, song.data["channels"].size())
	for c in song.data["channels"].size():
		seq.set_channel_muted(c, true)
	seq.seek_step(0)
	var peak := 0.0
	for i in 20:
		for f in seq.render(2048):
			peak = maxf(peak, absf(f.x))
	check(peak < 0.02, "silent when every part is muted (peak %s)" % peak)


func test_player_writes_only_changes() -> void:
	var sms := SmsSong.new()
	sms.groove = PackedInt32Array([2])
	sms.row_count = 4
	sms.looping = false
	sms.section_rows = [{"name": "A", "row": 0, "length": 4}]
	sms.instruments = [{"name": "T", "volume": [15, 13, 13]}]
	sms.notes[0] = [{"row": 0, "length": 2, "note": 69, "instrument": 0, "volume": 15, "arp": -1}]
	sms.notes[3] = [{"row": 1, "length": 1, "note": 1, "instrument": 0, "volume": 15, "arp": -1}]
	var recorded := PsgWriter.record(sms)
	var frames: Array = recorded["frames"]
	check_eq(frames.size(), 8, "two frames a row")
	# Frame 0 sets every register: tone 0 (latch, data), its volume, then the
	# silent volumes of the other channels.
	check_eq(Array(frames[0]), [0x8E, 0x4F, 0x90, 0xBF, 0xDF, 0xFF], "first frame")
	check_eq(Array(frames[1]), [0x92], "envelope steps down 2 dB")
	check_eq(Array(frames[2]), [0xE5, 0xF0], "noise hit: white, rate 1, full volume")
	check_eq(Array(frames[3]), [0xF2], "only what changed")
	check_eq(Array(frames[4]), [0x9F, 0xFF], "notes stop at their length")
	check_eq(Array(frames[7]), [], "nothing left to write")
	var psg := PsgWriter.encode(recorded)
	check_eq(Array(psg), [0x8E, 0x4F, 0x90, 0xBF, 0xDF, 0xFF, 0x38, 0x92, 0x38, 0xE5, 0xF0, 0x38, 0xF2, 0x38, 0x9F, 0xFF, 0x3B, 0x00], "PSGlib data")


func test_psg_data_loops_with_every_register() -> void:
	var sms := SmsArranger.arrange(_song())
	var recorded := PsgWriter.record(sms)
	var psg := PsgWriter.encode(recorded)
	check_eq(psg[psg.size() - 1], 0x00, "ends with the end marker")
	var markers := 0
	var at := -1
	for i in psg.size():
		var b := psg[i]
		check(b >= 0x38 or b <= 0x01, "only writes, waits and markers")
		if b == 0x01:
			markers += 1
			at = i
	check_eq(markers, 1, "one loop marker")
	# After the marker, all four volumes are written before the first wait.
	var volumes := {}
	var i := at + 1
	while i < psg.size() and not (psg[i] >= 0x38 and psg[i] <= 0x3F):
		if (psg[i] & 0x90) == 0x90:
			volumes[(psg[i] >> 5) & 3] = true
		i += 1
	check_eq(volumes.size(), 4, "loop point writes every volume")
	var vgm := PsgWriter.vgm_bytes(recorded)
	check_eq(vgm.slice(0, 4).get_string_from_ascii(), "Vgm ")
	check_eq(vgm.decode_u32(0x04), vgm.size() - 4, "end of file offset")
	check_eq(vgm.decode_u32(0x0C), 3579545, "SN76489 clock")
	check_eq(vgm.decode_u32(0x18), (recorded["frames"] as Array).size() * 735, "length in samples")
	check(vgm.decode_u32(0x1C) > 0, "loop offset")
	check_eq(vgm[vgm.size() - 1], 0x66, "ends with the end command")


func test_psg_golden() -> void:
	var sms := SmsArranger.arrange(_song())
	var psg := PsgWriter.song_bytes(sms)
	var blobs := {"tune_psg": psg}
	check_golden("sms_song_happy_platformer.c", PsgWriter.c_source(blobs, "tune_psg.h", sms.title))


func test_sfx_conversion() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := SmsSfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check_eq(coin.channel, SmsSong.SQUARE3)
	check_eq(coin.psglib_channel(), "SFX_CHANNEL2")
	check_eq(coin.volume[coin.frame_count() - 1], 0, "ends silent")
	var boom := SmsSfx.from_sfx(SfxGenerator.make_sfx(presets["explosion"], 1), "boom")
	check_eq(boom.channel, SmsSong.NOISE)
	check_eq(boom.psglib_channel(), "SFX_CHANNEL3")
	var peak := 0.0
	for s in coin.render(22050):
		peak = maxf(peak, absf(s))
	check(peak > 0.05, "coin makes sound (peak %s)" % peak)
	# A sound writes only its own channel, so the music keeps the others.
	for sfx: SmsSfx in [coin, boom]:
		var psg := PsgWriter.sfx_bytes(sfx)
		for b in psg:
			if b & 0x80:
				check_eq((b >> 5) & 3, sfx.channel, "%s writes only its channel" % sfx.name)
		check_eq(psg[psg.size() - 1], 0x00)


func test_export_jobs() -> void:
	var sms := SmsArranger.arrange(_song())
	var job := ExportJob.for_sms_song(sms, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	for path in ["sms/tune.psg", "sms/tune.vgm", "sms/tune_psg.c", "sms/tune_psg.h", "sms/README.txt", "midi/tune.mid", "README.txt"]:
		check(job.files.has(path), path)
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	check((job.files["sms/tune_psg.h"] as PackedByteArray).get_string_from_utf8().contains("extern const unsigned char tune_psg["), "C header")
	check((job.files["sms/README.txt"] as PackedByteArray).get_string_from_utf8().contains("PSGPlay(tune_psg)"), "how to play it")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_sms_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	for path in ["audio/coin.wav", "sms/coin.psg", "sms/coin.vgm", "sms/my_kit.c", "sms/my_kit.h", "sms/README.txt"]:
		check(kit.files.has(path), path)
	check((kit.files["sms/README.txt"] as PackedByteArray).get_string_from_utf8().contains("PSGSFXPlay(coin_psg, SFX_CHANNEL2)"), "how to play the sound")
