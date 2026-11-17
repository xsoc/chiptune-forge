extends SceneTree
## Writes PC Engine example projects for CI to build with HuCC:
##   godot --headless --path . -s tools/pce_examples.gd -- out_dir
## out_dir/project plays the first song with our C player (song.bin,
## pce_player.c, main.c, Makefile). out_dir/sfx is the same with sound
## effects (sfx.bin) played every two seconds over the music. out_dir also
## gets each song's data (song_<name>.bin) and, for the first song,
## song_<name>_preview.wav, the app's own preview, to compare with how the
## built ROM sounds.

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var first: PceSong = null
	var first_name := ""
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var started := Time.get_ticks_msec()
		var pce := PceArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		var data := PceWriter.song_bytes(pce)
		DirAccess.make_dir_recursive_absolute(out)
		_write(out.path_join(name + ".bin"), data)
		print("%s: arranged and written in %d ms, %d bytes" % [name, Time.get_ticks_msec() - started, data.size()])
		if first == null:
			first = pce
			first_name = name
			started = Time.get_ticks_msec()
			var seq := PceSequencer.new(pce, 44100)
			seq.seek_step(0)
			var frames := seq.render(44100 * 12)
			print("  12 s preview rendered in %d ms" % (Time.get_ticks_msec() - started))
			_write(out.path_join(name + "_preview.wav"), ChipAudio.encode_wav_stereo(frames, 44100))
	var catalog := Catalog.get_default()
	var sounds: Array = []
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			sounds.append(PceSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id))
	for dir in ["project", "sfx"]:
		var path := out.path_join(dir)
		DirAccess.make_dir_recursive_absolute(path)
		_write(path.path_join("song.bin"), PceWriter.song_bytes(first))
		_write(path.path_join("pce_player.c"), PceWriter.player_c().to_utf8_buffer())
		_write(path.path_join("Makefile"), PceWriter.makefile(first_name).to_utf8_buffer())
		var count := sounds.size() if dir == "sfx" else 0
		_write(path.path_join("main.c"), PceWriter.main_c("Chiptune Forge CI", count).to_utf8_buffer())
		if count > 0:
			_write(path.path_join("sfx.bin"), PceWriter.sfx_bytes(sounds))
	print("Wrote the PC Engine example projects to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
