extends SceneTree
## Writes a SNES example project for CI to build with PVSnesLib:
##   godot --headless --path . -s tools/snes_examples.gd -- out_dir
## out_dir/project is a PVSnesLib project: res/ holds the first song as an
## Impulse Tracker module, and the Makefile and main.c the export writes.
## out_dir/sfx is the same with the README's sound effect code added.
## out_dir also gets each song's module (song_<name>.it), the BRR the app
## expects smconv to make from each sample (sample_<name>.brr), and
## song_<name>_preview.wav, the app's own preview, to compare with how the
## built ROM sounds (and _preview_tracker.wav, the same at Impulse Tracker's
## tick rate, to compare with a tracker).

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var project := out.path_join("project")
	DirAccess.make_dir_recursive_absolute(project.path_join("res"))
	var first := ""
	var samples := {}
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var started := Time.get_ticks_msec()
		var snes := SnesArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		var it := ItWriter.module_bytes(snes)
		_write(out.path_join(name + ".it"), it)
		for sample in snes.samples:
			samples[sample] = true
		print("%s: arranged and written in %d ms, %d bytes" % [name, Time.get_ticks_msec() - started, it.size()])
		if first == "":
			first = name
			_write(project.path_join("res/%s.it" % name), it)
			_write(project.path_join("Makefile"), ItWriter.makefile(name).to_utf8_buffer())
			_write(project.path_join("main.c"), ItWriter.main_c(name, "Chiptune Forge CI").to_utf8_buffer())
			started = Time.get_ticks_msec()
			var seq := SnesSequencer.new(snes, 44100)
			seq.seek_step(0)
			var frames := seq.render(44100 * 12)
			print("  12 s preview rendered in %d ms" % (Time.get_ticks_msec() - started))
			_write(out.path_join(name + "_preview.wav"), ChipAudio.encode_wav_stereo(frames, 44100))
			# The same at Impulse Tracker's tick rate, to compare with a
			# tracker's playback (trackers run about 2% faster than SNESMod).
			var tracker := SnesArranger.arrange(SongGenerator.generate(s))
			tracker.frame_hz = tracker.tempo * 0.4
			var tseq := SnesSequencer.new(tracker, 44100)
			tseq.seek_step(0)
			_write(out.path_join(name + "_preview_tracker.wav"), ChipAudio.encode_wav_stereo(tseq.render(44100 * 12), 44100))
	for sample in samples:
		_write(out.path_join("sample_%s.brr" % sample), SnesSamples.brr(sample)["data"])
	# Sound effects: the README's setup in a program that also plays music.
	var catalog := Catalog.get_default()
	var sounds: Array = []
	var sfx_dir := out.path_join("sfx")
	DirAccess.make_dir_recursive_absolute(sfx_dir.path_join("res"))
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			var sfx := SnesSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id)
			sounds.append(sfx)
			_write(sfx_dir.path_join(sfx.name + ".brr"), sfx.brr_bytes())
	_write(sfx_dir.path_join("data.asm"), SnesSfx.data_asm(sounds).to_utf8_buffer())
	_write(sfx_dir.path_join("res/%s.it" % first), FileAccess.get_file_as_bytes(project.path_join("res/%s.it" % first)))
	_write(sfx_dir.path_join("Makefile"), ItWriter.makefile(first).to_utf8_buffer())
	var readme := SnesSfx.readme("CI", sounds)
	var setup: PackedStringArray = []
	var decls: PackedStringArray = []
	for line in readme.split("\n"):
		if line.begins_with("  extern") or line.begins_with("  brrsamples"):
			decls.append(line.strip_edges())
		elif line.begins_with("  spcAllocate") or line.begins_with("  spcSetSoundEntry"):
			setup.append("    " + line.strip_edges())
	setup.append("    spcPlaySound(0);")
	var main := ItWriter.main_c(first, "Chiptune Forge CI sound effects")
	main = main.replace("extern char SOUNDBANK__;", "extern char SOUNDBANK__;\n" + "\n".join(decls))
	main = main.replace("    spcPlay(0);", "    spcPlay(0);\n" + "\n".join(setup))
	_write(sfx_dir.path_join("main.c"), main.to_utf8_buffer())
	print("Wrote the SNES example projects to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
