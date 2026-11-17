extends SceneTree
## Writes Game Boy Advance example projects for CI to build with devkitARM
## and Maxmod:
##   godot --headless --path . -s tools/gba_examples.gd -- out_dir
## out_dir/project plays the first song (audio/<name>.it, Makefile, main.c).
## out_dir/sfx is the same with sound effects (audio/*.wav) played every two
## seconds over the music. out_dir also gets each song's module and, for
## the first song, <name>_preview.wav, the app's own preview, to compare
## with the module played elsewhere and with the built ROM.

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var first: GbaSong = null
	var first_name := ""
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var started := Time.get_ticks_msec()
		var gba := GbaArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		var it := GbaWriter.module_bytes(gba)
		_write(out.path_join(name + ".it"), it)
		print("%s: arranged and written in %d ms, %d bytes" % [name, Time.get_ticks_msec() - started, it.size()])
		if first == null:
			first = gba
			first_name = name
			var seq := GbaSequencer.new(gba, 44100)
			seq.seek_step(0)
			_write(out.path_join(name + "_preview.wav"), ChipAudio.encode_wav_stereo(seq.render(44100 * 12), 44100))
	var catalog := Catalog.get_default()
	var sounds: Array = []
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			sounds.append(GbaSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id))
	for dir in ["project", "sfx"]:
		var path := out.path_join(dir)
		DirAccess.make_dir_recursive_absolute(path.path_join("audio"))
		_write(path.path_join("audio/%s.it" % first_name), GbaWriter.module_bytes(first))
		var symbols := PackedStringArray()
		if dir == "sfx":
			for sfx: GbaSfx in sounds:
				_write(path.path_join("audio/%s.wav" % sfx.name), sfx.wav_bytes())
				symbols.append(GbaSfx.symbol(sfx.name))
		_write(path.path_join("Makefile"), GbaWriter.makefile(first_name).to_utf8_buffer())
		_write(path.path_join("main.c"), GbaWriter.main_c("Chiptune Forge CI", ItWriter.module_id(first_name + ".it"), symbols).to_utf8_buffer())
	print("Wrote the Game Boy Advance example projects to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
