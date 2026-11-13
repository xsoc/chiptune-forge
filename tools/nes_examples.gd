extends SceneTree
## Writes NES example projects for CI to convert with FamiStudio:
##   godot --headless --path . -s tools/nes_examples.gd -- out_dir
## out_dir/song_<name>.txt for a few generated songs and out_dir/kit.txt for
## a sound kit, all FamiStudio text projects. Also writes out_dir/<name>.wav,
## the app's own preview of each song, to compare with FamiStudio's render.

const SONGS := [
	["happy", "platformer", "42"],
	["boss_fight", "metal", "boss"],
	["cozy", "bossa_nova", "7"],
]


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	for entry in SONGS:
		var s := SongSettings.new()
		s.vibes.assign([entry[0]])
		s.style = entry[1]
		s.seed_text = entry[2]
		var nes := NesArranger.arrange(SongGenerator.generate(s))
		var name := "song_" + ExportJob.sanitize("%s %s" % [entry[0], entry[1]])
		_write(out.path_join(name + ".txt"), FamiStudioWriter.song_project(nes, nes.title, "Chiptune Forge CI example").to_utf8_buffer())
		var seq := NesSequencer.new(nes, 44100)
		seq.seek_step(0)
		var frames := seq.render(44100 * 8)
		var bytes := ChipAudio.wav_header(frames.size() * 4, 2, 44100, -1, -1)
		var header := bytes.size()
		bytes.resize(header + frames.size() * 4)
		ChipAudio.write_pcm16_stereo(frames, bytes, header)
		_write(out.path_join(name + "_preview.wav"), bytes)
	var catalog := Catalog.get_default()
	var sounds: Array = []
	for id in ["coin", "jump", "explosion", "laser", "power_up"]:
		if catalog.sfx_presets.has(id):
			sounds.append(NesSfx.from_sfx(SfxGenerator.make_sfx(catalog.sfx_presets[id], 1), id))
	_write(out.path_join("kit.txt"), FamiStudioWriter.sfx_project(sounds, "CI kit").to_utf8_buffer())
	print("Wrote NES examples to ", out)
	quit()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
