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
