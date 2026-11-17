extends "res://tests/test_case.gd"


func _song(style := "rock", seed_text := "opl") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign(["happy"])
	s.style = style
	s.seed_text = seed_text
	s.length_seconds = 30
	return SongGenerator.generate(s)


func _peak(out: PackedFloat32Array) -> float:
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	return peak


func _crossings(out: PackedFloat32Array) -> int:
	var count := 0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			count += 1
	return count


func test_frequency_numbers() -> void:
	var bf := OplSong.fnum_of(440.0)
	var hz: float = bf[1] * Opl.CHIP_RATE / pow(2.0, 20 - bf[0])
	check(absf(hz - 440.0) < 1.0, "A4's block and F-number play 440 Hz (%.2f)" % hz)
	check(bf[1] < 1024, "the F-number fits 10 bits")
	check_eq(OplSong.fnum_of(220.0)[0], bf[0] - 1, "an octave down is one block lower")
	check_eq(OplSong.level_atten(15), 0, "full level is no attenuation")
	check(OplSong.level_atten(1) > OplSong.level_atten(8), "quieter levels attenuate more")


func test_chip_plays_a_sine() -> void:
	var chip := Opl.new(44100.0)
	chip.write(0, 0x01, 0x20)
	var patch := {"fb": 0, "cnt": 0, "mod": OplPatches.op(1, 63, 15, 0, 0, 15), "car": OplPatches.op(1, 0, 15, 0, 0, 15)}
	for w in OplSong.patch_registers(0, patch):
		chip.write(0, w[0], w[1])
	var bf := OplSong.fnum_of(440.0)
	chip.write(0, 0xA0, bf[1] & 0xFF)
	chip.write(0, 0xB0, 0x20 | (bf[0] << 2) | (bf[1] >> 8))
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(44100)
	right.resize(44100)
	chip.render(left, right, 0, 44100)
	var crossings := _crossings(left.slice(4410))
	check(absi(crossings - 794) < 12, "a 440 Hz sine (%d crossings in 0.9 s)" % crossings)
	check(_peak(left) > 0.05, "loud enough")
	chip.write(0, 0xB0, (bf[0] << 2) | (bf[1] >> 8))
	left.fill(0.0)
	right.fill(0.0)
	chip.render(left, right, 0, 44100)
	check(_peak(left.slice(22050)) < 0.001, "keying off lets the fast release die away")


func test_rhythm_mode_drums_sound() -> void:
	var opl := OplArranger.arrange(_song(), "adlib")
	check(opl.rhythm_on(0), "the AdLib arrangement uses the rhythm mode")
	var drums := 0
	for v in opl.layout:
		if str(v["drum"]) != "":
			drums += 1
	check_eq(drums, 5, "five drum parts")
	check_eq(opl.layout.size(), 11, "six melodic parts and five drums")


func test_arrangements_for_each_card() -> void:
	var song := _song()
	for card in PcCards.CARDS:
		var opl := OplArranger.arrange(song, card)
		check_eq(opl.card, card, card)
		check_eq(opl.chip, PcCards.chip_of(card), "%s chip" % card)
		check(opl.note_count() > 50, "%s has the song's notes (%d)" % [card, opl.note_count()])
		check(not opl.report.is_empty(), "%s reports what it did" % card)
		var seq := OplSequencer.new(opl, 22050, song.data["channels"].size())
		var buf := seq.render(22050 * 3)
		var peak := 0.0
		for v in buf:
			peak = maxf(peak, absf(v.x))
		check(peak > 0.05 and peak <= 1.0, "%s plays (peak %.2f)" % [card, peak])


func test_arranging_is_deterministic() -> void:
	var a := OplWriter.dro_bytes(OplWriter.record(OplArranger.arrange(_song(), "sb16")), "opl3")
	var b := OplWriter.dro_bytes(OplWriter.record(OplArranger.arrange(_song(), "sb16")), "opl3")
	check(a == b, "the same song gives the same DRO file")


func test_file_formats() -> void:
	var opl := OplArranger.arrange(_song(), "adlib")
	var rec := OplWriter.record(opl)
	check(rec["frames"].size() > 70 * 20, "about 30 s of frames (%d)" % rec["frames"].size())
	var imf := OplWriter.imf_bytes(rec, "Test")
	var length := imf.decode_u16(0)
	check(length > 0 and length % 4 == 0, "IMF type 1 starts with the data length")
	check_eq(imf[length + 2], 0x1A, "and ends with the footer tag")
	check_eq(imf.decode_u32(2), 0, "the first record is empty, as players expect")
	var dro := OplWriter.dro_bytes(rec, "opl2")
	check_eq(dro.slice(0, 8).get_string_from_ascii(), "DBRAWOPL", "DRO signature")
	check_eq(dro.decode_u16(8), 2, "DRO version 2")
	check_eq(dro[20], 0, "hardware type OPL2")
	check_eq(OplWriter.dro_bytes(OplWriter.record(OplArranger.arrange(_song(), "sbpro")), "dual_opl2")[20], 1, "dual OPL2")
	check_eq(OplWriter.dro_bytes(OplWriter.record(OplArranger.arrange(_song(), "sb16")), "opl3")[20], 2, "OPL3")
	var vgm := OplWriter.vgm_bytes(rec, "opl2", "Test")
	check_eq(vgm.slice(0, 4).get_string_from_ascii(), "Vgm ", "VGM signature")
	check_eq(vgm.decode_u32(0x50), 3579545, "YM3812 clock")
	check_eq(vgm.decode_u32(4) + 4, vgm.size(), "the end-of-file offset matches")
	var vgm3 := OplWriter.vgm_bytes(OplWriter.record(OplArranger.arrange(_song(), "sb16")), "opl3", "Test")
	check_eq(vgm3.decode_u32(0x5C), 14318180, "YMF262 clock")


func test_sound_effects_for_each_card() -> void:
	var sfx := SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("coin"), 3)
	var noisy := SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("explosion"), 3)
	var adlib := PcSfx.from_sfx(sfx, "adlib")
	check(adlib.is_fm(), "the AdLib plays effects as FM")
	check(_peak(adlib.render(22050)) > 0.05, "and it sounds")
	check(PcSfx.from_sfx(noisy, "adlib").noisy, "an explosion uses the noisy patch")
	check(adlib.opl_frames().size() == adlib.volume.size() + 1, "a frame per 70th of a second, then key off")
	var sb := PcSfx.from_sfx(sfx, "sb")
	check_eq(sb.rate, 11025, "the Sound Blaster plays samples at 11 kHz")
	var voc := sb.voc_bytes()
	check_eq(voc.slice(0, 19).get_string_from_ascii(), "Creative Voice File", "VOC signature")
	check_eq(voc[26], 1, "a sound data block")
	check_eq(voc[30], 256 - roundi(1000000.0 / 11025), "with the 11 kHz time constant")
	check_eq(voc[voc.size() - 1], 0, "and a terminator")
	var sb16 := PcSfx.from_sfx(sfx, "sb16")
	check_eq(sb16.bits, 16, "16-bit on the Sound Blaster 16")
	var wav := sb16.wav_bytes()
	check_eq(wav.decode_u16(34), 16, "a 16-bit WAV")
	check_eq(wav.decode_u32(24), 22050, "at 22 kHz")


func test_export_jobs() -> void:
	var song := _song()
	var job := ExportJob.for_target_song("pc", song, {"prefix": "tune", "wav": false, "card": "adlib"}, null)
	job.run()
	for path in ["pc/tune.wlf", "pc/tune.dro", "pc/tune.vgm", "pc/README.txt", "README.txt"]:
		check(job.files.has(path), "AdLib export has %s" % path)
	job = ExportJob.for_target_song("pc", song, {"prefix": "tune", "wav": false, "card": "sb16"}, null)
	job.run()
	check(not job.files.has("pc/tune.wlf"), "no IMF for the OPL3")
	check(job.files.has("pc/tune.dro") and job.files.has("pc/tune.vgm"), "DRO and VGM for the OPL3")
	var sounds := {"coin": SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("coin"), 1)}
	job = ExportJob.for_target_sfx("pc", sounds, "kit", {"card": "sbpro", "wav": true})
	job.run()
	check(job.files.has("pc/coin.voc"), "a VOC for the Sound Blaster Pro")
	check(job.files.has("audio/coin.wav"), "and a WAV of it")
	job = ExportJob.for_target_sfx("pc", sounds, "kit", {"card": "adlib", "wav": false})
	job.run()
	check(job.files.has("pc/coin.dro") and job.files.has("pc/coin.wlf"), "FM sound files for the AdLib")


func test_report_and_project_keep_the_card() -> void:
	var song := _song()
	var opl := OplArranger.arrange(song, "sbpro")
	var report := TargetReport.lines("pc", true, song, opl, {}, "sbpro")
	check(TargetReport.fits(report), "the arrangement fits")
	check("\n".join(report).contains("Sound Blaster Pro"), "the report names the card")
	var text := ProjectFile.for_song(song, SongSettings.new(), "pc", {"card": "sbpro"})
	var project := ProjectFile.parse(text)
	check_eq(project["gameboy"].get("card"), "sbpro", "the project remembers the card")
	var kit := ProjectFile.parse(ProjectFile.for_kit("k", {}, "pc", "sb16"))
	check_eq(kit["card"], "sb16", "and so does a kit")


func test_pc_speaker() -> void:
	var song := _song("platformer", "42")
	var sp: SpeakerSong = PcCards.arrange(song, "speaker")
	check(sp is SpeakerSong, "the speaker gets its own arrangement")
	check_eq(sp.notes.size(), 3, "lead, bass and drums")
	check((sp.notes[SpeakerSong.LEAD] as Array).size() > 20, "the lead plays")
	for n in sp.notes[SpeakerSong.BASS]:
		check(int(n["note"]) >= SpeakerSong.LOWEST, "the bass fits the speaker")
		break
	check_eq(SpeakerSong.divisor_of(440.0), 2712, "A4 is PIT divisor 2712")
	var rec := SpeakerWriter.record(sp)
	var slots: PackedInt32Array = rec["slots"]
	check_eq(slots.size(), sp.frames_before(sp.row_count) * 2, "two tones a frame")
	var sounding := 0
	for d in slots:
		if d > 0:
			sounding += 1
	check(sounding > slots.size() / 3, "the speaker is busy (%d of %d)" % [sounding, slots.size()])
	var header := SpeakerWriter.c_header("song_test", slots, int(rec["loop_slot"]), "test")
	check(header.contains("#define SONG_TEST_TICKS %d" % slots.size()), "the header gives the length")
	check(header.contains("#define SONG_TEST_LOOP %d" % int(rec["loop_slot"])), "and the loop")
	var bin := SpeakerWriter.bin_bytes(slots)
	check_eq(bin.decode_u16(20), slots[10], "the binary holds the divisors")
	var seq := SpeakerSequencer.new(sp, 22050, song.data["channels"].size())
	var buf := seq.render(22050 * 3)
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v.x))
	check(peak > 0.1 and peak <= 1.0, "the speaker preview plays (peak %.2f)" % peak)
	var job := ExportJob.for_target_song("pc", song, {"prefix": "tune", "wav": false, "card": "speaker"}, sp)
	job.run()
	for path in ["pc/song_tune.h", "pc/song_tune.bin", "pc/speaker.c", "pc/speaker.h", "pc/main.c", "pc/makefile"]:
		check(job.files.has(path), "speaker export has %s" % path)
	var sfx := PcSfx.from_sfx(SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("coin"), 3), "speaker")
	check(not sfx.slots.is_empty(), "a speaker sound has tones")
	check(_peak(sfx.render(22050)) > 0.1, "and sounds")


func test_tandy() -> void:
	var song := _song()
	var sms: SmsSong = PcCards.arrange(song, "tandy")
	check_eq(sms.noise_taps, 0x0006, "the SN76496's white noise")
	check(not "\n".join(sms.report).contains("Master System"), "the report talks about the Tandy")
	var rec := PsgWriter.record(sms)
	var vgm := PsgWriter.vgm_bytes(rec, sms.noise_taps, sms.noise_width, OplWriter.gd3("t", "IBM PC, Tandy 1000", ""))
	check_eq(vgm.decode_u16(0x28), 0x0006, "VGM noise feedback")
	check_eq(vgm.decode_u32(0x04) + 4, vgm.size(), "the end-of-file offset covers the GD3 tag")
	check(vgm.decode_u32(0x14) > 0, "with a GD3 tag")
	var psg := SmsPsg.new(44100.0)
	psg.noise_taps = 0x0006
	psg.reset()
	psg.write(0xE4)
	psg.write(0xF0)
	var out := PackedFloat32Array()
	out.resize(4410)
	psg.render(out, 0, 4410)
	check(_peak(out) > 0.05, "white noise plays with the SN76496's taps")
	var sfx := PcSfx.from_sfx(SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("explosion"), 3), "tandy")
	check(sfx.noisy, "an explosion on the noise channel")
	check(_peak(sfx.render(22050)) > 0.05, "and it sounds")


func _midi_has(bytes: PackedByteArray, needle: PackedByteArray) -> bool:
	for i in bytes.size() - needle.size():
		if bytes.slice(i, i + needle.size()) == needle:
			return true
	return false


func test_roland_checksums() -> void:
	check_eq(ModuleArranger.roland_checksum([0x10, 0x00, 0x01, 0x00]), 0x6F, "the MT-32 manual's reverb example")
	check(ModuleArranger.roland_sysex(0x42, [0x40, 0x00, 0x7F], [0x00]) == PackedByteArray([0xF0, 0x41, 0x10, 0x42, 0x12, 0x40, 0x00, 0x7F, 0x00, 0x41, 0xF7]), "the GS reset")


func test_mt32() -> void:
	var song := _song()
	var mod: ModuleSong = PcCards.arrange(song, "mt32")
	check(mod is ModuleSong, "the MT-32 gets a module arrangement")
	var drums := 0
	for c in mod.parts:
		var part: Dictionary = mod.parts[c]
		if int(part["midi"]) == 9:
			drums += 1
		else:
			check(int(part["midi"]) >= 1 and int(part["midi"]) <= 8, "parts on channels 2 to 9")
			check(ModuleArranger.MT32_NAMES.has(int(part["program"])), "a named MT-32 preset")
	check(drums >= 1, "drums on channel 10")
	check(mod.peak <= 32, "within the 32 partials (%d)" % mod.peak)
	check_eq(mod.sysex.size(), 4, "display, reverb, partial reserve and channels")
	var reserve: PackedByteArray = mod.sysex[2]
	var total := 0
	for i in range(8, 17):
		total += reserve[i]
	check_eq(total, 32, "the partial reserve adds up to 32")
	for message: PackedByteArray in mod.sysex:
		var body: Array = Array(message.slice(5, message.size() - 2))
		check_eq(message[message.size() - 2], ModuleArranger.roland_checksum(body), "checksums")
	var midi := mod.midi_bytes()
	check_eq(midi.slice(0, 4).get_string_from_ascii(), "MThd", "a MIDI file")
	check(_midi_has(midi, PackedByteArray([0xF0, 0x0C, 0x41, 0x10, 0x16, 0x12, 0x10, 0x00, 0x01, 0x00, 0x05, 0x04, 0x66, 0xF7])), "with the reverb SysEx as an F0 event")
	check(not "\n".join(mod.report).is_empty(), "a report")
	var seq := ChipSongSequencer.new(mod.preview, 22050)
	var buf := seq.render(22050 * 2)
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v.x))
	check(peak > 0.05, "the preview plays (%.2f)" % peak)
	var job := ExportJob.for_target_song("pc", song, {"prefix": "tune", "wav": false, "card": "mt32"}, mod)
	job.run()
	check(job.files.has("pc/tune.mid") and job.files.has("pc/README.txt"), "the export has the MIDI file")


func test_sound_canvas() -> void:
	var song := _song()
	var mod: ModuleSong = PcCards.arrange(song, "gm")
	check(mod.peak <= 24, "within 24 voices (%d)" % mod.peak)
	var midi := mod.midi_bytes()
	check(_midi_has(midi, PackedByteArray([0xF0, 0x05, 0x7E, 0x7F, 0x09, 0x01, 0xF7])), "GM System On")
	for c in mod.parts:
		var part: Dictionary = mod.parts[c]
		if int(part["midi"]) != 9:
			check(_midi_has(midi, PackedByteArray([0xC0 | int(part["midi"]), int(part["program"])])), "program change for channel %d" % (int(part["midi"]) + 1))
	var plain := MidiWriter.encode(song)
	check(plain == MidiWriter.encode_setup(song, {}), "plain MIDI export is unchanged")
	var sfx := PcSfx.from_sfx(SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("coin"), 3), "gm")
	check(sfx.is_sample() and sfx.rate == 22050, "sounds go to a Sound Blaster beside the module")


func test_pad_chords_trim_to_fit() -> void:
	var song := _song()
	var parts := {}
	for c in song.data["channels"].size():
		parts[c] = {"midi": 9 if str(song.data["channels"][c].get("layer", "")) == "Drums" else c}
	var full := ModuleArranger.peak_of(song, parts, {}, 4)
	var pad := -1
	for c in song.data["channels"].size():
		if str(song.data["channels"][c].get("name", "")) == "Pad":
			pad = c
	if pad >= 0:
		check(ModuleArranger.peak_of(song, parts, {pad: 1}, 4) <= full, "cutting chords lowers the peak")


func test_gravis_ultrasound() -> void:
	var song := _song()
	var gus: GusSong = PcCards.arrange(song, "gus")
	check(gus is GusSong, "the GUS gets its own arrangement")
	check(gus.standard_ticks, "at Impulse Tracker's tick rate")
	check_eq(int(gus.echo["evol"]), 0, "no echo")
	check(not "\n".join(gus.report).contains("SNES"), "the report talks about the GUS (%s)" % "\n".join(gus.report))
	var it := ItWriter.module_bytes(gus, false)
	check_eq(it.slice(0, 4).get_string_from_ascii(), "IMPM", "an Impulse Tracker module")
	var seq := GusSequencer.new(gus, 22050, song.data["channels"].size())
	var buf := seq.render(22050 * 3)
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v.x))
	check(peak > 0.05 and peak <= 1.0, "the GUS preview plays (%.2f)" % peak)
	var job := ExportJob.for_target_song("pc", song, {"prefix": "tune", "wav": false, "card": "gus"}, gus)
	job.run()
	check(job.files.has("pc/tune.it"), "the export has the module")
	var sfx := PcSfx.from_sfx(SfxGenerator.make_sfx(Catalog.get_default().get_sfx_preset("coin"), 3), "gus")
	check_eq(sfx.bits, 16, "16-bit sounds")
