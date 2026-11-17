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


func test_ticks_at_impulse_trackers_rate() -> void:
	check_eq(SnesSong.tick_hz(125, true), 50.0, "tempo 125 ticks 50 times a second")
	var gba := GbaArranger.arrange(_song())
	check(gba.standard_ticks, "standard ticks")
	check_eq(gba.frame_hz, gba.tempo * 0.4, "frame rate follows the tempo")
	var bpm := gba.frame_hz / gba.speed() * 60.0 / gba.steps_per_beat
	check(absf(bpm - _song().get_bpm()) / _song().get_bpm() < 0.03, "plays near the song's tempo (%f)" % bpm)


func test_arrangement() -> void:
	var gba := GbaArranger.arrange(_song())
	check_eq(int(gba.echo["edl"]), 0, "no echo")
	check(gba.source.data["meta"]["target"] == "gba", "source")
	check((gba.notes[SnesSong.SFX_CHANNEL] as Array).is_empty(), "channel 8 left free")
	var text := "\n".join(gba.report)
	check(not text.contains("SNES") and not text.contains("Audio RAM") and not text.contains("Voice"), "report speaks of the GBA")
	check(text.contains("Maxmod"), "report names Maxmod")


func test_module_has_8_bit_samples() -> void:
	var gba := GbaArranger.arrange(_song())
	var it := GbaWriter.module_bytes(gba)
	check(it.slice(0, 4).get_string_from_ascii() == "IMPM", "an Impulse Tracker module")
	var ins := it.decode_u16(0x22)
	var smp := it.decode_u16(0x24)
	var ord := it.decode_u16(0x20)
	var pointers := 0xC0 + ord
	for i in smp:
		var at := it.decode_u32(pointers + (ins + i) * 4)
		check(it.slice(at, at + 4).get_string_from_ascii() == "IMPS", "sample header")
		check((it[at + 0x12] & 2) == 0, "8-bit sample")


func test_sequencer_plays() -> void:
	var gba := GbaArranger.arrange(_song())
	var seq := GbaSequencer.new(gba, 22050)
	seq.seek_step(0)
	var out := seq.render(22050 * 3)
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v.x))
	check(peak > 0.1, "audible (%f)" % peak)


func test_sfx() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := GbaSfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check(_peak(coin.render(22050)) > 0.05, "coin plays")
	check_eq(GbaSfx.symbol("coin"), "SFX_COIN", "mmutil's id")
	var wav := coin.wav_bytes()
	check_eq(wav.decode_u32(24), 16384, "16 kHz")


func test_export_jobs() -> void:
	var gba := GbaArranger.arrange(_song())
	var job := ExportJob.for_gba_song(gba, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	for path in ["gba/audio/tune.it", "gba/Makefile", "gba/main.c", "gba/README.txt", "midi/tune.mid", "README.txt", "audio/tune.wav"]:
		check(job.files.has(path), path)
	check((job.files["gba/main.c"] as PackedByteArray).get_string_from_utf8().contains("mmStart(MOD_TUNE, MM_PLAY_LOOP);"), "main.c plays the module")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_gba_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	for path in ["audio/coin.wav", "gba/audio/coin.wav", "gba/README.txt", "README.txt"]:
		check(kit.files.has(path), path)
	check((kit.files["gba/README.txt"] as PackedByteArray).get_string_from_utf8().contains("mmEffect(SFX_COIN);"), "how to play a sound")
