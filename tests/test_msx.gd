extends "res://tests/test_case.gd"


func _song(vibe := "happy", style := "platformer", seed_text := "42") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return SongGenerator.generate(s)


func _peak(out: PackedFloat32Array) -> float:
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	return peak


func test_periods_and_levels() -> void:
	check_eq(AySong.tone_period(69), 254, "A4 = 1789772.5 / (16 x 440)")
	check_eq(AySong.tone_period(69, AyPsg.CLOCK_ZX), 252, "the Spectrum's clock is a little slower")
	check_eq(AySong.tone_period(57), 508, "an octave down doubles it")
	check_eq(AySong.noise_period(0), 1, "highest noise")
	check_eq(AySong.noise_period(15), 31, "lowest noise")
	check_eq(AySong.level_of(15), 15, "full")
	check_eq(AySong.level_of(0), 0, "silent")
	check_eq(AySong.level_of(0.1), 1, "anything audible stays audible")


func test_psg_plays_tone_and_noise() -> void:
	var psg := AyPsg.new(44100.0)
	psg.write(0, 254)
	psg.write(1, 0)
	psg.write(AyPsg.MIXER, 0xBE)
	psg.write(8, 15)
	var out := PackedFloat32Array()
	out.resize(44100)
	psg.render(out, 0, 44100)
	var crossings := 0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
	check(absi(crossings - 880) < 20, "a square at 440 Hz (%d crossings)" % crossings)
	var loud := _peak(out.slice(22050))
	check(loud > 0.1, "loud (%f)" % loud)
	psg.write(8, 0)
	psg.write(6, 20)
	psg.write(AyPsg.MIXER, 0xB7)
	psg.write(9, 0)
	psg.render(out, 0, 44100)
	check(_peak(out.slice(4410)) < 0.01, "a channel at volume 0 is silent")
	psg.write(AyPsg.MIXER, 0xAF)
	psg.write(9, 15)
	psg.render(out, 0, 44100)
	check(_peak(out) > 0.1, "noise on channel B plays")


func test_arranged_parts_fit() -> void:
	var ay := AyArranger.arrange(_song())
	check_eq(ay.notes.size(), 4, "four parts")
	for c in 4:
		check(not (ay.notes[c] as Array).is_empty(), "%s has notes" % AySong.AY_CHANNEL_NAMES[c])
	for c in 3:
		for n in ay.notes[c]:
			check(int(n["note"]) >= AySong.LOWEST_NOTE and int(n["note"]) <= AySong.HIGHEST_NOTE, "in range")
	check(not ay.report.is_empty(), "report")
	check(ay.source.data["meta"]["target"] == "msx", "source")


func test_drums_borrow_channel_b() -> void:
	var ay := AyArranger.arrange(_song())
	var player := AyPlayer.new(ay, AyPsg.new(8000.0))
	var noise_frames := 0
	var tone_frames := 0
	for f in 600:
		player.tick()
		var mixer := player.regs[AyPsg.MIXER]
		check((mixer & 0x09) == 0x08, "A plays tone only")
		check((mixer & 0x24) == 0x20, "C plays tone only")
		if (mixer & 0x10) == 0:
			noise_frames += 1
			check((mixer & 0x02) != 0, "no tone under the drums")
		else:
			tone_frames += 1
	check(noise_frames > 20 and tone_frames > 20, "B takes turns (%d noise, %d tone)" % [noise_frames, tone_frames])


func test_exported_data_plays_like_the_preview() -> void:
	for entry in [["happy", "platformer", "42"], ["boss_fight", "metal", "boss"], ["calm", "rpg_town", "7"]]:
		var ay := AyArranger.arrange(_song(entry[0], entry[1], entry[2]))
		for machine in AyWriter.MACHINES:
			var clock: float = AyWriter.MACHINES[machine]
			var rec := AyWriter.record_song(ay, clock)
			var frames: Array = rec["frames"]
			var data := AyWriter.song_bytes(ay, clock)
			check(data.size() < 0x8000, "%s fits a cartridge (%d bytes for %d frames)" % [entry[0], data.size(), frames.size()])
			# Through the loop and on for half the song again.
			var count := frames.size() + frames.size() / 2
			var decoded := AyWriter.decode_song(data, count)
			var loop_frame := int(rec["loop_frame"])
			var first := -1
			for f in count:
				var want: PackedInt32Array = frames[f] if f < frames.size() else frames[loop_frame + (f - frames.size())]
				var got: PackedInt32Array = decoded[f]
				var same := true
				for r in AyWriter.REGS:
					var mask := 0x3F if r == AyPsg.MIXER else 0xFF
					if (want[r] & mask) != (got[r] & mask):
						same = false
				if not same:
					first = f
					break
			check_eq(first, -1, "%s on %s: the Z80 player's data matches the preview on every frame, through the loop" % [entry[0], machine])


func test_sequencer_plays() -> void:
	var ay := AyArranger.arrange(_song())
	var seq := AySequencer.new(ay, 22050)
	seq.seek_step(0)
	var out := seq.render(22050 * 3)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v.x))
	check(peak > 0.1, "audible (%f)" % peak)


func test_sfx() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := AySfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check(not coin.noise, "coin is tonal")
	check(_peak(coin.render(22050)) > 0.05, "coin plays")
	var boom := AySfx.from_sfx(SfxGenerator.make_sfx(presets["explosion"], 1), "explosion")
	check(boom.noise, "explosion is noise")
	check(_peak(boom.render(22050)) > 0.05, "explosion plays")
	var data := AyWriter.sfx_bytes([coin, boom])
	for i in 2:
		var sfx: AySfx = [coin, boom][i]
		var want := AyWriter.record_sfx(sfx)
		var got := AyWriter.decode_sfx(data, i)
		check_eq(got.size(), want.size(), "%s: every frame" % sfx.name)
		var same := true
		for f in mini(got.size(), want.size()):
			for r in [2, 3, 6, 9]:
				if got[f][r] != want[f][r]:
					same = false
			if (got[f][7] & 0x12) != (want[f][7] & 0x12):
				same = false
		check(same, "%s: the Z80 player plays it as the preview does" % sfx.name)


func test_vgm() -> void:
	var ay := AyArranger.arrange(_song())
	var vgm := AyWriter.vgm_bytes(ay)
	check_eq(vgm.decode_u32(0), 0x206D6756, "VGM magic")
	check_eq(vgm.decode_u32(0x74), 1789772, "AY clock")
	check(vgm.decode_u32(0x1C) > 0, "loops")


func test_export_jobs() -> void:
	var ay := AyArranger.arrange(_song())
	var job := ExportJob.for_ay_song(ay, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	for path in ["msx/song_msx.bin", "msx/song_zx.bin", "msx/song.vgm", "msx/ay_player.asm", "msx/msx_main.asm", "msx/zx_main.asm", "msx/Makefile", "msx/README.txt", "midi/tune.mid", "README.txt"]:
		check(job.files.has(path), path)
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	check((job.files["msx/ay_player.asm"] as PackedByteArray).get_string_from_utf8().contains("MIT License"), "the player is MIT")
	check((job.files["msx/Makefile"] as PackedByteArray).get_string_from_utf8().contains("tune.rom"), "Makefile names the ROM")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_ay_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	for path in ["audio/coin.wav", "msx/sfx_msx.bin", "msx/sfx_zx.bin", "msx/ay_player.asm", "msx/README.txt", "README.txt"]:
		check(kit.files.has(path), path)
	check((kit.files["msx/README.txt"] as PackedByteArray).get_string_from_utf8().contains("call ay_sfx_play"), "how to play a sound")
