extends "res://tests/test_case.gd"


func _song(vibe := "happy", style := "platformer", seed_text := "42") -> ChipSong:
	var s := SongSettings.new()
	s.vibes.assign([vibe])
	s.style = style
	s.seed_text = seed_text
	return SongGenerator.generate(s)


## A patch with only operator 4 sounding: a plain sine.
func _sine_patch(ar := 31, rr := 15) -> Dictionary:
	return {"name": "Sine", "alg": 7, "fb": 0, "ops": [
		MdPatches.off(), MdPatches.off(), MdPatches.off(),
		MdPatches.op(1, 0, ar, 0, 0, 0, rr),
	]}


func _load(fm: Ym2612, channel: int, patch: Dictionary, hz: float) -> void:
	for w in MdSong.patch_registers(channel, patch):
		fm.write(w[0], w[1], w[2])
	var bf := MdSong.fm_pitch(hz)
	fm.write(channel / 3, 0xA4 + channel % 3, (bf[0] << 3) | (bf[1] >> 8))
	fm.write(channel / 3, 0xA0 + channel % 3, bf[1] & 0xFF)


func _peak(out: PackedFloat32Array, from := 0, to := -1) -> float:
	var peak := 0.0
	for i in range(from, out.size() if to < 0 else to):
		peak = maxf(peak, absf(out[i]))
	return peak


func test_fm_pitch_and_level() -> void:
	check_eq(Array(MdSong.fm_pitch(440.0)), [4, 1083], "A4 is block 4, F-number 1083")
	var fm := Ym2612.new(22050.0)
	_load(fm, 4, _sine_patch(), 440.0)
	fm.write(0, 0x28, 0xF0 | 5)
	var out := PackedFloat32Array()
	out.resize(4410)
	fm.render(out, 0, out.size())
	var crossings := 0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
	# 440 Hz for 0.2 s: about 176 sign changes.
	check_near(float(crossings), 176.0, 4.0, "plays A4 on channel 5 (port 1)")
	check_near(_peak(out, 2000), Ym2612.CHANNEL_LEVEL, 0.01, "a sine at full level")
	# 12 total level steps is 9 dB down: about 0.355 of the level.
	fm.write(1, 0x4D, 12)
	out.fill(0.0)
	fm.render(out, 0, out.size())
	check_near(_peak(out) / Ym2612.CHANNEL_LEVEL, 0.355, 0.02, "total level in 0.75 dB steps")


func test_fm_envelope() -> void:
	var fm := Ym2612.new(22050.0)
	_load(fm, 0, _sine_patch(10, 15), 220.0)
	fm.write(0, 0x28, 0xF0)
	var out := PackedFloat32Array()
	out.resize(22050)
	fm.render(out, 0, out.size())
	check(_peak(out, 0, 220) < _peak(out, 11000) * 0.5, "a slow attack starts quiet")
	check(_peak(out, 11000) > 0.2, "and reaches full level")
	fm.write(0, 0x28, 0x00)
	out.fill(0.0)
	fm.render(out, 0, 4410)
	check(_peak(out, 1000, 4410) < 0.001, "release rate 15 is over in a few milliseconds")
	check(fm.is_channel_silent(0), "released channel is silent")


func test_fm_algorithms_and_feedback() -> void:
	var fm := Ym2612.new(22050.0)
	var two := _sine_patch()
	two["ops"][1] = MdPatches.op(2, 12, 31, 0, 0, 0, 15)
	two["ops"][3]["tl"] = 12
	_load(fm, 0, two, 220.0)
	fm.write(0, 0x28, 0xF0)
	var out := PackedFloat32Array()
	out.resize(2205)
	fm.render(out, 0, out.size())
	check(_peak(out) > Ym2612.CHANNEL_LEVEL * 0.355 * 1.3, "algorithm 7 adds two carriers")
	# Algorithm 0 with operators 1 to 3 silent sounds only operator 4; with
	# operator 3 loud, it modulates 4 and the tone gets brighter.
	var chain := {"name": "Chain", "alg": 0, "fb": 0, "ops": [MdPatches.off(), MdPatches.off(), MdPatches.op(1, 127, 31, 0, 0, 0, 15), MdPatches.op(1, 0, 31, 0, 0, 0, 15)]}
	var pure := _crossings_for(chain)
	chain["ops"][2] = MdPatches.op(3, 10, 31, 0, 0, 0, 15)
	var bright := _crossings_for(chain)
	check(bright > pure * 2, "modulation adds harmonics (%d vs %d sign changes)" % [bright, pure])
	var fed := {"name": "Fed", "alg": 7, "fb": 7, "ops": [MdPatches.op(1, 0, 31, 0, 0, 0, 15), MdPatches.off(), MdPatches.off(), MdPatches.off()]}
	check(_crossings_for(fed) > pure * 2, "full feedback turns a sine noisy")


func _crossings_for(patch: Dictionary) -> int:
	var fm := Ym2612.new(22050.0)
	_load(fm, 1, patch, 220.0)
	fm.write(0, 0x28, 0xF1)
	var out := PackedFloat32Array()
	out.resize(4410)
	fm.render(out, 0, out.size())
	var crossings := 0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			crossings += 1
	return crossings


func test_arranged_parts_fit_the_chips() -> void:
	var song := _song()
	var md := MdArranger.arrange(song)
	check(md.row_count > 0, "has rows")
	check_eq(md.notes.size(), MdSong.CHANNEL_COUNT, "ten channels")
	check(absf(md.frame_hz - MdSong.FRAME_HZ) < 0.001, "NTSC frame rate")
	check_near(md.get_bpm(), song.get_bpm(), song.get_bpm() * 0.025, "keeps the tempo")
	check(md.note_count() > 300, "plays plenty of notes (%d)" % md.note_count())
	check((md.notes[MdSong.FM6] as Array).is_empty(), "FM 6 left free for samples")
	for c in [MdSong.FM1, MdSong.FM4, MdSong.FM5, MdSong.SQUARE1, MdSong.MD_NOISE]:
		check(not (md.notes[c] as Array).is_empty(), "%s plays" % MdSong.MD_CHANNEL_NAMES[c])
	for c in MdSong.CHANNEL_COUNT:
		var last := -1
		for n: Dictionary in md.notes[c]:
			var note := int(n["note"])
			check(int(n["row"]) > last, "one note per row, in order")
			last = int(n["row"])
			check(int(n["volume"]) >= 1 and int(n["volume"]) <= 15, "volume")
			var inst: Dictionary = md.instruments[int(n["instrument"])]
			check_eq(inst.has("fm"), MdSong.is_fm(c), "FM patches only on FM channels")
			if c == MdSong.MD_NOISE:
				check(note >= 0 and note <= 2, "noise rate")
			elif MdSong.is_fm(c):
				check(note >= MdSong.FM_LOWEST and note <= MdSong.FM_HIGHEST, "FM note %d" % note)
			else:
				check(note >= SmsSong.LOWEST_NOTE and note <= SmsSong.HIGHEST_NOTE, "square note %d" % note)
	check(md.report[0].begins_with("FM 1 plays the lead"), "report names the channels")
	var source: Dictionary = md.source.data
	check_eq(source["meta"]["target"], "genesis")
	check_eq(source["channels"].size(), MdSong.CHANNEL_COUNT)
	check_eq(source["channels"][MdSong.FM5]["layer"], "Drums", "FM drums export as MIDI drums")


func test_pad_chords_play_as_chords() -> void:
	var md := MdArranger.arrange(_song("cozy", "bossa_nova", "7"))
	var by_row := {}
	for v in 3:
		for n: Dictionary in md.notes[MdSong.SQUARE1 + v]:
			by_row[int(n["row"])] = int(by_row.get(int(n["row"]), 0)) + 1
	var full := 0
	for row in by_row:
		if by_row[row] >= 3:
			full += 1
	check(full > 4, "three-note chords on the squares (%d)" % full)


func test_engine_plays_and_loops() -> void:
	var md := MdArranger.arrange(_song())
	var seq := MdSequencer.new(md, 22050)
	var loops := 0
	var peak := 0.0
	var seconds := md.frames_before(md.row_count) / MdSong.FRAME_HZ + 2.0
	for i in int(seconds * 22050 / 4096):
		var frames := seq.render(4096)
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
	var md := MdArranger.arrange(song)
	var seq := MdSequencer.new(md, 22050, song.data["channels"].size())
	for c in song.data["channels"].size():
		seq.set_channel_muted(c, true)
	seq.seek_step(0)
	var peak := 0.0
	for i in 10:
		for f in seq.render(2048):
			peak = maxf(peak, absf(f.x))
	check(peak < 0.02, "silent when every part is muted (peak %s)" % peak)


func test_player_writes_only_changes() -> void:
	var md := MdSong.new()
	md.groove = PackedInt32Array([2])
	md.row_count = 4
	md.looping = false
	md.section_rows = [{"name": "A", "row": 0, "length": 4}]
	md.instruments = [{"name": "Sine", "fm": _sine_patch()}, {"name": "Square", "volume": [15, 13]}]
	md.notes[MdSong.FM2] = [{"row": 0, "length": 2, "note": 69, "instrument": 0, "volume": 15, "arp": -1}]
	md.notes[MdSong.SQUARE1] = [{"row": 1, "length": 1, "note": 69, "instrument": 1, "volume": 15, "arp": -1}]
	var recorded := MdVgmWriter.record(md)
	var frames: Array = recorded["frames"]
	check_eq(frames.size(), 8, "two frames a row")
	var first := _commands(frames[0])
	check_eq(first.slice(0, 3), [[0x52, 0x22, 0x00], [0x52, 0x27, 0x00], [0x52, 0x2B, 0x00]], "LFO, timers and DAC off")
	check(first.has([0x52, 0x28, 0x01]), "FM 2 keyed off at the start")
	check(first.has([0x52, 0x4D, 0x00]), "patch loaded: operator 4's total level")
	check(first.has([0x52, 0xB1, 0x07]), "patch loaded: algorithm 7")
	var a4 := first.find([0x52, 0xA5, 0x24])
	var a0 := first.find([0x52, 0xA1, 0x3B])
	check(a4 >= 0 and a0 == a4 + 1, "pitch: block 4, F-number 1083, high byte first")
	check_eq(first[first.size() - 5], [0x52, 0x28, 0xF1], "then the key on, before the PSG")
	check_eq(first.slice(first.size() - 4), [[0x50, 0x9F], [0x50, 0xBF], [0x50, 0xDF], [0x50, 0xFF]], "PSG silent")
	check_eq(_commands(frames[1]), [], "nothing changed")
	check_eq(_commands(frames[2]), [[0x50, 0x8E], [0x50, 0x0F], [0x50, 0x90]], "square note: tone, then volume")
	check_eq(_commands(frames[3]), [[0x50, 0x92]], "its envelope steps down 2 dB")
	check_eq(_commands(frames[4]), [[0x52, 0x28, 0x01], [0x50, 0x9F]], "notes stop at their length: key off, volume off")
	check_eq(_commands(frames[7]), [], "nothing left to write")


## Splits a frame's VGM bytes into commands.
func _commands(bytes: PackedByteArray) -> Array:
	var out: Array = []
	var i := 0
	while i < bytes.size():
		var n := 2 if bytes[i] == MdVgmWriter.CMD_PSG else 3
		out.append(Array(bytes.slice(i, i + n)))
		i += n
	return out


func test_vgm_file() -> void:
	var md := MdArranger.arrange(_song())
	var recorded := MdVgmWriter.record(md)
	var vgm := MdVgmWriter.vgm_bytes(recorded, md.title, "credit")
	check_eq(vgm.slice(0, 4).get_string_from_ascii(), "Vgm ")
	check_eq(vgm.decode_u32(0x04), vgm.size() - 4, "end of file offset")
	check_eq(vgm.decode_u32(0x08), 0x160, "version 1.60")
	check_eq(vgm.decode_u32(0x0C), 3579545, "SN76489 clock")
	check_eq(vgm.decode_u32(0x2C), 7670453, "YM2612 clock")
	check_eq(vgm.decode_u32(0x18), (recorded["frames"] as Array).size() * 735, "length in samples")
	var loop_at := 0x1C + vgm.decode_u32(0x1C)
	var data_at := 0x34 + vgm.decode_u32(0x34)
	check_eq(data_at, 0x100, "data after the header")
	check(loop_at > data_at, "loop offset")
	var gd3_at := 0x14 + vgm.decode_u32(0x14)
	check_eq(vgm.slice(gd3_at, gd3_at + 4).get_string_from_ascii(), "Gd3 ", "GD3 tag")
	check_eq(vgm[gd3_at - 1], 0x66, "commands end before the tag")
	# At the loop point every patch is loaded again.
	var after_loop := vgm.slice(loop_at, loop_at + 2000)
	var patches := 0
	for i in after_loop.size() - 2:
		if (after_loop[i] == 0x52 or after_loop[i] == 0x53) and after_loop[i + 1] >= 0xB0 and after_loop[i + 1] <= 0xB2:
			patches += 1
	check(patches >= 5, "loop reloads the patches (%d)" % patches)


func test_vgm_golden() -> void:
	var md := MdArranger.arrange(_song())
	var recorded := MdVgmWriter.record(md)
	var vgm := MdVgmWriter.vgm_bytes(recorded, md.title, "golden")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(vgm)
	var lines: PackedStringArray = ["size %d" % vgm.size(), "sha256 %s" % hash.finish().hex_encode(), ""]
	var frames: Array = recorded["frames"]
	for f in mini(48, frames.size()):
		var parts: PackedStringArray = []
		for c in _commands(frames[f]):
			parts.append("".join(PackedStringArray(c.map(func(b: int) -> String: return "%02x" % b))))
		lines.append("%d: %s" % [f, " ".join(parts)])
	check_golden("genesis_song_happy_platformer.txt", "\n".join(lines) + "\n")


func test_sfx_conversion() -> void:
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var coin := MdSfx.from_sfx(SfxGenerator.make_sfx(presets["coin"], 1), "coin")
	check(coin.samples.size() > 1000, "has samples")
	for s in coin.samples:
		check_near(s * 127.0, roundf(s * 127.0), 0.001, "8-bit steps")
	var wav := coin.wav_bytes()
	check_eq(wav.slice(0, 4).get_string_from_ascii(), "RIFF")
	check_eq(wav.decode_u32(24), MdSfx.RATE, "14 kHz")
	check_eq(wav.decode_u16(34), 8, "8-bit")
	check_eq(wav.size(), 44 + coin.samples.size())
	var played := coin.render(44100)
	check_near(float(played.size()), coin.samples.size() * 44100.0 / MdSfx.RATE, 2.0, "plays at 14 kHz")
	check(_peak(played) > 0.05, "makes sound")
	check_eq(MdSfx.res_lines([coin]), "WAV sfx_coin \"coin.wav\" XGM\n")


func test_export_jobs() -> void:
	var md := MdArranger.arrange(_song())
	var job := ExportJob.for_md_song(md, {"prefix": "tune", "wav": true, "midi": true})
	while not job.done:
		job.step(1000000)
	for path in ["genesis/tune.vgm", "genesis/resources.res", "genesis/main.c", "genesis/README.txt", "midi/tune.mid", "README.txt"]:
		check(job.files.has(path), path)
	check(job.files.has("audio/tune.wav") and job.files["audio/tune.wav"].size() > 44100, "wav")
	check_eq((job.files["genesis/resources.res"] as PackedByteArray).get_string_from_utf8(), "XGM tune \"tune.vgm\"\n")
	check((job.files["genesis/main.c"] as PackedByteArray).get_string_from_utf8().contains("XGM_startPlay(tune);"), "example program")
	var presets: Dictionary = Catalog.get_default().sfx_presets
	var kit := ExportJob.for_md_sfx({"coin": SfxGenerator.make_sfx(presets["coin"], 1)}, "My kit", {"wav": true})
	while not kit.done:
		kit.step(1000000)
	for path in ["audio/coin.wav", "genesis/coin.wav", "genesis/resources.res", "genesis/README.txt", "README.txt"]:
		check(kit.files.has(path), path)
	check((kit.files["genesis/README.txt"] as PackedByteArray).get_string_from_utf8().contains("XGM_setPCM(64, sfx_coin, sizeof(sfx_coin));"), "how to load the sound")
