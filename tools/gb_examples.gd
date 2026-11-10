extends SceneTree
## Writes Game Boy example projects for CI to build into ROMs:
##   godot --headless --path . -s tools/gb_examples.gd -- out_dir
## out_dir/song_<name>/ for a few generated songs (one with a reserved
## sound effect channel) and out_dir/kit/ for a sound kit.

const SONGS := [
	["happy", "platformer", "42", {}],
	["boss_fight", "metal", "boss", {"sfx_channel": 3}],
	["cozy", "bossa_nova", "7", {"sfx_channel": 1, "sfx_free": true}],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var gb := GbArranger.arrange(SongGenerator.generate(s), entry[3])
		var symbol := GbCWriter.song_symbol("%s %s" % [entry[0], entry[1]])
		_write(out.path_join(symbol), GbCWriter.song_project(gb, symbol, gb.title, "Chiptune Forge CI example"))
	var catalog := Catalog.get_default()
	var sounds: Array = []
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			sounds.append(GbSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id))
	_write(out.path_join("kit"), GbCWriter.sfx_project(sounds, "ci_kit", "CI kit"))
	print("Wrote Game Boy examples to ", out)
	quit()


func _write(dir: String, files: Dictionary) -> void:
	for path in files:
		var full: String = dir.path_join(path)
		DirAccess.make_dir_recursive_absolute(full.get_base_dir())
		var file := FileAccess.open(full, FileAccess.WRITE)
		var data: Variant = files[path]
		if data is PackedByteArray:
			file.store_buffer(data)
		else:
			file.store_string(str(data))
		file.close()
