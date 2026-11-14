class_name ExportJob
extends RefCounted
## Builds the files for an export a little at a time, so the UI stays
## responsive while audio renders (web builds have no threads). Call
## [method step] every frame until [member done], then [method build_zip].

const MIX_RATE := 44100
const BLOCK := 4096

var files: Dictionary = {}
var progress := 0.0
var done := false
var status := ""

var _tasks: Array[Callable] = []
var _task_index := 0
# The render in progress. Each block is written straight into the finished
# WAV bytes, so a long song never holds its float frames in memory.
var _r_path := ""
var _r_seq: ChipSongSequencer
var _r_gb: GbSong
var _r_nes: NesSong
var _r_total := 0
var _r_written := 0
var _r_bytes := PackedByteArray()
var _r_header := 0
var _r_fraction := 0.0


## Export for a song. Options: prefix, godot, plugin, wav, loops, stems, midi.
static func for_song(song: ChipSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(str(options.get("prefix", song.get_title())))
	if bool(options.get("godot", true)):
		job._tasks.append(func() -> bool:
			job.files["godot/%s.chipsong" % prefix] = song.to_json().to_utf8_buffer()
			if bool(options.get("plugin", true)):
				job._add_plugin("godot/")
			return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		var loops := int(options.get("loops", 1))
		job._queue_render(song, "audio/%s.wav" % prefix, loops, [])
		if bool(options.get("stems", false)):
			for layer in SongSettings.LAYERS:
				var muted: Array = []
				for c in GenContext.CHANNEL_COUNT:
					if not SongGenerator.LAYER_CHANNELS[layer].has(c):
						muted.append(c)
				job._queue_render(song, "audio/stems/%s_%s.wav" % [prefix, layer.to_lower()], loops, muted)
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._song_readme(song, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Game Boy: a GBDK-2020 project with the
## song as hUGEDriver C data, plus optional WAV (rendered through the emulated
## sound chip) and MIDI of the arranged parts. Options: prefix, wav, loops,
## midi.
static func for_gameboy_song(gb: GbSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := gb.source
	var prefix := sanitize(str(options.get("prefix", gb.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "Made with Chiptune Forge. Seed %s. %s" % [meta.get("seed", ""), meta.get("license", "")]
	job._tasks.append(func() -> bool:
		var symbol := GbCWriter.song_symbol(prefix)
		var project := GbCWriter.song_project(gb, symbol, gb.title, credit)
		for path in project:
			job.files["gameboy/" + path] = project[path]
		return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_gb = gb
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._gameboy_readme(gb, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the NES: a FamiStudio text project (which
## FamiStudio exports for its sound engine, as NSF or as a ROM), plus
## optional WAV (rendered through the emulated 2A03) and MIDI of the arranged
## parts. Options: prefix, wav, loops, midi.
static func for_nes_song(nes: NesSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := nes.source
	var prefix := sanitize(str(options.get("prefix", nes.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "Made with Chiptune Forge. Seed %s. %s" % [meta.get("seed", ""), meta.get("license", "")]
	job._tasks.append(func() -> bool:
		job.files["nes/%s.txt" % prefix] = FamiStudioWriter.song_project(nes, nes.title, credit).to_utf8_buffer()
		job.files["nes/README.txt"] = FamiStudioWriter.readme("song", "%s.txt" % prefix).to_utf8_buffer()
		return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = nes
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._nes_readme(nes, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the NES: a FamiStudio text project with one
## song per sound, plus WAVs of how each one sounds on the console.
static func for_nes_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(NesSfx.from_sfx(sounds[id], sanitize(str(id))))
	job._tasks.append(func() -> bool:
		job.files["nes/%s.txt" % prefix] = FamiStudioWriter.sfx_project(converted, kit_name).to_utf8_buffer()
		job.files["nes/README.txt"] = FamiStudioWriter.readme("sfx", "%s.txt" % prefix).to_utf8_buffer()
		return true)
	if bool(options.get("wav", true)):
		for nes_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % nes_sfx.name] = ChipAudio.encode_wav_mono(nes_sfx.render(MIX_RATE), MIX_RATE)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the NES: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"nes/    A FamiStudio project with one song per sound. See nes/README.txt to export",
			"        the sounds for FamiStudio's sound engine.",
			"audio/  One WAV per sound, as the NES plays it.",
			"",
			"Sounds:",
		]
		for nes_sfx in converted:
			var text := "  %s  (%s, %d frames)" % [nes_sfx.name, "Pulse 2" if nes_sfx.channel == NesSong.PULSE2 else "Noise", nes_sfx.frame_count()]
			if not nes_sfx.notes.is_empty():
				text += ": " + ", ".join(nes_sfx.notes)
			lines.append(text)
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Master System and Game Gear: PSGlib
## data (as a .psg file and as a C array for devkitSMS) and a VGM file, plus
## optional WAV (rendered through the emulated SN76489) and MIDI of the
## arranged parts. Options: prefix, wav, loops, midi.
static func for_sms_song(sms: SmsSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := sms.source
	var prefix := sanitize(str(options.get("prefix", sms.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "%s. Made with Chiptune Forge. Seed %s. %s" % [sms.title, meta.get("seed", ""), meta.get("license", "")]
	job._tasks.append(func() -> bool:
		var recorded := PsgWriter.record(sms)
		var psg := PsgWriter.encode(recorded)
		var blobs := {PsgWriter.symbol(prefix) + "_psg": psg}
		job.files["sms/%s.psg" % prefix] = psg
		job.files["sms/%s.vgm" % prefix] = PsgWriter.vgm_bytes(recorded)
		job.files["sms/%s_psg.c" % prefix] = PsgWriter.c_source(blobs, "%s_psg.h" % prefix, credit).to_utf8_buffer()
		job.files["sms/%s_psg.h" % prefix] = PsgWriter.c_header(blobs, PsgWriter.symbol(prefix).to_upper() + "_PSG_H", credit).to_utf8_buffer()
		job.files["sms/README.txt"] = PsgWriter.readme("song", prefix).to_utf8_buffer()
		return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = sms
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._sms_readme(sms, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Master System and Game Gear: one PSGlib
## file and one VGM per sound, the sounds as C arrays, and WAVs of how each
## one sounds on the console.
static func for_sms_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(SmsSfx.from_sfx(sounds[id], sanitize(str(id))))
	job._tasks.append(func() -> bool:
		var blobs := {}
		for sms_sfx: SmsSfx in converted:
			var recorded := PsgWriter.record(sms_sfx.to_song(), 1 << sms_sfx.channel)
			var psg := PsgWriter.encode(recorded)
			job.files["sms/%s.psg" % sms_sfx.name] = psg
			job.files["sms/%s.vgm" % sms_sfx.name] = PsgWriter.vgm_bytes(recorded)
			blobs[PsgWriter.symbol(sms_sfx.name) + "_psg"] = psg
		var comment := "%s: sound effects made with Chiptune Forge" % kit_name
		job.files["sms/%s.c" % prefix] = PsgWriter.c_source(blobs, "%s.h" % prefix, comment).to_utf8_buffer()
		job.files["sms/%s.h" % prefix] = PsgWriter.c_header(blobs, PsgWriter.symbol(prefix).to_upper() + "_H", comment).to_utf8_buffer()
		job.files["sms/README.txt"] = PsgWriter.readme("sfx", prefix, converted).to_utf8_buffer()
		return true)
	if bool(options.get("wav", true)):
		for sms_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % sms_sfx.name] = ChipAudio.encode_wav_mono(sms_sfx.render(MIX_RATE), MIX_RATE)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Master System and Game Gear: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"sms/    PSGlib data for each sound (.psg and as C arrays) and a VGM of each.",
			"        See sms/README.txt to play them over your music.",
			"audio/  One WAV per sound, as the Master System plays it.",
			"",
			"Sounds:",
		]
		for sms_sfx: SmsSfx in converted:
			var text := "  %s  (%s, %d frames)" % [sms_sfx.name, "Square 3" if sms_sfx.channel == SmsSong.SQUARE3 else "Noise", sms_sfx.frame_count()]
			if not sms_sfx.notes.is_empty():
				text += ": " + ", ".join(sms_sfx.notes)
			lines.append(text)
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for a song arranged for the Mega Drive / Genesis: a VGM for SGDK
## (which converts it to XGM music), the resource line and a minimal SGDK
## program, plus optional WAV (rendered through the emulated YM2612 and
## SN76489) and MIDI of the arranged parts. Options: prefix, wav, loops, midi.
static func for_md_song(md: MdSong, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var song := md.source
	var prefix := sanitize(str(options.get("prefix", md.title)))
	var meta: Dictionary = song.data.get("meta", {})
	var credit := "Made with Chiptune Forge. Seed %s. %s" % [meta.get("seed", ""), meta.get("license", "")]
	job._tasks.append(func() -> bool:
		var sym := PsgWriter.symbol(prefix)
		job.files["genesis/%s.vgm" % prefix] = MdVgmWriter.vgm_bytes(MdVgmWriter.record(md), md.title, credit)
		job.files["genesis/resources.res"] = (MdVgmWriter.res_line(sym, prefix + ".vgm") + "\n").to_utf8_buffer()
		job.files["genesis/main.c"] = MdVgmWriter.main_c(sym, md.title).to_utf8_buffer()
		job.files["genesis/README.txt"] = MdVgmWriter.readme(prefix).to_utf8_buffer()
		return true)
	if bool(options.get("midi", false)):
		job._tasks.append(func() -> bool:
			job.files["midi/%s.mid" % prefix] = MidiWriter.encode(song)
			return true)
	if bool(options.get("wav", true)):
		job._r_nes = md
		job._queue_render(song, "audio/%s.wav" % prefix, int(options.get("loops", 1)), [])
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._md_readme(md, prefix, options).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Mega Drive: one 8-bit, 14 kHz WAV per
## sound for SGDK's XGM driver, the resource lines, and WAVs of how each
## one sounds on the console.
static func for_md_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(MdSfx.from_sfx(sounds[id], sanitize(str(id))))
	job._tasks.append(func() -> bool:
		for md_sfx: MdSfx in converted:
			job.files["genesis/%s.wav" % md_sfx.name] = md_sfx.wav_bytes()
		job.files["genesis/resources.res"] = MdSfx.res_lines(converted).to_utf8_buffer()
		job.files["genesis/README.txt"] = MdSfx.readme(prefix, converted).to_utf8_buffer()
		return true)
	if bool(options.get("wav", true)):
		for md_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % md_sfx.name] = ChipAudio.encode_wav_mono(md_sfx.render(MIX_RATE), MIX_RATE)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Mega Drive / Genesis: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"genesis/  One 8-bit, 14 kHz WAV per sound for SGDK's XGM driver, and resources.res.",
			"          See genesis/README.txt to play them over your music.",
			"audio/    One WAV per sound, 44.1 kHz, as the Mega Drive plays it.",
			"",
			"Sounds:",
		]
		for md_sfx: MdSfx in converted:
			lines.append("  %s  (%.2f s)" % [MdSfx.symbol(md_sfx.name), md_sfx.seconds()])
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for sound effects on the Game Boy: a GBDK-2020 project with the
## sounds as cf_sfx data, plus WAVs of how each one sounds on the console.
static func for_gameboy_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	var converted: Array = []
	var ids := sounds.keys()
	ids.sort()
	for id in ids:
		converted.append(GbSfx.from_sfx(sounds[id], sanitize(str(id))))
	job._tasks.append(func() -> bool:
		var project := GbCWriter.sfx_project(converted, prefix, kit_name)
		for path in project:
			job.files["gameboy/" + path] = project[path]
		return true)
	if bool(options.get("wav", true)):
		for gb_sfx in converted:
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % gb_sfx.name] = ChipAudio.encode_wav_mono(gb_sfx.render(MIX_RATE), MIX_RATE)
				return true)
	job._tasks.append(func() -> bool:
		var lines: Array[String] = [
			"Sound kit for the Game Boy: %s" % prefix,
			"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
			"",
			"gameboy/  A GBDK-2020 project: the sounds, the cf_sfx player and an example ROM.",
			"          See gameboy/README.txt to build it and use the sounds in your game.",
			"audio/    One WAV per sound, as the Game Boy plays it.",
			"",
			"Sounds:",
		]
		for gb_sfx in converted:
			var text := "  %s  (%s, %s, %d frames)" % [gb_sfx.name, GbCWriter.sfx_symbol(gb_sfx.name), "Pulse 2" if gb_sfx.channel == GbSfx.PULSE else "Noise", gb_sfx.frame_count()]
			if not gb_sfx.notes.is_empty():
				text += ": " + ", ".join(gb_sfx.notes)
			lines.append(text)
		job.files["README.txt"] = "\n".join(lines).to_utf8_buffer()
		return true)
	return job


## Export for sound effects. [param sounds] maps ids to [ChipSfx].
static func for_sfx(sounds: Dictionary, kit_name: String, options: Dictionary) -> ExportJob:
	var job := ExportJob.new()
	var prefix := sanitize(kit_name)
	if bool(options.get("godot", true)):
		job._tasks.append(func() -> bool:
			var kit := ChipSfxKit.new()
			kit.kit_name = kit_name
			kit.sounds = sounds
			job.files["godot/%s.chipkit" % prefix] = kit.to_json().to_utf8_buffer()
			for id in sounds:
				job.files["godot/sounds/%s.chipsfx" % sanitize(id)] = sounds[id].to_json().to_utf8_buffer()
			if bool(options.get("plugin", true)):
				job._add_plugin("godot/")
			return true)
	if bool(options.get("wav", true)):
		for id in sounds:
			var sfx: ChipSfx = sounds[id]
			job._tasks.append(func() -> bool:
				job.files["audio/%s.wav" % sanitize(id)] = ChipAudio.encode_wav_mono(sfx.render(MIX_RATE), MIX_RATE)
				return true)
	job._tasks.append(func() -> bool:
		job.files["README.txt"] = job._sfx_readme(sounds, prefix).to_utf8_buffer()
		return true)
	return job


## Lower-case, underscores, letters and digits only: safe for files and C.
static func sanitize(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if out != "" else "export"


## Does work for up to [param budget_usec] microseconds.
func step(budget_usec := 12000) -> void:
	var start := Time.get_ticks_usec()
	while not done and Time.get_ticks_usec() - start < budget_usec:
		if _task_index >= _tasks.size():
			done = true
			progress = 1.0
			status = "Done"
			break
		if _tasks[_task_index].call():
			_task_index += 1
		progress = (_task_index + _r_fraction) / float(maxi(_tasks.size(), 1))


func build_zip() -> PackedByteArray:
	var path := "user://export_tmp.zip"
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return PackedByteArray()
	var names := files.keys()
	names.sort()
	for name in names:
		zip.start_file(name)
		zip.write_file(files[name])
		zip.close_file()
	zip.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes


func _queue_render(song: ChipSong, path: String, loops: int, muted: Array) -> void:
	_tasks.append(func() -> bool:
		if _r_path != path:
			_start_render(song, path, loops, muted)
		var chunk := _r_seq.render(mini(BLOCK, _r_total - _r_written))
		ChipAudio.write_pcm16_stereo(chunk, _r_bytes, _r_header + _r_written * 4)
		_r_written += chunk.size()
		_r_fraction = _r_written / float(maxi(_r_total, 1))
		if _r_written < _r_total and not chunk.is_empty():
			return false
		files[path] = _finish_render()
		return true)


func _start_render(song: ChipSong, path: String, loops: int, muted: Array) -> void:
	if _r_gb:
		_r_seq = GbSequencer.new(_r_gb, MIX_RATE)
	elif _r_nes is MdSong:
		_r_seq = MdSequencer.new(_r_nes, MIX_RATE)
	elif _r_nes is SmsSong:
		_r_seq = SmsSequencer.new(_r_nes, MIX_RATE)
	elif _r_nes:
		_r_seq = NesSequencer.new(_r_nes, MIX_RATE)
	else:
		_r_seq = ChipSongSequencer.new(song, MIX_RATE)
	for c in muted:
		_r_seq.set_channel_muted(c, true)
	_r_total = _r_seq.get_loop_start_frame() + (_r_seq.get_loop_end_frame() - _r_seq.get_loop_start_frame()) * maxi(loops, 1)
	if not _r_seq.looping:
		_r_total = _r_seq.get_length_frames() + int(1.5 * MIX_RATE)
	_r_seq.seek_step(0)
	_r_path = path
	_r_written = 0
	_r_fraction = 0.0
	_r_bytes = _wav_header(_r_total)
	_r_header = _r_bytes.size()
	_r_bytes.resize(_r_header + _r_total * 4)
	status = "Rendering %s" % path.get_file()


func _finish_render() -> PackedByteArray:
	var bytes := _r_bytes
	if _r_written < _r_total:
		# The sequencer ran out early: trim the data and fix the sizes.
		bytes.resize(_r_header + _r_written * 4)
		var header := _wav_header(_r_written)
		for i in header.size():
			bytes[i] = header[i]
	bytes.append_array(ChipAudio.wav_loop_chunk(MIX_RATE, _loop_begin(), _loop_end()))
	_r_path = ""
	_r_seq = null
	_r_bytes = PackedByteArray()
	_r_fraction = 0.0
	return bytes


func _wav_header(frames: int) -> PackedByteArray:
	return ChipAudio.wav_header(frames * 4, 2, MIX_RATE, _loop_begin(), _loop_end())


func _loop_begin() -> int:
	return _r_seq.get_loop_start_frame() if _r_seq.looping else -1


func _loop_end() -> int:
	return _r_seq.get_loop_end_frame() if _r_seq.looping else -1


func _add_plugin(base: String) -> void:
	_copy_dir("res://addons/chipforge", base + "addons/chipforge")


func _copy_dir(from: String, to: String) -> void:
	var dir := DirAccess.open(from)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".import") or file.ends_with(".uid"):
			continue
		var bytes := FileAccess.get_file_as_bytes(from.path_join(file))
		if not bytes.is_empty():
			files[to.path_join(file)] = bytes
	for sub in dir.get_directories():
		_copy_dir(from.path_join(sub), to.path_join(sub))


func _song_readme(song: ChipSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = song.data["meta"]
	return "\n".join([
		"%s" % song.get_title(),
		"Made with Chiptune Forge. Seed %s, %s, %d BPM." % [meta.get("seed", ""), meta.get("key", ""), int(song.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		"godot/  The song for the Chiptune Forge Godot plugin (Godot 4.3 or later).",
		"        1. Copy godot/addons/chipforge into your project's addons folder.",
		"        2. Enable it in Project Settings > Plugins.",
		"        3. Copy godot/%s.chipsong into your project. It imports as a ChipSong." % prefix,
		"        4. Add a ChipMusicPlayer node, assign the song, and call play().",
		"        Adaptive music: $Music.set_state(\"combat\") or $Music.intensity = 0.72.",
		"audio/  WAV, 44.1 kHz, 16-bit. Looping songs carry loop points in the smpl chunk.",
		"midi/   One track per chip channel, drums on channel 10." if bool(options.get("midi", false)) else "",
	])


func _gameboy_readme(gb: GbSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = gb.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the Game Boy" % gb.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(gb.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		"gameboy/  A GBDK-2020 project: the song as hUGEDriver data, an example main.c and a Makefile",
		"          that builds a ROM. See gameboy/README.txt.",
		"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated Game Boy sound chip." if bool(options.get("wav", true)) else "",
		"midi/     The four arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(gb.report).map(func(line: String) -> String: return "  " + line)),
	])


func _nes_readme(nes: NesSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = nes.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the NES" % nes.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(nes.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		"nes/     %s.txt, a FamiStudio project. Open it in FamiStudio (File > Import) to" % prefix,
		"         export it for FamiStudio's sound engine, as NSF or as a ROM. See nes/README.txt.",
		"audio/   WAV, 44.1 kHz, 16-bit, rendered through an emulated NES sound chip." if bool(options.get("wav", true)) else "",
		"midi/    The four arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(nes.report).map(func(line: String) -> String: return "  " + line)),
	])


func _sms_readme(sms: SmsSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = sms.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the Master System and Game Gear" % sms.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(sms.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		"sms/     %s.psg, PSGlib data, also as a C array for devkitSMS, and %s.vgm." % [prefix, prefix],
		"         See sms/README.txt to play it in your game.",
		"audio/   WAV, 44.1 kHz, 16-bit, rendered through an emulated SN76489." if bool(options.get("wav", true)) else "",
		"midi/    The four arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(sms.report).map(func(line: String) -> String: return "  " + line)),
	])


func _md_readme(md: MdSong, prefix: String, options: Dictionary) -> String:
	var meta: Dictionary = md.source.data.get("meta", {})
	return "\n".join([
		"%s, arranged for the Mega Drive / Genesis" % md.title,
		"Made with Chiptune Forge. Seed %s, %s, %d BPM on the console." % [meta.get("seed", ""), meta.get("key", ""), int(md.get_bpm())],
		"",
		str(meta.get("license", "")),
		"",
		"genesis/  %s.vgm (YM2612 and SN76489), with resources.res and main.c for SGDK." % prefix,
		"          See genesis/README.txt to play it in your game.",
		"audio/    WAV, 44.1 kHz, 16-bit, rendered through an emulated YM2612 and SN76489." if bool(options.get("wav", true)) else "",
		"midi/     The ten arranged parts, one track each." if bool(options.get("midi", false)) else "",
		"",
		"Arrangement:",
		"\n".join(Array(md.report).map(func(line: String) -> String: return "  " + line)),
	])


func _sfx_readme(sounds: Dictionary, prefix: String) -> String:
	var ids: Array = []
	for id in sounds:
		ids.append("  %s  (%s)" % [id, SfxGenerator.c_id(id)])
	return "\n".join([
		"Sound kit: %s" % prefix,
		"Made with Chiptune Forge. You own these sounds and may use them for any purpose, including commercially.",
		"",
		"godot/  The kit for the Chiptune Forge Godot plugin. Copy addons/chipforge into your project,",
		"        enable the plugin, add a ChipSfxPlayer node, assign %s.chipkit and call $Sfx.play(\"id\")." % prefix,
		"audio/  One WAV per sound, 44.1 kHz, 16-bit mono.",
		"",
		"Sounds:",
		"\n".join(ids),
	])
